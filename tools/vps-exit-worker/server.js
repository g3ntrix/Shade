/**
 * VPS HTTP relay — dual protocol:
 *
 * 1) Shade / mhrv-rs exit node (Apps Script second hop): POST JSON with
 *    { k, u, m?, h?, b? } where k must match EXIT_NODE_PSK. Same contract
 *    as valtown.template.ts / deployed val (response { s, h, b } or { e }).
 *
 * 2) Legacy mhr-vps-worker: POST { u, m?, h?, b? } without k (no PSK).
 *
 * Set EXIT_NODE_PSK to a strong secret (≥8 chars). Use the same value as
 * "PSK" / relay secret in Shade → Settings → Exit node.
 */
const http = require("http");
const https = require("https");
const dns = require("dns");

dns.setDefaultResultOrder("ipv4first");

const BAD_HEADERS = [
  "host",
  "x-forwarded-for",
  "x-real-ip",
  "x-forwarded-proto",
  "cf-connecting-ip",
  "connection",
  "keep-alive",
];

const SLOW_SITES = [
  "gemini.google.com",
  "ai.google.dev",
  "makersuite.google.com",
  "generativelanguage.googleapis.com",
  ".googleapis.com",
  "chatgpt.com",
  ".chatgpt.com",
  "openai.com",
  ".openai.com",
  "api.openai.com",
  ".oaistatic.com",
  ".oaiusercontent.com",
];

const TIMEOUT_SLOW_MS = 55000;
const TIMEOUT_FAST_MS = 20000;
const PLACEHOLDER_PSK = "CHANGE_ME_TO_A_STRONG_SECRET";
const EXIT_NODE_PSK = process.env.EXIT_NODE_PSK || PLACEHOLDER_PSK;

const agentOptions = { rejectUnauthorized: false, keepAlive: true };
const httpAgent = new http.Agent(agentOptions);
const httpsAgent = new https.Agent(agentOptions);

function isSlowHost(hostname) {
  if (!hostname) return false;
  const host = hostname.toLowerCase();

  for (const rule of SLOW_SITES) {
    const r = (rule || "").toLowerCase().trim();
    if (!r) continue;

    if (r.startsWith(".")) {
      const suffix = r;
      if (host.endsWith(suffix) || host === suffix.slice(1)) return true;
    } else {
      if (host === r) return true;
    }
  }
  return false;
}

function sendJson(res, httpStatus, obj) {
  res.writeHead(httpStatus, { "Content-Type": "application/json" });
  res.end(JSON.stringify(obj));
}

function sendRelayResult(res, status, headers, base64Body) {
  res.writeHead(200, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ s: status, h: headers, b: base64Body }));
}

function runUpstreamFetch(data, _reqHost, onDone) {
  let isDone = false;
  const finish = (status, headers, base64Body) => {
    if (isDone) return;
    isDone = true;
    onDone(status, headers, base64Body);
  };

  try {
    if (!data.u || typeof data.u !== "string") {
      return finish(500, {}, Buffer.from("no url").toString("base64"));
    }

    const targetUrl = new URL(data.u);
    const isHttps = targetUrl.protocol === "https:";
    const slow = isSlowHost(targetUrl.hostname);

    const method = (data.m || "GET").toUpperCase();
    const options = {
      method,
      headers: {},
      agent: isHttps ? httpsAgent : httpAgent,
      timeout: slow ? TIMEOUT_SLOW_MS : TIMEOUT_FAST_MS,
    };

    if (data.h && typeof data.h === "object") {
      for (const [key, value] of Object.entries(data.h)) {
        const lowerKey = key.toLowerCase();
        if (!BAD_HEADERS.includes(lowerKey)) {
          options.headers[key] = value;
        }
      }
    }

    const proxyReq = (isHttps ? https : http).request(
      targetUrl,
      options,
      (proxyRes) => {
        const responseHeaders = {};
        Object.keys(proxyRes.headers).forEach((key) => {
          if (key.toLowerCase() !== "transfer-encoding") {
            responseHeaders[key] = proxyRes.headers[key];
          }
        });

        const chunks = [];
        proxyRes.on("data", (chunk) => chunks.push(chunk));

        proxyRes.on("end", () => {
          finish(
            proxyRes.statusCode,
            responseHeaders,
            Buffer.concat(chunks).toString("base64"),
          );
        });
      },
    );

    proxyReq.on("timeout", () => {
      proxyReq.destroy();
      finish(504, {}, Buffer.from("Target Timeout").toString("base64"));
    });

    proxyReq.on("error", (err) => {
      finish(
        502,
        {},
        Buffer.from("Relay Error: " + err.message).toString("base64"),
      );
    });

    if (data.b && !["GET", "HEAD"].includes(method)) {
      proxyReq.write(Buffer.from(data.b, "base64"));
    }

    proxyReq.end();
  } catch (err) {
    finish(500, {}, Buffer.from("Relay logic error").toString("base64"));
  }
}

