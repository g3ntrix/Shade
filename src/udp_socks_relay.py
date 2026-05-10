from __future__ import annotations
"""
SOCKS5 UDP_ASSOCIATE relay (RFC 1928 §7).

Bridges UDP datagrams between a SOCKS5 client (phone, TV, etc.) and the
Apps-Script-fronted tunnel-node, using the same JSON ``ops`` batch
protocol the Rust client uses for TCP. The tunnel-node already speaks
``udp_open`` / ``udp_data`` / ``close`` — see
``temp/MasterHttpRelayVPN-RUST-main/tunnel-node/src/main.rs``.

Architecture (single ASSOCIATE):

    phone ─UDP/SOCKS5§7─▶ ┌──────────────┐  uplink Q
                          │  this module │ ───────────▶ batch_sender
    phone ◀─UDP/SOCKS5§7─ └──────────────┘ ◀── pkts/r[]
                                  ▲
                                  │ idle 500ms → poll batch
                                  └─ poll_task

Lifetime is tied to the SOCKS5 control TCP connection (RFC 1928 §6:
"A UDP association terminates when the TCP connection that the UDP
ASSOCIATE request arrived on terminates"). When ``control_reader``
hits EOF, all sessions are closed and the UDP socket is released.
"""

import asyncio
import base64
import logging
import socket
import struct
import time
import uuid
from typing import Optional

log = logging.getLogger("UdpRelay")

# Mirror Rust `MAX_UDP_PAYLOAD_BYTES`. Datagrams larger than this are
# pathological — silently drop instead of paying base64 overhead.
MAX_UDP_PAYLOAD_BYTES = 9 * 1024

# Rust `MAX_UDP_SESSIONS_PER_ASSOCIATE`. STUN / DNS fanout produces
# dozens of distinct (host, port) targets; 256 is generous.
MAX_SESSIONS = 256

# Idle session reaper threshold. Matches Rust's 120 s.
SESSION_IDLE_TIMEOUT = 120.0

# Idle ASSOCIATE poll cadence. With no uplink datagrams, we still need
# to drain downlink (server-pushed responses) — fire an empty batch
# this often. The tunnel-node holds open polls up to its long-poll
# deadline (~5 s) so this is the *floor* between polls, not the
# request frequency.
POLL_IDLE_INTERVAL = 0.5

# Cap on ops in a single batch (Rust constant).
MAX_BATCH_OPS = 50

# How long the sender waits for additional uplink datagrams before
# flushing a batch. Keeps small bursts together without adding much
# latency. Rust uses 200 ms but Apps Script roundtrips dominate, so a
# tighter window is fine.
COALESCE_WINDOW = 0.05


def _build_socks5_udp_frame(atyp: int, addr_bytes: bytes, port: int, payload: bytes) -> bytes:
    """Wrap a payload in a SOCKS5 §7 UDP response frame.

    [RSV(2)=0][FRAG(1)=0][ATYP(1)][DST.ADDR(var)][DST.PORT(2 BE)][DATA]
    """
    return b"\x00\x00\x00" + bytes([atyp]) + addr_bytes + struct.pack("!H", port) + payload


