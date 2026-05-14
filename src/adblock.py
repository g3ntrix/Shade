"""
Adblock hosts list loader.

Downloads and caches domain blocklists at startup, then merges them into the
proxy's block-host rules.  Supports two common list formats:

  • Bare domain per line   — used by PersianBlocker Hosts files
  • Standard hosts format  — "0.0.0.0 domain.com" / "127.0.0.1 domain.com"

Comments (#), wildcards (analytics-*.example.com), and raw IP addresses are
skipped automatically.

Usage from proxy_server.py:
    from adblock import load_all, refresh_all

    # Synchronous load at startup (uses disk cache if available):
    domains = load_all(config["adblock_lists"])

    # Async background refresh (re-downloads stale lists):
    await refresh_all(config["adblock_lists"], callback=update_fn)
"""

import asyncio
import hashlib
import ipaddress
import logging
import pathlib
import re
import sys
import time
import urllib.request

log = logging.getLogger("Adblock")

_DEFAULT_MAX_AGE = 86_400          # 24 hours
_DOWNLOAD_TIMEOUT = 30             # seconds per HTTP request

# Cache sits next to the project root (parent of src/).
_CACHE_DIR = pathlib.Path(__file__).parent.parent / "adblock_cache"

# Bundled default blocklist (PersianBlocker). Lives next to this file
# unfrozen, or inside sys._MEIPASS when frozen by PyInstaller.
_DEFAULT_LIST_FILENAME = "adblock_default.txt"


def bundled_default_path() -> str | None:
    """Path to the bundled default blocklist, or None if not present."""
    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        p = pathlib.Path(meipass) / _DEFAULT_LIST_FILENAME
        if p.exists():
            return str(p)
    p = pathlib.Path(__file__).parent / _DEFAULT_LIST_FILENAME
    if p.exists():
        return str(p)
    return None


def _is_local_source(s: str) -> bool:
    return s.startswith(("/", "./", "file://"))


def _read_local(source: str) -> str | None:
    path = source[7:] if source.startswith("file://") else source
    try:
        return pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        log.warning("Adblock: local read failed (%s): %s", path, exc)
        return None

_IP_RE = re.compile(
    r"^(?:\d{1,3}\.){3}\d{1,3}$"
    r"|^[0-9a-fA-F:]{2,39}$"
)
_WILDCARD_RE = re.compile(r"[*?]")
_DOMAIN_RE = re.compile(
    r"^(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$"
)

_SKIP_NAMES = frozenset({
    "localhost", "local", "broadcasthost",
    "localhost.localdomain", "ip6-localhost",
    "ip6-loopback",
})
_HOSTS_PREFIXES = frozenset({"0.0.0.0", "127.0.0.1", "::1", "::0"})


def parse_hosts_text(text: str) -> list[str]:
    """Parse hosts-format or bare-domain-per-line text into a deduplicated domain list."""
    seen: set[str] = set()
    domains: list[str] = []

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        comment_pos = line.find(" #")
        if comment_pos != -1:
            line = line[:comment_pos].strip()

        parts = line.split()
        if len(parts) == 2 and parts[0] in _HOSTS_PREFIXES:
            domain = parts[1].lower().rstrip(".")
        elif len(parts) == 1:
            domain = parts[0].lower().rstrip(".")
        else:
            continue

        if _WILDCARD_RE.search(domain):
            continue
        if _IP_RE.match(domain):
            continue
        try:
            ipaddress.ip_address(domain)
            continue
        except ValueError:
            pass
        if domain in _SKIP_NAMES:
            continue
        if not _DOMAIN_RE.match(domain):
            continue

        if domain not in seen:
            seen.add(domain)
            domains.append(domain)

    return domains


def _cache_path(url: str) -> pathlib.Path:
    h = hashlib.sha1(url.encode()).hexdigest()[:16]
    return _CACHE_DIR / f"{h}.txt"


def _cache_is_stale(url: str, max_age: int) -> bool:
    path = _cache_path(url)
    if not path.exists():
        return True
    try:
        return (time.time() - path.stat().st_mtime) > max_age
    except OSError:
        return True


def _read_cache(url: str) -> list[str] | None:
    path = _cache_path(url)
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        return parse_hosts_text(text)
    except OSError:
        return None


def _write_cache(url: str, text: str) -> None:
    try:
        _CACHE_DIR.mkdir(parents=True, exist_ok=True)
        _cache_path(url).write_text(text, encoding="utf-8")
    except OSError as exc:
        log.warning("Adblock: cache write failed: %s", exc)


def _fetch(url: str) -> str | None:
    """Blocking HTTP GET — run inside asyncio.to_thread() for async callers."""
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Shade/adblock-updater"},
        )
        with urllib.request.urlopen(req, timeout=_DOWNLOAD_TIMEOUT) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except Exception as exc:
        log.warning("Adblock: download failed (%s): %s", url, exc)
        return None


def load_all(sources: list[str], max_age: int = _DEFAULT_MAX_AGE) -> list[str]:
    """Synchronously load all lists at proxy startup.

    Sources may be HTTP(S) URLs or local file paths (absolute, ./relative, file://).
    HTTP sources use disk cache if available (even if stale) to avoid blocking
    startup; first-run with no cache downloads immediately. Stale caches are
    refreshed later by refresh_all(). Local files are read directly on every load.
    """
    all_domains: list[str] = []
    for src in sources:
        src = src.strip()
        if not src:
            continue
        if _is_local_source(src):
            text = _read_local(src)
            if text:
                domains = parse_hosts_text(text)
                log.info("Adblock: %d domains loaded from %s",
                         len(domains), src.rsplit("/", 1)[-1])
                all_domains.extend(domains)
            continue
        cached = _read_cache(src)
        if cached is not None:
            log.info("Adblock: %d domains loaded from cache (%s)",
                     len(cached), src.split("/")[-1])
            all_domains.extend(cached)
        else:
            log.info("Adblock: no cache for %s — downloading...", src.split("/")[-1])
            text = _fetch(src)
            if text:
                _write_cache(src, text)
                domains = parse_hosts_text(text)
                log.info("Adblock: downloaded %d domains from %s",
                         len(domains), src.split("/")[-1])
                all_domains.extend(domains)
            else:
                log.warning("Adblock: could not load %s — adblock disabled for this list", src)
    return all_domains


async def refresh_all(
    sources: list[str],
    max_age: int = _DEFAULT_MAX_AGE,
    callback=None,
) -> list[str]:
    """Async background refresh. Re-downloads HTTP lists whose cache is stale.

    callback(domains: list[str]) is called after any list updates, letting
    the proxy hot-swap the active block set without restarting. Local file
    sources are skipped (they're not refreshable over the network).
    """
    all_domains: list[str] = []
    changed = False

    for src in sources:
        src = src.strip()
        if not src or _is_local_source(src):
            continue

        if not _cache_is_stale(src, max_age):
            cached = _read_cache(src) or []
            all_domains.extend(cached)
            continue

        log.info("Adblock: refreshing %s ...", src.split("/")[-1])
        text = await asyncio.to_thread(_fetch, src)
        if text:
            await asyncio.to_thread(_write_cache, src, text)
            domains = await asyncio.to_thread(parse_hosts_text, text)
            log.info("Adblock: refreshed %d domains from %s",
                     len(domains), src.split("/")[-1])
            all_domains.extend(domains)
            changed = True
        else:
            cached = _read_cache(src) or []
            all_domains.extend(cached)

    if changed and callback is not None:
        callback(all_domains)

    return all_domains
