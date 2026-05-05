import SwiftUI

// MARK: - Badge

struct ValBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.up.right.circle.fill")
                .font(.system(size: 8, weight: .bold))
            Text("tunnel")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.mint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(.mint.opacity(0.15))
                .overlay(Capsule().stroke(.mint.opacity(0.35), lineWidth: 0.5))
        )
        .fixedSize()
    }
}

// MARK: - Settings panel (tunnels + routing next to exit mode)

struct ExitNodeSettingsPanel: View {
    @Binding var settings: AppSettings
    @State private var showPicker = false
    @State private var showAddSheet = false
    @State private var editTarget: ExitNodeProfile? = nil

    private let accent: Color = .mint

    private var valid: [ExitNodeProfile] { settings.validExitNodeProfiles() }

    private var active: ExitNodeProfile? {
        guard let id = settings.activeExitNodeProfileID else { return valid.first }
        return valid.first { $0.id == id } ?? valid.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Full Tunnel servers (URL + key) used by Setup guides to generate CodeFull.gs quickly.")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Use Full Tunnel mode in Advanced to activate CodeFull traffic path.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if valid.isEmpty && !settings.exitNodeProfiles.isEmpty {
                Text("Saved tunnels need a valid https URL and PSK (≥ 8 characters).")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            if valid.count >= 2 {
                HStack(spacing: 6) {
                    Text("Tunnel LB")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $settings.enableExitNodeLB)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .disabled(false)
                }
            }

            HStack(spacing: 8) {
                Label("Tunnels", systemImage: "arrow.turn.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Spacer(minLength: 4)
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .help("Add tunnel server")
            }

            if settings.exitNodeProfiles.isEmpty {
                Text("No tunnel servers yet. Add the tunnel URL and key from your VPS setup.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Button { showPicker = true } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(active?.name ?? "Select tunnel")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if active != nil { ValBadge() }
                            }
                            if let p = active {
                                let u = p.relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !u.isEmpty {
                                    Text(u.count > 34 ? String(u.prefix(34)) + "…" : u)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(false)

            }

            Divider().opacity(0.12)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .sheet(isPresented: $showPicker) {
            ExitNodePickerSheet(
                profiles: $settings.exitNodeProfiles,
                activeExitNodeProfileID: $settings.activeExitNodeProfileID,
                enableExitNodeLB: $settings.enableExitNodeLB
            )
        }
        .sheet(item: $editTarget) { profile in
            ExitNodeEditSheet(
                profile: profile,
                profiles: $settings.exitNodeProfiles,
                activeExitNodeProfileID: $settings.activeExitNodeProfileID
            )
        }
        .sheet(isPresented: $showAddSheet) {
            ExitNodeEditSheet(
                profile: nil,
                profiles: $settings.exitNodeProfiles,
                activeExitNodeProfileID: $settings.activeExitNodeProfileID
            )
        }
    }
}

// MARK: - Picker sheet

struct ExitNodePickerSheet: View {
    @Binding var profiles: [ExitNodeProfile]
    @Binding var activeExitNodeProfileID: UUID?
    @Binding var enableExitNodeLB: Bool

    @Environment(\.dismiss) var dismiss
    @State private var showAddSheet = false
    @State private var editTarget: ExitNodeProfile? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Exit relays")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.mint)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(profiles) { p in
                        ExitNodeRow(
                            profile: p,
                            isActive: enableExitNodeLB
                                ? p.isEnabledForLB
                                : activeExitNodeProfileID == p.id
                                    || (activeExitNodeProfileID == nil && profiles.first?.id == p.id),
                            isLB: enableExitNodeLB,
                            onSelect: {
                                if enableExitNodeLB {
                                    if let idx = profiles.firstIndex(where: { $0.id == p.id }) {
                                        profiles[idx].isEnabledForLB.toggle()
                                    }
                                } else {
                                    activeExitNodeProfileID = p.id
                                }
                                if !enableExitNodeLB { dismiss() }
                            },
                            onEdit: {
                                editTarget = p
                            },
                            onDelete: {
                                profiles.removeAll { $0.id == p.id }
                                if activeExitNodeProfileID == p.id {
                                    activeExitNodeProfileID = profiles.first?.id
                                }
                            }
                        )
                    }
                }
                .padding(16)
            }

            Divider().opacity(0.3)

            Button {
                showAddSheet = true
            } label: {
                Label("Add tunnel", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.mint)
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .frame(width: 340, height: 400)
        .sheet(item: $editTarget) { profile in
            ExitNodeEditSheet(
                profile: profile,
                profiles: $profiles,
                activeExitNodeProfileID: $activeExitNodeProfileID
            )
        }
        .sheet(isPresented: $showAddSheet) {
            ExitNodeEditSheet(
                profile: nil,
                profiles: $profiles,
                activeExitNodeProfileID: $activeExitNodeProfileID
            )
        }
    }
}