def _parse_socks5_udp_frame(buf: bytes) -> Optional[tuple[int, bytes, str, int, bytes]]:
    """Parse an inbound SOCKS5 §7 UDP datagram.

    Returns (atyp, addr_bytes, host, port, payload) or None if malformed
    or fragmentation requested (FRAG != 0). FRAG is rare in practice and
    the Rust impl drops it too; nothing important uses it.
    """
    if len(buf) < 4:
        return None
    rsv1, rsv2, frag, atyp = buf[0], buf[1], buf[2], buf[3]
    if rsv1 != 0 or rsv2 != 0:
        return None
    if frag != 0:
        return None
    p = 4
    if atyp == 0x01:  # IPv4
        if len(buf) < p + 4 + 2:
            return None
        addr_bytes = buf[p:p + 4]
        host = ".".join(str(b) for b in addr_bytes)
        p += 4
    elif atyp == 0x03:  # Domain
        if len(buf) < p + 1:
            return None
        ln = buf[p]
        p += 1
        if len(buf) < p + ln + 2 or ln == 0:
            return None
        addr_bytes = buf[p:p + ln]
        try:
            host = addr_bytes.decode("ascii")
        except UnicodeDecodeError:
            host = addr_bytes.decode("latin-1", errors="replace")
        p += ln
    elif atyp == 0x04:  # IPv6
        if len(buf) < p + 16 + 2:
            return None
        addr_bytes = buf[p:p + 16]
        host = ":".join(f"{(addr_bytes[i] << 8) | addr_bytes[i + 1]:x}" for i in range(0, 16, 2))
        p += 16
    else:
        return None
    port = (buf[p] << 8) | buf[p + 1]
    payload = buf[p + 2:]
    return (atyp, bytes(addr_bytes), host, port, payload)


async def _serve_dns(fronter, query: bytes, atyp: int, addr_bytes: bytes,
                     port: int, transport: asyncio.DatagramTransport,
                     peer: tuple[str, int], script_id: str) -> None:
    """Resolve a single DNS UDP query via the TCP tunnel and reply in
    SOCKS5 §7 framing. Echoes the original DST atyp/addr/port back so
    iOS clients match the response to the request they sent."""
    try:
        response = await fronter.dns_query(query, script_id=script_id)
    except Exception as e:
        log.debug("DNS resolve raised: %s", e)
        return
    if not response or transport.is_closing():
        return
    frame = _build_socks5_udp_frame(atyp, addr_bytes, port, response)
    try:
        transport.sendto(frame, peer)
    except Exception as e:
        log.debug("DNS reply sendto %s failed: %s", peer, e)


class _Session:
    """Per-target state. The same target keeps the same sid and the
    same SOCKS5 reply atyp/addr (so downlink frames echo the address
    the client used)."""
    __slots__ = ("sid", "atyp", "addr_bytes", "port", "host", "last_active")

    def __init__(self, sid: str, atyp: int, addr_bytes: bytes, port: int, host: str):
        self.sid = sid
        self.atyp = atyp
        self.addr_bytes = addr_bytes
        self.port = port
        self.host = host
        self.last_active = time.monotonic()


class _UdpAssociateProtocol(asyncio.DatagramProtocol):
    """Captures inbound datagrams from the SOCKS client onto an asyncio
    queue. Buffers downlink writes through the underlying transport."""

    def __init__(self, queue: asyncio.Queue):
        self._queue = queue
        self.transport: Optional[asyncio.DatagramTransport] = None

    def connection_made(self, transport):  # type: ignore[override]
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data, addr):  # type: ignore[override]
        try:
            self._queue.put_nowait((data, addr))
        except asyncio.QueueFull:
            # Drop on overflow — UDP is lossy by design.
            pass

    def error_received(self, exc):  # type: ignore[override]
        log.debug("UDP socket error: %s", exc)


