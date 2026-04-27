import SwiftUI
import AppKit

/// Step-by-step wizard that walks the user through creating a Google Apps
/// Script web-app deployment and getting the Script ID + Auth Key that Shade
/// needs. Kept entirely self-contained: the Code.gs source is embedded so
/// there's nothing to fetch.
struct SetupView: View {
    @EnvironmentObject var app: AppState
    @State private var step: Int = 0
    @State private var authKeyDraft: String = ""
    @State private var authKeyConfirmed: Bool = false

    private let steps: [Step] = [
        .init(
            title: "Create a new Apps Script project",
            body:
                """
                Open script.google.com and click New project (top-left). \
                You'll get an empty editor with a single Code.gs file already open.
                """,
            link: URL(string: "https://script.google.com/home/projects/create")
        ),
        .init(
            title: "Paste the Code.gs contents",
            body:
                """
                Select everything in the default Code.gs, delete it, then paste the \
                code below. Before saving, change the AUTH_KEY constant at the top \
                to a strong secret of your choice: you'll enter the same value into
                Shade as your Auth Key. Save with ⌘S.
                """,
            showCode: true
        ),
        .init(
            title: "Deploy as a Web app",
            body:
                """
                Click Deploy → New deployment (top-right). For "Select type" click the \
                gear icon and pick Web app. Configure it like this:

                  • Description: anything you want (e.g. "Shade relay")
                  • Execute as: Me
                  • Who has access: Anyone

                Google may ask you to authorize the script the first time:
                review the permissions and continue.
                """
        ),
        .init(
            title: "Copy the Deployment ID",
            body:
                """
                After deploying, Google shows a "Deployment ID" and a "Web app URL". \
                Copy the Deployment ID (it starts with AKfycb…). That's your Script ID.

                You now have everything:
                  • Script ID → the Deployment ID you just copied
                  • Auth Key  → the AUTH_KEY string you set in step 2
                """
        ),
        .init(
            title: "Add the profile to Shade",
            body:
                """
                Head back to the Dashboard, click + Add next to Profile, paste your \
                Script ID and Auth Key, and save. Hit Start and you're connected.
                """
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup Guide")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Get your Google Apps Script deployment running in five short steps.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                stepper
                stepCard
            }
        }
    }

    // MARK: - Stepper

    private var stepper: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.accentColor : .white.opacity(0.12))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    // MARK: - Step card

    private var stepCard: some View {
        let s = steps[step]
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.18))
                            .frame(width: 26, height: 26)
                        Text("\(step + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(s.title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Step \(step + 1) of \(steps.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text(s.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if s.showCode {
                    if authKeyConfirmed {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Auth key embedded: copy and paste the code below.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Change") {
                                    authKeyConfirmed = false
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                            }
                            CodeSnippet(code: SetupView.codeGS
                                .replacingOccurrences(
                                    of: "CHANGE_ME_TO_A_STRONG_SECRET",
                                    with: authKeyDraft.replacingOccurrences(of: "\"", with: "\\\"")
                                ))
                        }
                    } else {
                        AuthKeyPrompt(authKey: $authKeyDraft) {
                            authKeyConfirmed = true
                        }
                    }
                }

                if let link = s.link {
                    Link(destination: link) {
                        Label(link.absoluteString, systemImage: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                    }
                }

                HStack {
                    Button {
                        if step > 0 { withAnimation { step -= 1 } }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(step > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                    .disabled(step == 0)

                    Spacer()

                    if step < steps.count - 1 {
                        let isStep2MissingKey = (step == 1 && !authKeyConfirmed)
                        Button {
                            withAnimation { step += 1 }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                        .disabled(isStep2MissingKey)
                        .opacity(isStep2MissingKey ? 0.5 : 1.0)
                    }
                }
            }
        }
    }

    private struct Step {
        let title: String
        let body:  String
        var link:  URL?    = nil
        var showCode: Bool = false
    }
}

// MARK: - Auth key prompt (shown before snippet)

private struct AuthKeyPrompt: View {
    @Binding var authKey: String
    var onConfirm: () -> Void
    @State private var isVisible: Bool = false
    @State private var copied: Bool = false

    private var trimmed: String {
        authKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool { trimmed.count >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an Auth Key")
                .font(.system(size: 12, weight: .semibold))

            Text("Pick a strong secret (at least 8 characters). It will be baked into the snippet below: the same value goes into Shade's profile as the Auth Key.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    if isVisible {
                        TextField("Strong secret", text: $authKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                    } else {
                        SecureField("Strong secret", text: $authKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    Button {
                        isVisible.toggle()
                    } label: {
                        Image(systemName: isVisible ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(authKey, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Button {
                    authKey = Self.generateRandomKey()
                } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Generate a strong random key")

                Button {
                    onConfirm()
                } label: {
                    Text("Use This Key")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isValid)
            }

            if !authKey.isEmpty && !isValid {
                Text("Too short: use 8 or more characters.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private static func generateRandomKey(length: Int = 32) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] })
    }
}

// MARK: - Code snippet (copyable, scrollable)

private struct CodeSnippet: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Code.gs")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? .green : .accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.04))

            Divider().opacity(0.3)

            ScrollView([.vertical]) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 260)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Embedded Code.gs

extension SetupView {
    static let codeGS: String = #"""
const AUTH_KEY = "CHANGE_ME_TO_A_STRONG_SECRET";

const SKIP_HEADERS = {
  host: 1, connection: 1, "content-length": 1,
  "transfer-encoding": 1, "proxy-connection": 1, "proxy-authorization": 1,
};

function doPost(e) {
  try {
    var req = JSON.parse(e.postData.contents);
    if (req.k !== AUTH_KEY) return _json({ e: "unauthorized" });
    if (Array.isArray(req.q)) return _doBatch(req.q);
    return _doSingle(req);
  } catch (err) {
    return _json({ e: String(err) });
  }
}

function _doSingle(req) {
  if (!req.u || typeof req.u !== "string" || !req.u.match(/^https?:\/\//i)) {
    return _json({ e: "bad url" });
  }
  var opts = _buildOpts(req);
  var resp = UrlFetchApp.fetch(req.u, opts);
  return _json({
    s: resp.getResponseCode(),
    h: resp.getHeaders(),
    b: Utilities.base64Encode(resp.getContent()),
  });
}

function _doBatch(items) {
  var fetchArgs = [];
  var errorMap = {};
  for (var i = 0; i < items.length; i++) {
    var item = items[i];
    if (!item.u || typeof item.u !== "string" || !item.u.match(/^https?:\/\//i)) {
      errorMap[i] = "bad url";
      continue;
    }
    var opts = _buildOpts(item);
    opts.url = item.u;
    fetchArgs.push({ _i: i, _o: opts });
  }
  var responses = [];
  if (fetchArgs.length > 0) {
    responses = UrlFetchApp.fetchAll(fetchArgs.map(function(x) { return x._o; }));
  }
  var results = [];
  var rIdx = 0;
  for (var i = 0; i < items.length; i++) {
    if (errorMap.hasOwnProperty(i)) {
      results.push({ e: errorMap[i] });
    } else {
      var resp = responses[rIdx++];
      results.push({
        s: resp.getResponseCode(),
        h: resp.getHeaders(),
        b: Utilities.base64Encode(resp.getContent()),
      });
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

function doGet(e) {
  return HtmlService.createHtmlOutput("<h1>Welcome</h1><p>Shade relay is running.</p>");
}

function _json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
"""#
}