private struct ExitNodeRow: View {
    let profile: ExitNodeProfile
    let isActive: Bool
    var isLB: Bool = false
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var accent: Color { .mint }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: isLB
                          ? (isActive ? "checkmark.square.fill" : "square")
                          : (isActive ? "checkmark.circle.fill" : "circle"))
                        .foregroundStyle(isActive ? accent : .secondary)
                        .font(.system(size: 17))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(profile.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            ValBadge()
                        }
                        let u = profile.relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(u.isEmpty ? "No URL" : (u.count > 28 ? String(u.prefix(28)) + "…" : u))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? accent.opacity(0.15) : .white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? accent.opacity(0.3) : .white.opacity(0.06),
                                lineWidth: 1)
                )
        )
    }
}

// MARK: - Edit sheet

struct ExitNodeEditSheet: View {
    @Environment(\.dismiss) var dismiss

    let profile: ExitNodeProfile?
    @Binding var profiles: [ExitNodeProfile]
    @Binding var activeExitNodeProfileID: UUID?

    @State private var name: String = ""
    @State private var relayURL: String = ""
    @State private var psk: String = ""
    @State private var includeInLB: Bool = true
    @State private var isPSKVisible: Bool = false

    private var isNew: Bool { profile == nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isNew ? "New exit relay" : "Edit exit relay")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSave ? .mint : .secondary)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider().opacity(0.3)

            ScrollView {
                VStack(spacing: 18) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 14))
                            .foregroundStyle(.mint)
                            .frame(width: 18, alignment: .center)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Compatible HTTP exit relay")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Use the relay’s public URL and the same PSK configured on that relay.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.mint.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(.mint.opacity(0.22), lineWidth: 1)
                            )
                    )

                    EditField(label: "TUNNEL NAME", hint: "e.g. exit primary") {
                        TextField("Exit relay", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .editFieldStyle()
                    }

                    EditField(label: "RELAY URL", hint: "https://relay.example.com") {
                        TextField("https://", text: $relayURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .editFieldStyle()
                    }

                    EditField(label: "EXIT PSK", hint: "Same as PSK in your relay config (≥ 8 characters)") {
                        HStack(spacing: 0) {
                            if isPSKVisible {
                                TextField("", text: $psk)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            } else {
                                SecureField("", text: $psk)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            Button {
                                isPSKVisible.toggle()
                            } label: {
                                Image(systemName: isPSKVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .editFieldStyle()
                    }

                    if profiles.count >= 2 || !isNew {
                        HStack {
                            Text("Include in load-balance pool")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Toggle("", isOn: $includeInLB)
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .labelsHidden()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.04))
                        )
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 380, height: 460)
        .onAppear {
            if let p = profile {
                name = p.name
                relayURL = p.relayURL
                psk = p.psk
                includeInLB = p.isEnabledForLB
            }
        }
    }

    private var canSave: Bool {
        let u = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = u.lowercased()
        return (low.hasPrefix("https://") || low.hasPrefix("http://")) && psk.count >= 8
    }

    private func save() {
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Exit \(profiles.count + 1)"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = profile,
           let idx = profiles.firstIndex(where: { $0.id == existing.id }) {
            profiles[idx].name = resolvedName
            profiles[idx].relayURL = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
            profiles[idx].psk = psk
            profiles[idx].isEnabledForLB = includeInLB
        } else {
            let p = ExitNodeProfile(
                name: resolvedName,
                relayURL: relayURL.trimmingCharacters(in: .whitespacesAndNewlines),
                psk: psk,
                isEnabledForLB: includeInLB
            )
            profiles.append(p)
            if activeExitNodeProfileID == nil {
                activeExitNodeProfileID = p.id
            }
        }
        dismiss()
    }
}

// MARK: - Settings-style field helpers (same as SettingsView)

private struct SField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            if let hint {
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func monoField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}
