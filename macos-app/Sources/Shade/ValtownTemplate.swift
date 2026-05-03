import Foundation

enum ValtownTemplate {
    private static let pskPlaceholderLine = #"const PSK = "CHANGE_ME_TO_A_STRONG_SECRET";"#
    private static let fallbackTemplate = #"""
const PSK = "CHANGE_ME_TO_A_STRONG_SECRET";

const STRIP_HEADERS = new Set([
  "host",
  "connection",
  "content-length",
  "transfer-encoding",
  "proxy-connection",
  "proxy-authorization",
  "x-forwarded-for",
  "x-forwarded-host",
  "x-forwarded-proto",
  "x-forwarded-port",
  "x-real-ip",
  "forwarded",
  "via",
]);

function decodeBase64ToBytes(input) {
  const bin = atob(input);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function encodeBytesToBase64(bytes) {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function sanitizeHeaders(h) {
  const out = {};
  if (!h || typeof h !== "object") return out;
  for (const [k, v] of Object.entries(h)) {
    if (!k) continue;
    if (STRIP_HEADERS.has(k.toLowerCase())) continue;
    out[k] = String(v ?? "");
  }
  return out;
}

export default async function (req) {
  if (PSK === "CHANGE_ME_TO_A_STRONG_SECRET") {
    return Response.json({
      e: "exit_node misconfigured: replace PSK placeholder before deploying",
    }, { status: 503 });
  }
  try {
    if (req.method !== "POST") return Response.json({ e: "method_not_allowed" }, { status: 405 });
    const body = await req.json();
    const k = String(body?.k ?? "");
    const u = String(body?.u ?? "");
    const m = String(body?.m ?? "GET").toUpperCase();
    const h = sanitizeHeaders(body?.h);
    const b64 = body?.b;
    if (k !== PSK) return Response.json({ e: "unauthorized" }, { status: 401 });
    if (!/^https?:\/\//i.test(u)) return Response.json({ e: "bad url" }, { status: 400 });

    let payload;
    if (typeof b64 === "string" && b64.length > 0) payload = decodeBase64ToBytes(b64);
    const resp = await fetch(u, { method: m, headers: h, body: payload, redirect: "manual" });
    const data = new Uint8Array(await resp.arrayBuffer());
    const respHeaders = {};
    resp.headers.forEach((value, key) => { respHeaders[key] = value; });
    return Response.json({ s: resp.status, h: respHeaders, b: encodeBytesToBase64(data) });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return Response.json({ e: message }, { status: 500 });
  }
}
"""#

    static func load() -> String {
        if let url = Bundle.main.url(forResource: "valtown.template", withExtension: "ts"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        return fallbackTemplate
    }

    /// Injects the user PSK into the template line (escapes `\` and `"` for JavaScript).
    static func withPSKEmbedded(_ psk: String) -> String {
        let escaped = psk
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return load().replacingOccurrences(
            of: pskPlaceholderLine,
            with: "const PSK = \"\(escaped)\";"
        )
    }
}
