// TouchBarController.swift – budowanie paska i jego „życie”: pokazywanie dla Pages/Keynote/Numbers,
// natywne kontrolki (formatowanie, wyrównanie, rozmiar, kolor, slajdy) i podświetlanie stanu.

import Cocoa

final class TouchBarController: NSObject {

    private enum Mode: String { case edit = "edycja", show = "pokaz" }

    private static let trayID = NSTouchBarItem.Identifier("pl.bulka.iworkbar.tray")
    private static let escID = NSTouchBarItem.Identifier("pl.bulka.iworkbar.esc")
    private static let slideItemID = NSUserInterfaceItemIdentifier("pl.bulka.iworkbar.slide")

    // Konfiguracja i cel
    private var config: Config?
    private var appConfig: AppConfig?
    private var currentBar: NSTouchBar?
    private var currentButtons: [ButtonConfig] = []
    private var targetPID: pid_t?
    private var targetBundleID: String?
    private var mode: Mode = .edit
    private var trayItem: NSCustomTouchBarItem?

    // Kontrolki, których stan aktualizujemy
    private var formatControl: NSSegmentedControl?
    private var formatHasStrike = false
    private var formatPrevious: [Bool] = []
    private var alignControl: NSSegmentedControl?
    private var sizeControl: NSSegmentedControl?
    private var colorItem: NSColorPickerTouchBarItem?
    private var scrubber: NSScrubber?
    private var slideCount = 0

    // Odczyt stanu
    private let reader = StateReader()
    private let colorApplier = ColorApplier()
    private let keynote = KeynoteMonitor()
    private var timer: Timer?
    private var tick = 0
    private var suppressFormatUntil = Date.distantPast
    private var suppressAlignUntil = Date.distantPast
    private var suppressColorUntil = Date.distantPast
    private var loggedFormattingKnown: Bool?

    // Okno dialogowe programu (Zapisz / Nie zapisuj / Anuluj…) – wtedy pasek iWorkBar jest schowany
    private var dialogHidden = false

    /// Nazwa programu, dla którego pasek jest teraz widoczny (do menu na pasku menu).
    private(set) var activeAppName: String?
    var onStateChange: (() -> Void)?
    /// Wywoływane, gdy przycisk nie zadziałał z powodu braku uprawnienia.
    var onPermissionMissing: (() -> Void)?

    // MARK: - Konfiguracja

    func apply(config: Config) {
        self.config = config
        refreshForFrontmostApp(force: true)
    }

    // MARK: - Reakcja na zmianę aktywnego programu

    func refreshForFrontmostApp(force: Bool = false) {
        handleActivation(of: NSWorkspace.shared.frontmostApplication, force: force)
    }

    func handleActivation(of app: NSRunningApplication?, force: Bool = false) {
        // Nasza własna aplikacja nie zmienia stanu (np. gdy otwarto jej menu)
        if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        // Ten sam program znów aktywny (np. po okienku systemowym) – pasek już stoi, nie przebudowujemy go
        if !force, let app, app.processIdentifier == targetPID, currentBar != nil { return }

        guard let config, let app,
              let match = config.appConfig(name: app.localizedName, bundleID: app.bundleIdentifier),
              !match.1.przyciski.isEmpty
        else {
            hide()
            return
        }
        appConfig = match.1
        targetBundleID = app.bundleIdentifier
        reader.reset()
        show(mode: .edit, appName: match.0, pid: app.processIdentifier)
    }

    // MARK: - Pokazywanie i ukrywanie

    private func show(mode newMode: Mode, appName: String, pid: pid_t) {
        guard let config, let appConfig else { return }
        if let old = currentBar { PrivateTouchBar.dismiss(old) }
        // Nowy pasek – jeśli okno dialogowe nadal jest otwarte, pierwsze sprawdzenie od razu go schowa.
        dialogHidden = false

        mode = newMode
        let buttons = (newMode == .show ? appConfig.pokaz : nil) ?? appConfig.przyciski
        currentButtons = buttons
        targetPID = pid
        activeAppName = appName

        let bar = buildBar(buttons: buttons, showEsc: config.showEsc)
        currentBar = bar

        installTrayItemIfNeeded()
        PrivateTouchBar.hideCloseBox()
        let shown = PrivateTouchBar.present(bar, fullWidth: config.fullWidth, trayIdentifier: Self.trayID.rawValue)
        Log.write("Pasek dla \(appName) (\(newMode.rawValue)): \(buttons.count) elementów, pokazany=\(shown), "
                  + "Dostępność(AX)=\(Actions.isAXTrusted), wysyłanie klawiszy=\(Actions.canPostEvents)")
        startTimer()
        updateState(force: true)
        onStateChange?()
    }