function handleExitNodeRequest(req, res, data) {
  if (EXIT_NODE_PSK === PLACEHOLDER_PSK) {
    return sendJson(res, 503, {
      e:
        "exit_node misconfigured: set EXIT_NODE_PSK in the environment " +
        "(e.g. pm2 ecosystem file) to a strong secret before accepting Shade traffic.",
    });
  }

  if (typeof data.k !== "string" || data.k !== EXIT_NODE_PSK) {
    return sendJson(res, 401, { e: "unauthorized" });
  }

  const u = String(data.u || "");
  if (!/^https?:\/\//i.test(u)) {
    return sendJson(res, 400, { e: "bad url" });
  }

  try {
    const dst = new URL(u);
    const hostHeader = String(req.headers.host || "")
      .split(":")[0]
      .toLowerCase();
    const dstHost = dst.hostname.toLowerCase();
    if (hostHeader && dstHost === hostHeader) {
      return sendJson(res, 400, { e: "exit-node loop refused" });
    }
  } catch {
    return sendJson(res, 400, { e: "bad url" });
  }

  const relayPayload = {
    u,
    m: String(data.m || "GET").toUpperCase(),
    h: data.h && typeof data.h === "object" ? data.h : undefined,
    b: typeof data.b === "string" && data.b.length > 0 ? data.b : undefined,
  };

  runUpstreamFetch(relayPayload, req.headers.host, (status, headers, b64) => {
    sendRelayResult(res, status, headers, b64);
  });
}

const server = http.createServer((req, res) => {
  const bodyParts = [];

  req.on("data", (chunk) => bodyParts.push(chunk));
  req.on("end", () => {
    let isResponded = false;

    const sendResponse = (status, headers, base64Body) => {
      if (isResponded) return;
      isResponded = true;
      sendRelayResult(res, status, headers, base64Body);
    };

    try {
      const bodyStr = Buffer.concat(bodyParts).toString();
      if (!bodyStr) {
        return sendResponse(500, {}, Buffer.from("empty").toString("base64"));
      }

      const data = JSON.parse(bodyStr);

      if (data && typeof data === "object" && Object.prototype.hasOwnProperty.call(data, "k")) {
        if (isResponded) return;
        isResponded = true;
        return handleExitNodeRequest(req, res, data);
      }

      if (!data.u) {
        return sendResponse(500, {}, Buffer.from("no url").toString("base64"));
      }

      runUpstreamFetch(data, req.headers.host, (status, headers, b64) => {
        sendResponse(status, headers, b64);
      });
    } catch (err) {
      sendResponse(500, {}, Buffer.from("Relay logic error").toString("base64"));
    }
  });
});

const port = Number(process.env.PORT || 8081);
server.listen(port, "0.0.0.0", () => {
  console.log("Rock-Solid Worker running on port " + port);
});
