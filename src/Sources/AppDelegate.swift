import Cocoa
import SwiftUI
import WebKit
import UserNotifications
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    private var settingsPopover: NSPopover?
    var serverManager: ServerManager!
    var thinkingProxy: ThinkingProxy!
    var ollamaProxy: OllamaProxy!
    private let notificationCenter = UNUserNotificationCenter.current()
    private var notificationPermissionGranted = false
    private let updaterController: SPUStandardUpdaterController

    override init() {
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup standard Edit menu for keyboard shortcuts (Cmd+C/V/X/A)
        setupMainMenu()

        // Initialize managers
        serverManager = ServerManager()
        thinkingProxy = ThinkingProxy()
        ollamaProxy = OllamaProxy()

        // Setup menu bar + settings popover
        setupMenuBar()
        configurePopover()

        // Sync Vercel AI Gateway config from ServerManager to ThinkingProxy
        syncVercelConfig()
        serverManager.onVercelConfigChanged = { [weak self] in
            self?.syncVercelConfig()
        }

        // Sync Ollama proxy enabled state
        serverManager.onOllamaProxyConfigChanged = { [weak self] in
            self?.syncOllamaProxy()
        }

        // Warm commonly used icons to avoid first-use disk hits
        preloadIcons()

        configureNotifications()

        // Start server automatically
        startServer()

        // Register for notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuBarStatus),
            name: .serverStatusChanged,
            object: nil
        )
    }

    private func preloadIcons() {
        let statusIconSize = NSSize(width: 18, height: 18)
        let serviceIconSize = NSSize(width: 20, height: 20)

        let iconsToPreload = [
            ("icon-active.png", statusIconSize),
            ("icon-inactive.png", statusIconSize),
            ("icon-codex.png", serviceIconSize),
            ("icon-claude.png", serviceIconSize),
            ("icon-gemini.png", serviceIconSize)
        ]

        for (name, size) in iconsToPreload {
            if IconCatalog.shared.image(named: name, resizedTo: size, template: true) == nil {
                NSLog("[IconPreload] Warning: Failed to preload icon '%@'", name)
            }
        }
    }

    private func configureNotifications() {
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error = error {
                NSLog("[Notifications] Authorization failed: %@", error.localizedDescription)
            }
            DispatchQueue.main.async {
                self?.notificationPermissionGranted = granted
                if !granted {
                    NSLog("[Notifications] Authorization not granted; notifications will be suppressed")
                }
            }
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About VibeProxy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit VibeProxy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (for Cmd+C/V/X/A to work)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let icon = IconCatalog.shared.image(named: "icon-inactive.png", resizedTo: NSSize(width: 18, height: 18), template: true) {
                button.image = icon
            } else {
                let fallback = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "VibeProxy")
                fallback?.isTemplate = true
                button.image = fallback
                NSLog("[MenuBar] Failed to load inactive icon from bundle; using fallback system icon")
            }
            button.target = self
            button.action = #selector(togglePopover)
        }
    }

    private func configurePopover() {
        let actions = SettingsActions(
            onToggleServer: { [weak self] in self?.toggleServer() },
            onCopyURL: { [weak self] in self?.copyServerURL() },
            onCheckForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) },
            onQuit: { [weak self] in self?.quit() }
        )

        let contentView = SettingsView(serverManager: serverManager, actions: actions)
        let hostingController = NSHostingController(rootView: contentView)

        let popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 640, height: 520)
        settingsPopover = popover
    }

    @objc func togglePopover() {
        guard let button = statusItem.button, let popover = settingsPopover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            DispatchQueue.main.async { [weak popover] in
                popover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc func toggleServer() {
        if serverManager.isRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    func startServer() {
        // Start the thinking proxy first (port 8317)
        thinkingProxy.start()

        // Poll for thinking proxy readiness with timeout
        pollForProxyReadiness(attempts: 0, maxAttempts: 60, intervalMs: 50)
    }

    private func pollForProxyReadiness(attempts: Int, maxAttempts: Int, intervalMs: Int) {
        // Check if proxy is running
        if thinkingProxy.isRunning {
            // Success - proceed to start backend
            serverManager.start { [weak self] success in
                DispatchQueue.main.async {
                    if success {
                        self?.updateMenuBarStatus()
                        // User always connects to 8317 (thinking proxy)
                        self?.showNotification(title: "Server Started", body: "VibeProxy is now running")
                        // Start Ollama proxy if enabled
                        if self?.serverManager.ollamaProxyEnabled == true {
                            self?.ollamaProxy.start()
                        }
                    } else {
                        // Backend failed - stop the proxy to keep state consistent
                        self?.thinkingProxy.stop()
                        self?.showNotification(title: "Server Failed", body: "Could not start backend server on port 8318")
                    }
                }
            }
            return
        }

        // Check if we've exceeded timeout
        if attempts >= maxAttempts {
            DispatchQueue.main.async { [weak self] in
                // Clean up partially initialized proxy
                self?.thinkingProxy.stop()
                self?.showNotification(title: "Server Failed", body: "Could not start thinking proxy on port 8317 (timeout)")
            }
            return
        }

        // Schedule next poll
        let interval = Double(intervalMs) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.pollForProxyReadiness(attempts: attempts + 1, maxAttempts: maxAttempts, intervalMs: intervalMs)
        }
    }

    func stopServer() {
        // Stop the ollama proxy
        ollamaProxy.stop()

        // Stop the thinking proxy first to stop accepting new requests
        thinkingProxy.stop()

        // Then stop CLIProxyAPI backend
        serverManager.stop()

        updateMenuBarStatus()
    }

    @objc func copyServerURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("http://localhost:\(thinkingProxy.proxyPort)", forType: .string)
        showNotification(title: "Copied", body: "Server URL copied to clipboard")
    }

    @objc func updateMenuBarStatus() {
        // Update icon based on server status
        if let button = statusItem.button {
            let iconName = serverManager.isRunning ? "icon-active.png" : "icon-inactive.png"
            let fallbackSymbol = serverManager.isRunning ? "network" : "network.slash"

            if let icon = IconCatalog.shared.image(named: iconName, resizedTo: NSSize(width: 18, height: 18), template: true) {
                button.image = icon
                NSLog("[MenuBar] Loaded %@ icon from cache", serverManager.isRunning ? "active" : "inactive")
            } else {
                let fallback = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: serverManager.isRunning ? "Running" : "Stopped")
                fallback?.isTemplate = true
                button.image = fallback
                NSLog("[MenuBar] Failed to load %@ icon; using fallback", serverManager.isRunning ? "active" : "inactive")
            }
        }
    }

    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "io.automaze.vibeproxy.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { error in
            if let error = error {
                NSLog("[Notifications] Failed to deliver notification '%@': %@", title, error.localizedDescription)
            }
        }
    }

    @objc func quit() {
        // Stop server and wait for cleanup before quitting
        if serverManager.isRunning {
            ollamaProxy.stop()
            thinkingProxy.stop()
            serverManager.stop()
        }
        // Give a moment for cleanup to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: .serverStatusChanged, object: nil)
        // Final cleanup - stop server if still running
        if serverManager.isRunning {
            ollamaProxy.stop()
            thinkingProxy.stop()
            serverManager.stop()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // If server is running, stop it first
        if serverManager.isRunning {
            ollamaProxy.stop()
            thinkingProxy.stop()
            serverManager.stop()
            // Give server time to stop (up to 3 seconds total with the improved stop method)
            return .terminateNow
        }
        return .terminateNow
    }

    // MARK: - Vercel Config Sync

    private func syncOllamaProxy() {
        if serverManager.ollamaProxyEnabled && serverManager.isRunning {
            if !ollamaProxy.isRunning {
                ollamaProxy.start()
            }
        } else {
            ollamaProxy.stop()
        }
    }

    private func syncVercelConfig() {
        thinkingProxy.vercelConfig = VercelGatewayConfig(
            enabled: serverManager.vercelGatewayEnabled,
            apiKey: serverManager.vercelApiKey
        )
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