    func hide() {
        stopTimer()
        dialogHidden = false
        if let bar = currentBar { PrivateTouchBar.dismiss(bar) }
        currentBar = nil
        targetPID = nil
        clearWidgetReferences()
        mode = .edit
        if activeAppName != nil {
            activeAppName = nil
            onStateChange?()
        }
    }

    /// Ponownie pokazuje pasek (np. po restarcie procesów Touch Bara).
    func representIfActive() {
        guard !dialogHidden, let bar = currentBar, let config else { return }
        PrivateTouchBar.hideCloseBox()
        PrivateTouchBar.present(bar, fullWidth: config.fullWidth, trayIdentifier: Self.trayID.rawValue)
    }

    func shutdown() {
        hide()
        reader.restoreEnhanced()
        if let tray = trayItem { PrivateTouchBar.removeTrayItem(tray) }
    }

    private func clearWidgetReferences() {
        formatControl = nil
        formatPrevious = []
        alignControl = nil
        sizeControl = nil
        colorItem = nil
        scrubber = nil
        slideCount = 0
        loggedFormattingKnown = nil
    }

    // MARK: - Ikona w Control Strip

    private func installTrayItemIfNeeded() {
        guard trayItem == nil else { return }
        let item = NSCustomTouchBarItem(identifier: Self.trayID)
        let button: NSButton
        if let image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: "iWorkBar") {
            button = NSButton(image: image, target: self, action: #selector(trayTapped))
        } else {
            button = NSButton(title: "iW", target: self, action: #selector(trayTapped))
        }
        item.view = button
        trayItem = item
        PrivateTouchBar.addTrayItem(item)
    }

    @objc private func trayTapped() {
        representIfActive()
    }

    // MARK: - Budowanie paska

    private func buildBar(buttons: [ButtonConfig], showEsc: Bool) -> NSTouchBar {
        clearWidgetReferences()
        let bar = NSTouchBar()
        var items: [NSTouchBarItem] = []
        var ids: [NSTouchBarItem.Identifier] = []

        if showEsc {
            let esc = NSCustomTouchBarItem(identifier: Self.escID)
            let b = NSButton(title: "esc", target: self, action: #selector(escTapped))
            b.widthAnchor.constraint(equalToConstant: 64).isActive = true
            esc.view = b
            items.append(esc)
            ids.append(Self.escID)
        }

        for (index, config) in buttons.enumerated() {
            let id = NSTouchBarItem.Identifier("pl.bulka.iworkbar.\(mode.rawValue).\(index)")
            guard let item = makeItem(config, index: index, identifier: id) else {
                Log.write("Nieznany typ elementu „\(config.kind)” – pominięto")
                continue
            }
            items.append(item)
            ids.append(id)
        }

        bar.templateItems = Set(items)
        bar.defaultItemIdentifiers = ids
        return bar
    }

    private func makeItem(_ config: ButtonConfig, index: Int, identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch config.kind {
        case "przycisk", "button":
            return wrap(makeButton(config, tag: index), identifier, label: config.label)

        case "formatowanie":
            formatHasStrike = config.przekreslenie ?? false
            var symbols = [("bold", "B"), ("italic", "I"), ("underline", "U")]
            if formatHasStrike { symbols.append(("strikethrough", "S")) }
            let control = segmented(symbols, mode: .selectAny, action: #selector(formatChanged(_:)), width: 40)
            formatControl = control
            formatPrevious = Array(repeating: false, count: symbols.count)
            return wrap(control, identifier, label: "Formatowanie")

        case "wyrownanie":
            let control = segmented([("text.alignleft", "L"), ("text.aligncenter", "C"),
                                     ("text.alignright", "R"), ("text.justify", "J")],
                                    mode: .selectOne, action: #selector(alignChanged(_:)), width: 40)
            control.selectedSegment = -1
            alignControl = control
            return wrap(control, identifier, label: "Wyrównanie")

        case "rozmiar":
            let control = segmented([("textformat.size.smaller", "A−"), ("", "–"), ("textformat.size.larger", "A+")],
                                    mode: .momentary, action: #selector(sizeTapped(_:)), width: 40)
            control.setWidth(48, forSegment: 1)
            sizeControl = control
            return wrap(control, identifier, label: "Rozmiar")

        case "kolor":
            let item = NSColorPickerTouchBarItem.textColorPicker(withIdentifier: identifier)
            item.showsAlpha = false
            item.target = self
            item.action = #selector(colorPicked(_:))
            colorItem = item
            return item

        case "cofnij":
            let control = segmented([("arrow.uturn.backward", "↶"), ("arrow.uturn.forward", "↷")],
                                    mode: .momentary, action: #selector(undoTapped(_:)), width: 40)
            return wrap(control, identifier, label: "Cofnij")

        case "slajdy":
            let s = NSScrubber()
            s.register(NSScrubberTextItemView.self, forItemIdentifier: Self.slideItemID)
            let layout = NSScrubberFlowLayout()
            layout.itemSpacing = 4
            s.scrubberLayout = layout
            s.mode = .free
            s.selectionBackgroundStyle = .roundedBackground
            s.selectionOverlayStyle = .outlineOverlay
            s.showsArrowButtons = false
            s.dataSource = self
            s.delegate = self
            s.widthAnchor.constraint(equalToConstant: 420).isActive = true
            scrubber = s
            return wrap(s, identifier, label: "Slajdy")

        default:
            return nil
        }
    }

    private func wrap(_ view: NSView, _ identifier: NSTouchBarItem.Identifier, label: String) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = view
        item.customizationLabel = label
        return item
    }

    /// Grupa połączonych przycisków w stylu Apple. Gdy symbolu brak, pokazuje tekst zastępczy.
    private func segmented(_ segments: [(String, String)], mode: NSSegmentedControl.SwitchTracking,
                           action: Selector, width: CGFloat) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: segments.map { $0.1 }, trackingMode: mode,
                                         target: self, action: action)
        for (i, segment) in segments.enumerated() {
            if !segment.0.isEmpty, let image = NSImage(systemSymbolName: segment.0, accessibilityDescription: segment.1) {
                control.setImage(image, forSegment: i)
                control.setLabel("", forSegment: i)
            }
            control.setWidth(width, forSegment: i)
        }
        control.selectedSegmentBezelColor = .controlAccentColor
        return control
    }

    private func makeButton(_ config: ButtonConfig, tag: Int) -> NSButton {
        let title = config.label
        let image = config.ikona.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: title)
        }
        let button: NSButton
        if let image {
            button = NSButton(title: title, image: image, target: self, action: #selector(buttonTapped(_:)))
            button.imagePosition = (config.zTytulem ?? false) ? .imageLeading : .imageOnly
        } else {
            button = NSButton(title: title, target: self, action: #selector(buttonTapped(_:)))
        }
        button.tag = tag
        if let hex = config.kolor, let color = NSColor(hex: hex) {
            button.bezelColor = color
        }
        if let w = config.szerokosc {
            button.widthAnchor.constraint(equalToConstant: CGFloat(w)).isActive = true
        } else if button.imagePosition == .imageOnly {
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }
        return button
    }

    // MARK: - Odczyt stanu (co 0,35 s)

    // MARK: - Okna dialogowe (Zapisz, Nie zapisuj, Anuluj, Otwórz…)

    /// true – program pokazuje okno dialogowe (Otwórz, Zapisz, „Zachować zmiany?”).
    /// Wtedy chowamy pasek iWorkBar, a macOS sam pokazuje na Touch Barze przyciski tego okna
    /// (Zapisz, Nie zapisuj, Anuluj, Otwórz…) – dokładnie tak, jak przed wyłączeniem Touch Bara w iWork.
    private func handleDialog(pid: pid_t) -> Bool {
        guard let found = DialogReader.container(pid: pid) else {
            if dialogHidden { endDialog() }
            return false
        }
        if !dialogHidden {
            dialogHidden = true
            if let bar = currentBar { PrivateTouchBar.dismiss(bar) }
            Log.write("Okno dialogowe – \(found.1): pasek iWorkBar schowany, przyciski okna pokazuje macOS")
        }
        return true
    }

    /// Okno dialogowe zamknięte – pasek narzędzi budujemy od nowa.
    private func endDialog() {
        dialogHidden = false
        Log.write("Okno dialogowe zamknięte – wraca pasek \(activeAppName ?? "")")
        if let pid = targetPID, let name = activeAppName {
            let restoreMode = mode
            DispatchQueue.main.async { [weak self] in
                guard let self, self.targetPID == pid, !self.dialogHidden else { return }
                self.show(mode: restoreMode, appName: name, pid: pid)
            }
        }
    }


    private func startTimer() {
        stopTimer()
        tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.updateState(force: false)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private var needsFormattingState: Bool {
        formatControl != nil || alignControl != nil || sizeControl != nil || colorItem != nil
    }

    private func updateState(force: Bool) {
        guard let pid = targetPID else { return }
        tick += 1

        // Otwarte okno dialogowe → pasek iWorkBar schowany, przyciski okna pokazuje macOS
        if Actions.isAXTrusted, handleDialog(pid: pid) { return }

        // Keynote: przełączanie między paskiem edycji a paskiem pokazu (co ok. 1 s)
        if appConfig?.pokaz != nil, let bundleID = targetBundleID, force || tick % 3 == 0 {
            checkPresentation(bundleID: bundleID, pid: pid)
            if targetPID == nil { return }
        }

        guard mode == .edit, needsFormattingState, config?.readsFormatting ?? true,
              Actions.isAXTrusted
        else { return }

        let state = reader.read(pid: pid)
        if loggedFormattingKnown != state.formattingKnown && state.isEditingText {
            loggedFormattingKnown = state.formattingKnown
            Log.write(state.formattingKnown
                      ? "Odczyt formatowania: działa (\(activeAppName ?? "?"))"
                      : "Odczyt formatowania: program nie udostępnia atrybutów tekstu – podświetlanie wyłączone")
        }
        apply(state)
    }

    private func apply(_ state: TextState) {
        let now = Date()

        if let control = formatControl, now > suppressFormatUntil {
            var values = [state.bold, state.italic, state.underline]
            if formatHasStrike { values.append(state.strike) }
            if !state.formattingKnown { values = values.map { _ in false } }
            for (i, value) in values.enumerated() where i < control.segmentCount {
                control.setSelected(value, forSegment: i)
            }
            formatPrevious = values
        }

        if let control = alignControl, now > suppressAlignUntil {
            if let a = state.alignment, a >= 0, a < control.segmentCount {
                control.selectedSegment = a
            } else {
                control.selectedSegment = -1
            }
        }

        if let control = sizeControl {
            let text: String
            if let size = state.size {
                text = size.rounded() == size ? String(Int(size)) : String(format: "%.1f", size)
            } else {
                text = "–"
            }
            if control.label(forSegment: 1) != text { control.setLabel(text, forSegment: 1) }
        }

        if let item = colorItem, now > suppressColorUntil, let color = state.color {
            item.color = color
        }
    }

    private func checkPresentation(bundleID: String, pid: pid_t) {
        guard let status = keynote.status(bundleID: bundleID) else { return }
        let wanted: Mode = status.playing ? .show : .edit
        if wanted != mode, let name = activeAppName {
            Log.write(status.playing ? "Keynote: rozpoczęto pokaz" : "Keynote: zakończono pokaz")
            show(mode: wanted, appName: name, pid: pid)
        }
        guard mode == .show, let s = scrubber else { return }
        if status.slideCount != slideCount {
            slideCount = status.slideCount
            s.reloadData()
        }
        let index = status.currentSlide - 1
        if index >= 0, index < slideCount, s.selectedIndex != index {
            s.selectedIndex = index
            s.scrollItem(at: index, to: .center)
        }
    }

    // MARK: - Dotknięcia

    @objc private func buttonTapped(_ sender: NSButton) {
        guard currentButtons.indices.contains(sender.tag) else {
            Log.write("Dotknięto przycisku o nieznanym numerze \(sender.tag)")
            return
        }
        let button = currentButtons[sender.tag]
        let outcome = Actions.perform(button, targetPID: targetPID)
        report(outcome, title: button.label)
    }

    @objc private func escTapped() {
        report(sendKey("esc"), title: "esc")
    }

    @objc private func formatChanged(_ sender: NSSegmentedControl) {
        let now = (0..<sender.segmentCount).map { sender.isSelected(forSegment: $0) }
        guard let index = now.indices.first(where: { $0 < formatPrevious.count && now[$0] != formatPrevious[$0] })
        else { return }
        formatPrevious = now
        suppressFormatUntil = Date().addingTimeInterval(0.7)

        let names = ["Pogrubienie", "Kursywa", "Podkreślenie", "Przekreślenie"]
        let outcome: Actions.Outcome
        switch index {
        case 0: outcome = sendKey("cmd+b")
        case 1: outcome = sendKey("cmd+i")
        case 2: outcome = sendKey("cmd+u")
        default: outcome = strikethrough()
        }
        report(outcome, title: names[min(index, names.count - 1)])
    }

    /// Przekreślenie nie ma skrótu – wybieramy je z menu Format → Czcionka.
    private func strikethrough() -> Actions.Outcome {
        guard Actions.isAXTrusted else { NSSound.beep(); return .noPermission }
        guard let pid = targetPID,
              Actions.pressMenu(path: ["Format", "Czcionka|Font", "Przekreślenie|Strikethrough"], pid: pid)
        else {
            NSSound.beep()
            return .failed("nie znaleziono polecenia Format → Czcionka → Przekreślenie")
        }
        return .ok
    }

    @objc private func alignChanged(_ sender: NSSegmentedControl) {
        let shortcuts = ["cmd+shift+[", "cmd+shift+\\", "cmd+shift+]", "alt+cmd+shift+\\"]
        let names = ["Do lewej", "Do środka", "Do prawej", "Wyjustuj"]
        let index = sender.selectedSegment
        guard shortcuts.indices.contains(index) else { return }
        suppressAlignUntil = Date().addingTimeInterval(1.0)
        report(sendKey(shortcuts[index]), title: names[index])
    }

    @objc private func sizeTapped(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: report(sendKey("cmd+-"), title: "Mniejsza czcionka")
        case 2: report(sendKey("cmd+shift+="), title: "Większa czcionka")
        default: break
        }
    }

    @objc private func undoTapped(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: report(sendKey("cmd+z"), title: "Cofnij")
        case 1: report(sendKey("cmd+shift+z"), title: "Ponów")
        default: break
        }
    }

    @objc private func colorPicked(_ sender: NSColorPickerTouchBarItem) {
        guard let pid = targetPID else { return }
        guard Actions.canPostEvents else { report(.noPermission, title: "Kolor"); return }
        suppressColorUntil = Date().addingTimeInterval(2.0)
        let color = sender.color
        colorApplier.apply(color, pid: pid, reader: reader) { [weak self] problem in
            if let problem {
                NSSound.beep()
                self?.report(.failed(problem), title: "Kolor")
            } else {
                self?.report(.ok, title: "Kolor")
            }
        }
    }

    private func sendKey(_ shortcut: String) -> Actions.Outcome {
        guard Actions.canPostEvents else { NSSound.beep(); return .noPermission }
        return Actions.sendShortcut(shortcut) ? .ok : .failed("nie udało się wysłać \(shortcut)")
    }

    private func report(_ outcome: Actions.Outcome, title: String) {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        switch outcome {
        case .ok:
            Log.write("„\(title)” → wysłano do \(front)")
        case .noPermission:
            Log.write("„\(title)” → ZABLOKOWANE: brak uprawnienia Dostępności")
            onPermissionMissing?()
        case .failed(let reason):
            Log.write("„\(title)” → błąd: \(reason)")
        }
    }

    // MARK: - Diagnostyka

    /// Opis tego, co program widzi w aktywnym programie (do dziennika zdarzeń).
    func diagnose() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "Brak aktywnego programu" }
        var text = reader.diagnose(pid: app.processIdentifier, appName: app.localizedName ?? "?")
        if let id = app.bundleIdentifier, id.lowercased().contains("keynote"),
           let status = keynote.status(bundleID: id) {
            text += "\nKeynote: pokaz=\(status.playing), slajdów=\(status.slideCount), bieżący=\(status.currentSlide)"
        }
        return text
    }
}

// MARK: - Numery slajdów (tryb pokazu)

extension TouchBarController: NSScrubberDataSource, NSScrubberDelegate, NSScrubberFlowLayoutDelegate {

    func numberOfItems(for scrubber: NSScrubber) -> Int {
        slideCount
    }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let view = scrubber.makeItem(withIdentifier: Self.slideItemID, owner: nil) as? NSScrubberTextItemView
            ?? NSScrubberTextItemView()
        view.textField.stringValue = "\(index + 1)"
        return view
    }

    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt itemIndex: Int) -> NSSize {
        NSSize(width: itemIndex + 1 >= 100 ? 52 : 40, height: 30)
    }

    /// W trakcie pokazu Keynote przechodzi do slajdu po wpisaniu jego numeru i Enter.
    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
        let number = selectedIndex + 1
        var outcome: Actions.Outcome = .ok
        for digit in String(number) {
            if case .ok = sendKey(String(digit)) { continue }
            outcome = .failed("nie udało się wpisać numeru slajdu")
            break
        }
        if case .ok = outcome { outcome = sendKey("return") }
        report(outcome, title: "Slajd \(number)")
    }
}

// MARK: - Kolor z zapisu HEX

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