async def handle_udp_associate(
    fronter,
    control_reader: asyncio.StreamReader,
    control_writer: asyncio.StreamWriter,
    bind_ip: str,
) -> None:
    """Bind a UDP socket on ``bind_ip``, send the SOCKS5 success reply
    with that bound address, then relay UDP between the SOCKS client
    and the tunnel-node until ``control_reader`` EOFs.

    The bound IP is chosen by ``proxy_server`` to match the IP the
    client reached us on (Mac LAN IP for phone clients), so the address
    the client puts in DST during the SOCKS5 reply is one it can route
    UDP datagrams to.
    """
    loop = asyncio.get_running_loop()
    inbound: asyncio.Queue[tuple[bytes, tuple[str, int]]] = asyncio.Queue(maxsize=512)

    # Bind the relay UDP socket. Port 0 → kernel picks free port.
    try:
        transport, protocol = await loop.create_datagram_endpoint(
            lambda: _UdpAssociateProtocol(inbound),
            local_addr=(bind_ip, 0),
            family=socket.AF_INET,
        )
    except Exception as e:
        log.error("UDP_ASSOCIATE bind on %s failed: %s", bind_ip, e)
        # Reply 0x01 (general failure) with zero BND.
        control_writer.write(b"\x05\x01\x00\x01\x00\x00\x00\x00\x00\x00")
        try:
            await control_writer.drain()
        except Exception:
            pass
        return

    bound_sock = transport.get_extra_info("socket")
    bound_ip, bound_port = bound_sock.getsockname()[:2]
    log.info("SOCKS5 UDP ASSOCIATE bound on %s:%d", bound_ip, bound_port)

    # Build SOCKS5 reply. ATYP 0x01 (IPv4) — bind_ip is always IPv4 in
    # this impl. If we ever bind v6, switch ATYP to 0x04 here.
    try:
        ip_packed = socket.inet_aton(bound_ip)
    except OSError:
        ip_packed = b"\x00\x00\x00\x00"
    reply = b"\x05\x00\x00\x01" + ip_packed + struct.pack("!H", bound_port)
    control_writer.write(reply)
    try:
        await control_writer.drain()
    except Exception:
        transport.close()
        return

    script_id = fronter.pick_script_id() if hasattr(fronter, "pick_script_id") else ""

    # (atyp, addr_bytes, port) → _Session. Domain targets bypass DNS on
    # the Mac and let the tunnel-node resolve, so addr_bytes is the raw
    # domain name in that case.
    sessions: dict[tuple[int, bytes, int], _Session] = {}
    sid_to_target: dict[str, tuple[int, bytes, int]] = {}
    pending_open: dict[tuple[int, bytes, int], asyncio.Future[Optional[str]]] = {}

    # Source-IP lock. First valid datagram pins the (ip, port) of the
    # SOCKS client; later datagrams from other addresses are dropped.
    locked_peer: Optional[tuple[str, int]] = None

    # Queue of outbound ops to the tunnel-node. Each entry:
    #   ("open", target_key, host, port, payload, future)
    #   ("data", target_key, payload)
    #   ("close", target_key)
    out_q: asyncio.Queue = asyncio.Queue(maxsize=1024)

    closing = asyncio.Event()

    def _send_to_client(sess: _Session, payload: bytes) -> None:
        if locked_peer is None or transport is None or transport.is_closing():
            return
        frame = _build_socks5_udp_frame(sess.atyp, sess.addr_bytes, sess.port, payload)
        try:
            transport.sendto(frame, locked_peer)
        except Exception as e:
            log.debug("UDP downlink sendto %s failed: %s", locked_peer, e)

    def _handle_op_result(target_key, op: str, resp: dict) -> None:
        sess = sessions.get(target_key)
        err = resp.get("e")
        if err:
            log.debug("UDP %s error target=%s: %s", op, target_key, err)
            if sess is not None:
                sessions.pop(target_key, None)
                sid_to_target.pop(sess.sid, None)
            return
        sid = resp.get("sid")
        if op == "open":
            fut = pending_open.pop(target_key, None)
            if sess is None and sid:
                # Build session retroactively from the queue entry's metadata.
                # The sender preserves it in target_key + future result.
                pass
            if sid and sess is not None:
                sess.sid = sid
                sid_to_target[sid] = target_key
            if fut is not None and not fut.done():
                fut.set_result(sid)
        if sess is not None:
            sess.last_active = time.monotonic()
        pkts = resp.get("pkts")
        if isinstance(pkts, list) and sess is not None:
            for b64 in pkts:
                if not isinstance(b64, str):
                    continue
                try:
                    raw = base64.b64decode(b64)
                except Exception:
                    continue
                if raw:
                    _send_to_client(sess, raw)
        if resp.get("eof") and sess is not None:
            sessions.pop(target_key, None)
            sid_to_target.pop(sess.sid, None)

    async def sender_task() -> None:
        """Drain ``out_q`` into batches, dispatch to fronter, demux."""
        while not closing.is_set():
            try:
                first = await asyncio.wait_for(out_q.get(), timeout=POLL_IDLE_INTERVAL)
            except asyncio.TimeoutError:
                # Idle → emit a poll batch (empty udp_data for every open sid).
                if not sessions:
                    continue
                ops = []
                op_targets: list = []
                for tgt, sess in list(sessions.items())[:MAX_BATCH_OPS]:
                    ops.append({"op": "udp_data", "sid": sess.sid})
                    op_targets.append(("data", tgt))
                try:
                    results = await fronter.tunnel_batch(ops, script_id=script_id)
                except Exception as e:
                    log.debug("UDP poll batch failed: %s", e)
                    continue
                for (op, tgt), resp in zip(op_targets, results):
                    if isinstance(resp, dict):
                        _handle_op_result(tgt, op, resp)
                continue

            # Have at least one queued op. Coalesce briefly for more.
            batch = [first]
            deadline = time.monotonic() + COALESCE_WINDOW
            while len(batch) < MAX_BATCH_OPS:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                try:
                    item = await asyncio.wait_for(out_q.get(), timeout=remaining)
                except asyncio.TimeoutError:
                    break
                batch.append(item)

            ops = []
            op_targets = []
            for entry in batch:
                kind = entry[0]
                if kind == "open":
                    _, tgt, host, port, payload, _fut = entry
                    op = {"op": "udp_open", "sid": str(uuid.uuid4()), "host": host, "port": int(port)}
                    if payload:
                        op["d"] = base64.b64encode(payload).decode()
                    # Record provisional sid on the session so the response
                    # match-by-sid case has something to look at; the
                    # authoritative sid is whatever the tunnel-node returns.
                    sess = sessions.get(tgt)
                    if sess is not None and not sess.sid:
                        sess.sid = op["sid"]
                        sid_to_target[op["sid"]] = tgt
                    ops.append(op)
                    op_targets.append(("open", tgt))
                elif kind == "data":
                    _, tgt, payload = entry
                    sess = sessions.get(tgt)
                    if sess is None or not sess.sid:
                        continue
                    op = {"op": "udp_data", "sid": sess.sid}
                    if payload:
                        op["d"] = base64.b64encode(payload).decode()
                    ops.append(op)
                    op_targets.append(("data", tgt))
                elif kind == "close":
                    _, tgt = entry
                    sess = sessions.get(tgt)
                    if sess is None or not sess.sid:
                        continue
                    ops.append({"op": "close", "sid": sess.sid})
                    op_targets.append(("close", tgt))

            # Top off with poll-ops for sids not already in this batch, so
            # downlink keeps draining alongside uplink writes.
            covered = {tgt for _, tgt in op_targets}
            for tgt, sess in sessions.items():
                if len(ops) >= MAX_BATCH_OPS:
                    break
                if tgt in covered or not sess.sid:
                    continue
                ops.append({"op": "udp_data", "sid": sess.sid})
                op_targets.append(("data", tgt))

            if not ops:
                continue

            try:
                results = await fronter.tunnel_batch(ops, script_id=script_id)
            except Exception as e:
                log.debug("UDP batch failed: %s", e)
                # Wake any pending opens with None so the inbound task
                # doesn't hang on the future.
                for entry in batch:
                    if entry[0] == "open":
                        fut = entry[5]
                        if fut is not None and not fut.done():
                            fut.set_result(None)
                continue

            for (op, tgt), resp in zip(op_targets, results):
                if isinstance(resp, dict):
                    _handle_op_result(tgt, op, resp)

    async def inbound_task() -> None:
        nonlocal locked_peer
        while not closing.is_set():
            data, src_addr = await inbound.get()
            if locked_peer is None:
                parsed = _parse_socks5_udp_frame(data)
                if parsed is None:
                    continue
                locked_peer = src_addr
                log.info("SOCKS5 UDP source-locked to %s:%d", src_addr[0], src_addr[1])
            elif src_addr[0] != locked_peer[0]:
                # Different source IP — silently drop (could be probing).
                continue
            else:
                parsed = _parse_socks5_udp_frame(data)
                if parsed is None:
                    continue
            atyp, addr_bytes, host, port, payload = parsed
            if len(payload) > MAX_UDP_PAYLOAD_BYTES:
                continue

            # DNS short-circuit. Resolve port-53 UDP queries by running
            # TCP DNS through the tunnel against a public resolver
            # (1.1.1.1, 9.9.9.9). The local network's DNS is censored, but
            # the VPS exits cleanly — the per-session UDP poll path can't
            # keep up with iOS systemwide DNS volume (Apps Script
            # concurrency starves), so we don't use it for DNS.
            if port == 53 and len(payload) >= 12 and locked_peer is not None:
                asyncio.create_task(
                    _serve_dns(
                        fronter, payload, atyp, addr_bytes, port,
                        transport, locked_peer, script_id,
                    )
                )
                continue

            target_key = (atyp, addr_bytes, port)
            sess = sessions.get(target_key)
            if sess is None:
                if len(sessions) >= MAX_SESSIONS:
                    # Evict oldest by last_active (FIFO-ish).
                    victim_key = min(sessions, key=lambda k: sessions[k].last_active)
                    victim = sessions.pop(victim_key)
                    sid_to_target.pop(victim.sid, None)
                    try:
                        out_q.put_nowait(("close", victim_key))
                    except asyncio.QueueFull:
                        pass
                sess = _Session(sid="", atyp=atyp, addr_bytes=addr_bytes, port=port, host=host)
                sessions[target_key] = sess
                fut: asyncio.Future[Optional[str]] = asyncio.get_running_loop().create_future()
                pending_open[target_key] = fut
                try:
                    out_q.put_nowait(("open", target_key, host, port, payload, fut))
                except asyncio.QueueFull:
                    sessions.pop(target_key, None)
                    pending_open.pop(target_key, None)
            else:
                sess.last_active = time.monotonic()
                if not sess.sid:
                    # Open still in flight — bundling the new payload with
                    # an in-flight open is fiddly; simplest is to drop.
                    # UDP is lossy, the app will retransmit (DNS, QUIC retry).
                    continue
                try:
                    out_q.put_nowait(("data", target_key, payload))
                except asyncio.QueueFull:
                    pass

    async def reaper_task() -> None:
        while not closing.is_set():
            await asyncio.sleep(15.0)
            now = time.monotonic()
            stale = [k for k, s in sessions.items() if now - s.last_active > SESSION_IDLE_TIMEOUT]
            for k in stale:
                sess = sessions.pop(k, None)
                if sess and sess.sid:
                    sid_to_target.pop(sess.sid, None)
                    try:
                        out_q.put_nowait(("close", k))
                    except asyncio.QueueFull:
                        pass

    async def control_watch_task() -> None:
        # SOCKS5 §6: ASSOCIATE ends when its TCP control closes.
        try:
            while not closing.is_set():
                chunk = await control_reader.read(4096)
                if chunk == b"":
                    break
        except Exception:
            pass
        closing.set()

    tasks = [
        asyncio.create_task(sender_task()),
        asyncio.create_task(inbound_task()),
        asyncio.create_task(reaper_task()),
        asyncio.create_task(control_watch_task()),
    ]
    try:
        await closing.wait()
    finally:
        # Best-effort close of all live sessions.
        live_sids = [s.sid for s in sessions.values() if s.sid]
        if live_sids:
            close_ops = [{"op": "close", "sid": sid} for sid in live_sids[:MAX_BATCH_OPS]]
            try:
                await fronter.tunnel_batch(close_ops, script_id=script_id)
            except Exception:
                pass
        for t in tasks:
            t.cancel()
        for t in tasks:
            try:
                await t
            except (asyncio.CancelledError, Exception):
                pass
        try:
            transport.close()
        except Exception:
            pass
        log.info("SOCKS5 UDP ASSOCIATE on %s:%d closed (%d sessions)",
                 bound_ip, bound_port, len(sessions))
