import SwiftUI
import ServiceManagement

/// A single account row with remove button
struct AccountRowView: View {
    let account: AuthAccount
    let removeColor: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(account.isExpired ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(account.displayName)
                .font(.caption)
                .foregroundColor(account.isExpired ? .orange : .secondary)
            if account.isExpired {
                Text("(expired)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Button(action: onRemove) {
                HStack(spacing: 2) {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption)
                    Text("Remove")
                        .font(.caption)
                }
                .foregroundColor(removeColor)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.leading, 28)
    }
}

/// Vercel AI Gateway controls shown in Claude expanded section
struct VercelGatewayControls: View {
    @ObservedObject var serverManager: ServerManager
    @State private var showingSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $serverManager.vercelGatewayEnabled) {
                Text("Use Vercel AI Gateway")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .help("Route Claude requests through Vercel AI Gateway for safer access to your Claude Max subscription")

            if serverManager.vercelGatewayEnabled {
                HStack(spacing: 8) {
                    Text("Vercel API key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("", text: $serverManager.vercelApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .font(.caption)

                    if showingSaved {
                        Text("Saved")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Button("Save") {
                            showingSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showingSaved = false
                            }
                        }
                        .controlSize(.small)
                        .disabled(serverManager.vercelApiKey.isEmpty)
                    }
                }
            }
        }
        .padding(.leading, 28)
        .padding(.top, 4)
    }
}

/// A row displaying a service with its connected accounts and add button
struct ServiceRow<ExtraContent: View>: View {
    let serviceType: ServiceType
    let iconName: String
    let accounts: [AuthAccount]
    let isAuthenticating: Bool
    let helpText: String?
    let isEnabled: Bool
    let customTitle: String?
    let onConnect: () -> Void
    let onDisconnect: (AuthAccount) -> Void
    let onToggleEnabled: (Bool) -> Void
    @ViewBuilder var extraContent: () -> ExtraContent

    @State private var isExpanded = false
    @State private var accountToRemove: AuthAccount?
    @State private var showingRemoveConfirmation = false

    private var activeCount: Int { accounts.filter { !$0.isExpired }.count }
    private var expiredCount: Int { accounts.filter { $0.isExpired }.count }
    private let removeColor = Color(red: 0xeb/255, green: 0x0f/255, blue: 0x0f/255)

