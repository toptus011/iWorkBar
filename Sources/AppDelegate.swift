// AppDelegate.swift – ikona na pasku menu, obserwacja aktywnego programu, ustawienia

import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let controller = TouchBarController()
    private var configError: String?
    private var permissionTimer: Timer?
    private var hadPermission = false
    private var lastPermissionAlert = Date.distantPast

    private var hasPermission: Bool { Actions.canPostEvents }

    // MARK: - Start

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        controller.onStateChange = { [weak self] in self?.updateStatusIcon() }
        controller.onPermissionMissing = { [weak self] in self?.permissionMissing() }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        Log.write("Start iWorkBar \(version) z \(Bundle.main.bundlePath); "
                  + "Dostępność(AX)=\(Actions.isAXTrusted), wysyłanie klawiszy=\(Actions.canPostEvents), "
                  + "funkcje Touch Bara=\(PrivateTouchBar.isAvailable)")

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if !PrivateTouchBar.isAvailable {
            showAlert("Ta wersja macOS nie udostępnia funkcji Touch Bara potrzebnych do działania iWorkBar.",
                      info: "Program pozostanie na pasku menu, ale nie będzie mógł wyświetlać przycisków.")
        }

        hadPermission = hasPermission
        if !hadPermission {
            askForAccessibility()
        }
        startPermissionWatch()

        reloadConfig(showErrors: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    // MARK: - Uprawnienia

    /// Co 2 s sprawdza uprawnienie. Gdy zostanie właśnie nadane, program uruchamia się
    /// ponownie – macOS nie zawsze stosuje świeże uprawnienie do działającego procesu.
    private func startPermissionWatch() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = self.hasPermission
            if now && !self.hadPermission {
                Log.write("Uprawnienie Dostępności zostało nadane – ponowne uruchomienie programu")
                self.relaunch()
            }
            if now != self.hadPermission { self.updateStatusIcon() }
            self.hadPermission = now
        }
    }

    private func permissionMissing() {
        // Nie częściej niż raz na 15 s, żeby nie przeszkadzać przy kolejnych dotknięciach
        guard Date().timeIntervalSince(lastPermissionAlert) > 15 else { return }
        lastPermissionAlert = Date()
        askForAccessibility()
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func appActivated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        controller.handleActivation(of: app)
    }

    // MARK: - Konfiguracja

    private func reloadConfig(showErrors: Bool) {
        switch ConfigStore.load() {
        case .success(let config):
            configError = nil
            controller.apply(config: config)
        case .failure(let error):
            let message = error.message
            configError = message
            controller.hide()
            if showErrors {
                showAlert("Nie udało się wczytać konfiguracji przycisków.", info: message)
            }
        }
        updateStatusIcon()
    }

    // MARK: - Pasek menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        if !hasPermission {
            symbol = "exclamationmark.triangle"
        } else {
            symbol = controller.activeAppName != nil ? "rectangle.inset.filled" : "rectangle"
        }
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "iWorkBar") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.title = "iW"
        }
        button.toolTip = controller.activeAppName.map { "iWorkBar – aktywny w: \($0)" } ?? "iWorkBar"
    }

    /// Menu budowane od nowa przy każdym otwarciu, żeby pokazywało aktualny stan.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let state: String
        if let error = configError {
            state = "⚠️ Błąd konfiguracji: \(error)"
        } else if let name = controller.activeAppName {
            state = "Aktywny: \(name)"
        } else {
            state = "Czeka na Pages, Keynote lub Numbers"
        }
        let stateItem = NSMenuItem(title: state, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let permLine = NSMenuItem(title: hasPermission
                                  ? "✅ Uprawnienie Dostępności: nadane"
                                  : "❌ Uprawnienie Dostępności: BRAK – przyciski nie działają",
                                  action: nil, keyEquivalent: "")
        permLine.isEnabled = false
        menu.addItem(permLine)
        if !hasPermission {
            menu.addItem(item("Nadaj uprawnienie Dostępności…", #selector(openAccessibilitySettings)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Edytuj przyciski…", #selector(editConfig), key: "e"))
        menu.addItem(item("Wczytaj przyciski ponownie", #selector(reloadFromMenu), key: "r"))
        menu.addItem(item("Pokaż folder konfiguracji", #selector(revealConfig)))
        menu.addItem(item("Przywróć przyciski domyślne…", #selector(resetConfig)))

        menu.addItem(.separator())
        let login = item("Uruchamiaj przy logowaniu", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Napraw Touch Bar (restart procesów)…", #selector(restartTouchBar)))
        menu.addItem(item("Sprawdź, co widzi iWorkBar (za 3 s)", #selector(runDiagnostics)))
        menu.addItem(item("Pokaż dziennik zdarzeń", #selector(showLog)))

        menu.addItem(.separator())
        menu.addItem(item("O programie iWorkBar", #selector(about)))
        menu.addItem(item("Zakończ", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: - Akcje menu

    @objc private func editConfig() {
        ConfigStore.ensureExists()
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([ConfigStore.fileURL], withApplicationAt: textEdit,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func reloadFromMenu() {
        reloadConfig(showErrors: true)
    }

    @objc private func revealConfig() {
        ConfigStore.ensureExists()
        NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
    }

    @objc private func resetConfig() {
        let alert = NSAlert()
        alert.messageText = "Przywrócić przyciski domyślne?"
        alert.informativeText = "Obecny plik zostanie zapisany jako config.backup.json."
        alert.addButton(withTitle: "Przywróć")
        alert.addButton(withTitle: "Anuluj")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let fm = FileManager.default
        let backup = ConfigStore.folderURL.appendingPathComponent("config.backup.json")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: ConfigStore.fileURL, to: backup)
        reloadConfig(showErrors: true)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Nie udało się zmienić ustawienia logowania.", info: error.localizedDescription)
        }
    }

    @objc private func restartTouchBar() {
        if Actions.restartTouchBar() {
            // Procesy wstają po chwili – wtedy pokazujemy nasz pasek ponownie
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.controller.refreshForFrontmostApp(force: true)
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        Actions.checkAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Po 3 sekundach (czas na kliknięcie w tekst w Pages/Keynote) zapisuje do dziennika,
    /// jakie informacje o tekście udostępnia program, i otwiera dziennik.
    @objc private func runDiagnostics() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            Log.write(self.controller.diagnose())
            self.showLog()
        }
    }

    @objc private func showLog() {
        if !FileManager.default.fileExists(atPath: Log.fileURL.path) {
            Log.write("Dziennik utworzony")
        }
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([Log.fileURL], withApplicationAt: textEdit,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "iWorkBar",
            .credits: NSAttributedString(string: "Własny Touch Bar dla Pages, Keynote i Numbers.\nOpracował ks. Piotr Bułka"),
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Okna dialogowe

    private func askForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "iWorkBar potrzebuje uprawnienia Dostępności"
        alert.informativeText = """
        Bez niego przyciski na Touch Barze są widoczne, ale nie działają.

        1. W oknie „Dostępność”, które się otworzy, zaznacz każdą starą pozycję „iWorkBar” i usuń ją przyciskiem „–”.
        2. Dodaj iWorkBar ponownie przyciskiem „+” (folder Aplikacje) i włącz przełącznik.

        Gdy uprawnienie zostanie nadane, iWorkBar sam uruchomi się ponownie.
        """
        alert.addButton(withTitle: "Otwórz Ustawienia")
        alert.addButton(withTitle: "Później")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func showAlert(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
