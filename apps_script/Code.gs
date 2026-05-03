/**
 * MasterHttpRelay — Google Apps Script
 * 
 * DEPLOYMENT:
 *   1. Go to https://script.google.com → New project
 *   2. Delete the default code, paste THIS entire file
 *   3. Click Deploy → New deployment
 *   4. Type: Web app  |  Execute as: Me  |  Who has access: Anyone
 *   5. Copy the Deployment ID into config.json as "script_id"
 *
 * CHANGE THE AUTH KEY BELOW TO YOUR OWN SECRET!
 */

const AUTH_KEY = "CHANGE_ME_TO_A_STRONG_SECRET";

// Keep browser capability headers (sec-ch-ua*, sec-fetch-*) intact.
// Some modern apps, notably Google Meet, use them for browser gating.
// Headers that reveal the user's real IP are also stripped here as a
// second line of defence (the Python client strips them first).
const SKIP_HEADERS = {
  host: 1, connection: 1, "content-length": 1,
  "transfer-encoding": 1, "proxy-connection": 1, "proxy-authorization": 1,
  "priority": 1, te: 1,
  // IP-leaking / proxy-metadata headers
  "x-forwarded-for": 1, "x-forwarded-host": 1, "x-forwarded-proto": 1,
  "x-forwarded-port": 1, "x-real-ip": 1, "forwarded": 1, "via": 1,
};

// If fetchAll fails, only retry methods that are safe to replay.
const SAFE_REPLAY_METHODS = { GET: 1, HEAD: 1, OPTIONS: 1 };

/**
 * Second hop: POST to exit node (e.g. val.town) with the same shape it expects
 * ({k, u, m, h, b}). On failure, caller falls back to direct fetch.
 */