    private var displayTitle: String {
        customTitle ?? serviceType.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            HStack {
                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { onToggleEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(isEnabled ? "Disable this provider" : "Enable this provider")

                if let nsImage = IconCatalog.shared.image(named: iconName, resizedTo: NSSize(width: 20, height: 20), template: true) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 20, height: 20)
                        .opacity(isEnabled ? 1.0 : 0.4)
                }
                Text(displayTitle)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                Spacer()
                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                } else if isEnabled {
                    Button("Add Account") {
                        onConnect()
                    }
                    .controlSize(.small)
                }
            }

            // Account display (only shown when enabled)
            if isEnabled {
                if !accounts.isEmpty {
                    // Collapsible summary
                    HStack(spacing: 4) {
                        Text("\(accounts.count) connected account\(accounts.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.green)

                        if accounts.count > 1 {
                            Text("• Round-robin w/ auto-failover")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(SettingsAnimations.rowExpand) {
                            isExpanded.toggle()
                        }
                    }

                    // Expanded accounts list
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(accounts) { account in
                                AccountRowView(account: account, removeColor: removeColor) {
                                    accountToRemove = account
                                    showingRemoveConfirmation = true
                                }
                            }
                            extraContent()
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else {
                    Text("No connected accounts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
                }
            }
        }
        .padding(.vertical, 4)
        .help(helpText ?? "")
        .onAppear {
            if accounts.contains(where: { $0.isExpired }) {
                isExpanded = true
            }
        }
        .onChange(of: accounts) { _, newAccounts in
            if newAccounts.contains(where: { $0.isExpired }) {
                isExpanded = true
            }
        }
        .alert("Remove Account", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                accountToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let account = accountToRemove {
                    onDisconnect(account)
                }
                accountToRemove = nil
            }
        } message: {
            if let account = accountToRemove {
                Text("Are you sure you want to remove \(account.displayName) from \(serviceType.displayName)?")
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var serverManager: ServerManager
    let actions: SettingsActions
    @StateObject private var authManager = AuthManager()
    @State private var launchAtLogin = false
    @State private var authenticatingService: ServiceType? = nil
    @State private var fileMonitor: DispatchSourceFileSystemObject?
    @State private var qwenEmail = ""
    @State private var zaiApiKey = ""
    @State private var pendingRefresh: DispatchWorkItem?
    @State private var expandedSections: Set<SettingsSectionID> = [.system, .services, .actions]
    @State private var activeInlinePrompt: InlinePrompt? = nil
    @State private var authToast: AuthToast? = nil

    private enum Timing {
        static let serverRestartDelay: TimeInterval = 0.3
        static let refreshDebounce: TimeInterval = 0.5
    }

    private enum InlinePrompt: Identifiable {
        case qwen
        case zai

        var id: String {
            switch self {
            case .qwen: return "qwen"
            case .zai: return "zai"
            }
        }
    }

    private struct AuthToast: Identifiable {
        let id = UUID()
        let message: String
        let success: Bool
    }

    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "v\(version)"
        }
        return ""
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    if let toast = authToast {
                        AuthToastView(message: toast.message, success: toast.success)
                            .animation(SettingsAnimations.toast, value: authToast?.id)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Server")
                                    .font(.headline)
                                Spacer()
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(serverManager.isRunning ? Color.green : Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(serverManager.isRunning ? "Running" : "Stopped")
                                        .font(.subheadline)
                                }
                            }

                            HStack(spacing: 10) {
                                Button(serverManager.isRunning ? "Stop Server" : "Start Server") {
                                    actions.onToggleServer()
                                }
                                .buttonStyle(.glassProminent)

                                Button("Copy URL") {
                                    actions.onCopyURL()
                                }
                                .buttonStyle(.glass)
                                .disabled(!serverManager.isRunning)
                            }
                        }
                        .padding(14)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))

                        SettingsSection(title: "System", isExpanded: sectionBinding(.system)) {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Launch at login", isOn: $launchAtLogin)
                                    .onChange(of: launchAtLogin) { _, newValue in
                                        toggleLaunchAtLogin(newValue)
                                    }

                                Toggle("Ollama-compatible server (port 11434)", isOn: $serverManager.ollamaProxyEnabled)
                                    .help("Expose an Ollama-compatible API on port 11434 for tools that expect Ollama")

                                HStack {
                                    Text("Auth files")
                                    Spacer()
                                    Button("Open Folder") {
                                        openAuthFolder()
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }

                        SettingsSection(title: "Actions", isExpanded: sectionBinding(.actions)) {
                            VStack(alignment: .leading, spacing: 10) {
                                Button("Check for Updates") {
                                    actions.onCheckForUpdates()
                                }
                                .buttonStyle(.glass)

                                Button("Quit VibeProxy") {
                                    actions.onQuit()
                                }
                                .buttonStyle(.glass)
                            }
                        }

                        SettingsSection(title: "About", isExpanded: sectionBinding(.about)) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Text("VibeProxy \(appVersion) was made possible thanks to")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Link("CLIProxyAPIPlus", destination: URL(string: "https://github.com/router-for-me/CLIProxyAPIPlus")!)
                                        .font(.caption)
                                        .underline()
                                        .foregroundColor(.secondary)
                                        .onHover { inside in
                                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                        }
                                    Text("|")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("License: MIT")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                HStack(spacing: 4) {
                                    Text("© 2026")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Link("Automaze, Ltd.", destination: URL(string: "https://automaze.io")!)
                                        .font(.caption)
                                        .underline()
                                        .foregroundColor(.secondary)
                                        .onHover { inside in
                                            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                        }
                                    Text("All rights reserved.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Link("Report an issue", destination: URL(string: "https://github.com/automazeio/vibeproxy/issues")!)
                                    .font(.caption)
                                    .padding(.top, 6)
                                    .onHover { inside in
                                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: 300, alignment: .leading)

                        SettingsSection(title: "Services", isExpanded: sectionBinding(.services)) {
                            VStack(alignment: .leading, spacing: 10) {
                            ServiceRow(
                                serviceType: .antigravity,
                                iconName: "icon-antigravity.png",
                                accounts: authManager.accounts(for: .antigravity),
                                isAuthenticating: authenticatingService == .antigravity,
                                helpText: "Antigravity provides OAuth-based access to various AI models including Gemini and Claude. One login gives you access to multiple AI services.",
                                isEnabled: serverManager.isProviderEnabled("antigravity"),
                                customTitle: nil,
                                onConnect: { connectService(.antigravity) },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("antigravity", enabled: enabled) }
                            ) { EmptyView() }

                            ServiceRow(
                                serviceType: .claude,
                                iconName: "icon-claude.png",
                                accounts: authManager.accounts(for: .claude),
                                isAuthenticating: authenticatingService == .claude,
                                helpText: nil,
                                isEnabled: serverManager.isProviderEnabled("claude"),
                                customTitle: serverManager.vercelGatewayEnabled && !serverManager.vercelApiKey.isEmpty ? "Claude Code (via Vercel)" : nil,
                                onConnect: { connectService(.claude) },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("claude", enabled: enabled) }
                            ) {
                                VercelGatewayControls(serverManager: serverManager)
                            }

                            ServiceRow(
                                serviceType: .codex,
                                iconName: "icon-codex.png",
                                accounts: authManager.accounts(for: .codex),
                                isAuthenticating: authenticatingService == .codex,
                                helpText: nil,
                                isEnabled: serverManager.isProviderEnabled("codex"),
                                customTitle: nil,
                                onConnect: { connectService(.codex) },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("codex", enabled: enabled) }
                            ) { EmptyView() }

                            ServiceRow(
                                serviceType: .gemini,
                                iconName: "icon-gemini.png",
                                accounts: authManager.accounts(for: .gemini),
                                isAuthenticating: authenticatingService == .gemini,
                                helpText: "⚠️ Note: If you're an existing Gemini user with multiple projects, authentication will use your default project. Set your desired project as default in Google AI Studio before connecting.",
                                isEnabled: serverManager.isProviderEnabled("gemini"),
                                customTitle: nil,
                                onConnect: { connectService(.gemini) },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("gemini", enabled: enabled) }
                            ) { EmptyView() }

                            ServiceRow(
                                serviceType: .copilot,
                                iconName: "icon-copilot.png",
                                accounts: authManager.accounts(for: .copilot),
                                isAuthenticating: authenticatingService == .copilot,
                                helpText: "GitHub Copilot provides access to Claude, GPT, Gemini and other models via your Copilot subscription.",
                                isEnabled: serverManager.isProviderEnabled("github-copilot"),
                                customTitle: nil,
                                onConnect: { connectService(.copilot) },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("github-copilot", enabled: enabled) }
                            ) { EmptyView() }

                            ServiceRow(
                                serviceType: .qwen,
                                iconName: "icon-qwen.png",
                                accounts: authManager.accounts(for: .qwen),
                                isAuthenticating: authenticatingService == .qwen,
                                helpText: nil,
                                isEnabled: serverManager.isProviderEnabled("qwen"),
                                customTitle: nil,
                                onConnect: {
                                    withAnimation(SettingsAnimations.prompt) {
                                        activeInlinePrompt = .qwen
                                    }
                                },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("qwen", enabled: enabled) }
                            ) { EmptyView() }

                            if activeInlinePrompt == .qwen {
                                InlinePromptCard(
                                    title: "Qwen Account Email",
                                    subtitle: "Enter your Qwen account email address"
                                ) {
                                    TextField("your.email@example.com", text: $qwenEmail)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 240)
                                    HStack(spacing: 10) {
                                        Button("Cancel") {
                                            withAnimation(SettingsAnimations.prompt) {
                                                activeInlinePrompt = nil
                                            }
                                            qwenEmail = ""
                                        }
                                        .buttonStyle(.glass)
                                        Button("Continue") {
                                            withAnimation(SettingsAnimations.prompt) {
                                                activeInlinePrompt = nil
                                            }
                                            startQwenAuth(email: qwenEmail)
                                        }
                                        .disabled(qwenEmail.isEmpty)
                                        .buttonStyle(.glassProminent)
                                    }
                                }
                            }

                            ServiceRow(
                                serviceType: .zai,
                                iconName: "icon-zai.png",
                                accounts: authManager.accounts(for: .zai),
                                isAuthenticating: authenticatingService == .zai,
                                helpText: "Z.AI GLM provides access to GLM-4.7 and other models via API key. Get your key at https://z.ai/manage-apikey/apikey-list",
                                isEnabled: serverManager.isProviderEnabled("zai"),
                                customTitle: nil,
                                onConnect: {
                                    withAnimation(SettingsAnimations.prompt) {
                                        activeInlinePrompt = .zai
                                    }
                                },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("zai", enabled: enabled) }
                            ) { EmptyView() }

                            if activeInlinePrompt == .zai {
                                InlinePromptCard(
                                    title: "Z.AI API Key",
                                    subtitle: "Enter your Z.AI API key"
                                ) {
                                    TextField("", text: $zaiApiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 260)
                                    HStack(spacing: 10) {
                                        Button("Cancel") {
                                            withAnimation(SettingsAnimations.prompt) {
                                                activeInlinePrompt = nil
                                            }
                                            zaiApiKey = ""
                                        }
                                        .buttonStyle(.glass)
                                        Button("Add Key") {
                                            withAnimation(SettingsAnimations.prompt) {
                                                activeInlinePrompt = nil
                                            }
                                            startZaiAuth(apiKey: zaiApiKey)
                                        }
                                        .disabled(zaiApiKey.isEmpty)
                                        .buttonStyle(.glassProminent)
                                    }
                                }
                            }

                            ServiceRow(
                                serviceType: .kimi,
                                iconName: "icon-kimi.png",
                                accounts: authManager.accounts(for: .kimi),
                                isAuthenticating: authenticatingService == .kimi,
                                helpText: "Kimi (Moonshot AI) provides access to K2 and other models via OAuth device flow.",
                                isEnabled: serverManager.isProviderEnabled("kimi"),
                                customTitle: nil,
                                onConnect: { connectService(.kimi) },
                                onDisconnect: { account in disconnectAccount(account) },
                                onToggleEnabled: { enabled in serverManager.setProviderEnabled("kimi", enabled: enabled) }
                            ) { EmptyView() }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 640, height: 520)
        .onAppear {
            authManager.checkAuthStatus()
            checkLaunchAtLogin()
            startMonitoringAuthDirectory()
        }
        .onDisappear {
            stopMonitoringAuthDirectory()
        }
    }

    // MARK: - Actions

    private func sectionBinding(_ id: SettingsSectionID) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(id)
                } else {
                    expandedSections.remove(id)
                }
            }
        )
    }

    private func showAuthToast(message: String, success: Bool) {
        let toast = AuthToast(message: message, success: success)
        withAnimation(SettingsAnimations.toast) {
            authToast = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if authToast?.id == toast.id {
                withAnimation(SettingsAnimations.toast) {
                    authToast = nil
                }
            }
        }
    }

    private func openAuthFolder() {
        let authDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cli-proxy-api")
        NSWorkspace.shared.open(authDir)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[SettingsView] Failed to toggle launch at login: %@", error.localizedDescription)
            }
        }
    }

    private func checkLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func connectService(_ serviceType: ServiceType) {
        authenticatingService = serviceType
        NSLog("[SettingsView] Starting %@ authentication", serviceType.displayName)

        let command: AuthCommand
        switch serviceType {
        case .claude: command = .claudeLogin
        case .codex: command = .codexLogin
        case .copilot: command = .copilotLogin
        case .gemini: command = .geminiLogin
        case .qwen:
            authenticatingService = nil
            return // handled separately with email prompt
        case .antigravity: command = .antigravityLogin
        case .zai:
            authenticatingService = nil
            return // handled separately with API key prompt
        case .kimi: command = .kimiLogin
        }

        serverManager.runAuthCommand(command) { success, output in
            NSLog("[SettingsView] Auth completed - success: %d, output: %@", success, output)
            DispatchQueue.main.async {
                self.authenticatingService = nil

                if success {
                    // For Copilot, use the output which contains the device code
                    if serviceType == .copilot && (output.contains("Code copied") || output.contains("code:")) {
                        self.showAuthToast(message: output, success: true)
                    } else {
                        self.showAuthToast(message: self.successMessage(for: serviceType), success: true)
                    }
                } else {
                    self.showAuthToast(message: "Authentication failed. \(output.isEmpty ? "No output from authentication process." : output)", success: false)
                }
            }
        }
    }

    private func successMessage(for serviceType: ServiceType) -> String {
        switch serviceType {
        case .claude:
            return "🌐 Browser opened for Claude Code authentication.\n\nPlease complete the login in your browser.\n\nThe app will automatically detect your credentials."
        case .codex:
            return "🌐 Browser opened for Codex authentication.\n\nPlease complete the login in your browser.\n\nThe app will automatically detect your credentials."
        case .copilot:
            return "🌐 GitHub Copilot authentication started!\n\nPlease visit github.com/login/device and enter the code shown.\n\nThe app will automatically detect your credentials."
        case .gemini:
            return "🌐 Browser opened for Gemini authentication.\n\nPlease complete the login in your browser.\n\n⚠️ Note: If you have multiple projects, the default project will be used."
        case .qwen:
            return "🌐 Browser opened for Qwen authentication.\n\nPlease complete the login in your browser."
        case .antigravity:
            return "🌐 Browser opened for Antigravity authentication.\n\nPlease complete the login in your browser."
        case .zai:
            return "✓ Z.AI API key added successfully.\n\nYou can now use GLM models through the proxy."
        case .kimi:
            return "🌐 Browser opened for Kimi authentication.\n\nPlease complete the login in your browser.\n\nThe app will automatically detect your credentials."
        }
    }


    private func startQwenAuth(email: String) {
        authenticatingService = .qwen
        NSLog("[SettingsView] Starting Qwen authentication")

        serverManager.runAuthCommand(.qwenLogin(email: email)) { success, output in
            NSLog("[SettingsView] Auth completed - success: %d, output: %@", success, output)
            DispatchQueue.main.async {
                self.authenticatingService = nil
                self.qwenEmail = ""

                if success {
                    self.showAuthToast(message: self.successMessage(for: .qwen), success: true)
                } else {
                    self.showAuthToast(message: "Authentication failed. \(output.isEmpty ? "No output." : output)", success: false)
                }
            }
        }
    }

    private func startZaiAuth(apiKey: String) {
        authenticatingService = .zai
        NSLog("[SettingsView] Adding Z.AI API key")

        serverManager.saveZaiApiKey(apiKey) { success, output in
            NSLog("[SettingsView] Z.AI key save completed - success: %d, output: %@", success, output)
            DispatchQueue.main.async {
                self.authenticatingService = nil
                self.zaiApiKey = ""

                if success {
                    self.showAuthToast(message: self.successMessage(for: .zai), success: true)
                    self.authManager.checkAuthStatus()
                } else {
                    self.showAuthToast(message: "Failed to save API key. \(output.isEmpty ? "Unknown error." : output)", success: false)
                }
            }
        }
    }

    private func disconnectAccount(_ account: AuthAccount) {
        let wasRunning = serverManager.isRunning

        // Stop server, delete file, restart
        let cleanup = {
            if self.authManager.deleteAccount(account) {
                self.showAuthToast(message: "Removed \(account.displayName) from \(account.type.displayName)", success: true)
            } else {
                self.showAuthToast(message: "Failed to remove account", success: false)
            }

            if wasRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + Timing.serverRestartDelay) {
                    self.serverManager.start { _ in }
                }
            }
        }

        if wasRunning {
            serverManager.stop { cleanup() }
        } else {
            cleanup()
        }
    }

    // MARK: - File Monitoring

    private func startMonitoringAuthDirectory() {
        let authDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cli-proxy-api")
        try? FileManager.default.createDirectory(at: authDir, withIntermediateDirectories: true)

        let fileDescriptor = open(authDir.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [self] in
            // Debounce rapid file changes to prevent UI flashing
            pendingRefresh?.cancel()
            let workItem = DispatchWorkItem {
                NSLog("[FileMonitor] Auth directory changed - refreshing status")
                authManager.checkAuthStatus()
            }
            pendingRefresh = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.refreshDebounce, execute: workItem)
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()
        fileMonitor = source
    }

    private func stopMonitoringAuthDirectory() {
        pendingRefresh?.cancel()
        fileMonitor?.cancel()
        fileMonitor = nil
    }
}
