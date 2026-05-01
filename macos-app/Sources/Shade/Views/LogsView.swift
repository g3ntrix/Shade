import SwiftUI

struct LogsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Logs")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                
                Toggle("Enable Logs", isOn: Binding(
                    get: { app.settings.enableAppLogs },
                    set: { newValue in
                        app.settings.enableAppLogs = newValue
                        app.saveSettings()
                        if !newValue { app.clearLogs() }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.trailing, 8)

                Button("Clear") { app.clearLogs() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Text("Core + TUN messages. Open this tab if something fails.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextEditor(text: .constant(joinedLogs))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08)))
                )
        }
    }

    private var joinedLogs: String {
        app.logs.map(\.text).joined(separator: "")
    }
}