function _fetchViaExitNode(req) {
  try {
    var en = req.en;
    if (!en || typeof en !== "object") return null;
    var relayUrl = en.relay_url;
    var exitPsk = en.psk;
    if (
      !relayUrl ||
      typeof relayUrl !== "string" ||
      !relayUrl.match(/^https?:\/\//i) ||
      !exitPsk ||
      typeof exitPsk !== "string"
    ) {
      return null;
    }
    var inner = {
      k: exitPsk,
      u: req.u,
      m: (req.m || "GET").toUpperCase(),
    };
    if (req.h && typeof req.h === "object") inner.h = req.h;
    if (req.b) inner.b = req.b;

    var resp = UrlFetchApp.fetch(relayUrl, {
      method: "post",
      contentType: "application/json",
      payload: JSON.stringify(inner),
      muteHttpExceptions: true,
      followRedirects: true,
    });
    var text = resp.getContentText();
    var data = JSON.parse(text);
    if (data.e) return null;
    if (typeof data.s !== "number") return null;
    if (!data.h || typeof data.h !== "object") return null;
    if (typeof data.b !== "string") return null;
    return data;
  } catch (err) {
    return null;
  }
}

function doPost(e) {
  try {
    var req = JSON.parse(e.postData.contents);
    if (req.k !== AUTH_KEY) return _json({ e: "unauthorized" });

    // Batch mode: { k, q: [...] }
    if (Array.isArray(req.q)) return _doBatch(req.q);

    // Single mode
    return _doSingle(req);
  } catch (err) {
    return _json({ e: String(err) });
  }
}

function _doSingle(req) {
  if (!req.u || typeof req.u !== "string" || !req.u.match(/^https?:\/\//i)) {
    return _json({ e: "bad url" });
  }
  if (req.en && req.en.relay_url && req.en.psk) {
    var viaExit = _fetchViaExitNode(req);
    if (viaExit) {
      return _json({
        s: viaExit.s,
        h: viaExit.h,
        b: viaExit.b,
      });
    }
  }
  var opts = _buildOpts(req);
  var resp = UrlFetchApp.fetch(req.u, opts);
  return _json({
    s: resp.getResponseCode(),
    h: _respHeaders(resp),
    b: Utilities.base64Encode(resp.getContent()),
  });
}

function _doBatch(items) {
  var results = new Array(items.length);
  var fetchArgs = [];
  var fetchIndex = [];
  var fetchMethods = [];
  var i;
  var j;

  for (i = 0; i < items.length; i++) {
    var item = items[i];
    if (!item || typeof item !== "object") {
      results[i] = { e: "bad item" };
      continue;
    }
    if (!item.u || typeof item.u !== "string" || !item.u.match(/^https?:\/\//i)) {
      results[i] = { e: "bad url" };
      continue;
    }
    if (item.en && item.en.relay_url && item.en.psk) {
      var viaExit = _fetchViaExitNode(item);
      if (viaExit) {
        results[i] = {
          s: viaExit.s,
          h: viaExit.h,
          b: viaExit.b,
        };
        continue;
      }
    }
    try {
      var opts = _buildOpts(item);
      opts.url = item.u;
      fetchArgs.push(opts);
      fetchIndex.push(i);
      fetchMethods.push(String(item.m || "GET").toUpperCase());
      results[i] = null;
    } catch (err) {
      results[i] = { e: String(err) };
    }
  }

  var responses = [];
  if (fetchArgs.length > 0) {
    try {
      responses = UrlFetchApp.fetchAll(fetchArgs);
    } catch (err) {
      responses = [];
      for (j = 0; j < fetchArgs.length; j++) {
        try {
          if (!SAFE_REPLAY_METHODS[fetchMethods[j]]) {
            results[fetchIndex[j]] = {
              e: "batch fetchAll failed; unsafe method not replayed",
            };
            responses[j] = null;
            continue;
          }
          var fallbackReq = fetchArgs[j];
          var fallbackUrl = fallbackReq.url;
          var fallbackOpts = {};
          for (var key in fallbackReq) {
            if (Object.prototype.hasOwnProperty.call(fallbackReq, key) && key !== "url") {
              fallbackOpts[key] = fallbackReq[key];
            }
          }
          responses[j] = UrlFetchApp.fetch(fallbackUrl, fallbackOpts);
        } catch (singleErr) {
          results[fetchIndex[j]] = { e: String(singleErr) };
          responses[j] = null;
        }
      }
    }
  }

  var rIdx = 0;
  for (i = 0; i < items.length; i++) {
    if (results[i] !== null) continue;
    var resp = responses[rIdx++];
    if (!resp) {
      if (!results[i]) results[i] = { e: "fetch failed" };
    } else {
      results[i] = {
        s: resp.getResponseCode(),
        h: _respHeaders(resp),
        b: Utilities.base64Encode(resp.getContent()),
      };
    }
  }
  return _json({ q: results });
}

function _buildOpts(req) {
  var opts = {
    method: (req.m || "GET").toLowerCase(),
    muteHttpExceptions: true,
    followRedirects: req.r !== false,
    validateHttpsCertificates: true,
    escaping: false,
  };
  if (req.h && typeof req.h === "object") {
    var headers = {};
    for (var k in req.h) {
      if (req.h.hasOwnProperty(k) && !SKIP_HEADERS[k.toLowerCase()]) {
        headers[k] = req.h[k];
      }
    }
    opts.headers = headers;
  }
  if (req.b) {
    opts.payload = Utilities.base64Decode(req.b);
    if (req.ct) opts.contentType = req.ct;
  }
  return opts;
}

function _respHeaders(resp) {
  try {
    if (typeof resp.getAllHeaders === "function") {
      return resp.getAllHeaders();
    }
  } catch (err) {}
  return resp.getHeaders();
}

function doGet(e) {
  return HtmlService.createHtmlOutput(
    "<!DOCTYPE html><html><head><title>My App</title></head>" +
      '<body style="font-family:sans-serif;max-width:600px;margin:40px auto">' +
      "<h1>Welcome</h1><p>This application is running normally.</p>" +
      "</body></html>"
  );
}

function _json(obj) {
  var out = {};
  if (obj && typeof obj === "object" && !Array.isArray(obj)) {
    for (var k in obj) {
      if (Object.prototype.hasOwnProperty.call(obj, k)) {
        out[k] = obj[k];
      }
    }
  }
  out.cap = 2;
  return ContentService.createTextOutput(JSON.stringify(out)).setMimeType(
    ContentService.MimeType.JSON
  );
}
