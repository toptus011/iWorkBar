// StateReader.swift – odczyt formatowania tekstu pod kursorem w Pages / Keynote / Numbers
//
// Korzysta z interfejsu Dostępności (tego samego, którego używa VoiceOver):
// - pogrubienie, kursywa, podkreślenie, przekreślenie, rozmiar i kolor czytamy
//   z atrybutów tekstu pod kursorem (AXAttributedStringForRange),
// - wyrównanie czytamy z przycisków wyrównania w panelu Format (gdy jest otwarty).
// Jeżeli program nie udostępnia tych danych, pasek nadal działa – tylko bez podświetlania.

import Cocoa
import ApplicationServices

struct TextState: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var size: Double?
    var color: NSColor?
    var alignment: Int?          // 0 lewo, 1 środek, 2 prawo, 3 justowanie
    var isEditingText = false    // kursor jest w polu tekstowym
    var hasSelection = false     // zaznaczono co najmniej jeden znak
    var formattingKnown = false  // udało się odczytać atrybuty tekstu
}

final class StateReader {

    private struct AlignmentGroup {
        let window: AXUIElement
        let buttons: [AXUIElement]   // kolejność: lewo, środek, prawo, justowanie
    }

    private var alignmentCache: [pid_t: AlignmentGroup] = [:]
    private var lastAlignmentSearch: [pid_t: Date] = [:]

    // Znaleziony element z kursorem (gdy program nie podaje go wprost)
    private var focusCache: [pid_t: AXUIElement] = [:]
    private var lastFocusSearch: [pid_t: Date] = [:]
    private var misses: [pid_t: Int] = [:]
    /// Programy, w których włączyliśmy tryb dostępności VoiceOvera (do wyłączenia przy zamknięciu).
    private(set) var enhancedPIDs: Set<pid_t> = []

    /// Skąd pochodzi ostatnio znaleziony element z kursorem (do diagnostyki).
    private(set) var lastFocusSource = "-"

    init() {
        // Krótki limit czasu – zawieszony program nie może zablokować naszego paska.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
    }

    func reset() {
        alignmentCache.removeAll()
        lastAlignmentSearch.removeAll()
        focusCache.removeAll()
        lastFocusSearch.removeAll()
        misses.removeAll()
    }

    // MARK: - Odczyt stanu

    func read(pid: pid_t) -> TextState {
        var state = TextState()
        let app = AXUIElementCreateApplication(pid)

        if let focused = focusedTextElement(app: app, pid: pid) {
            misses[pid] = 0
            if let range = selectedRange(focused) {
                state.isEditingText = true
                state.hasSelection = range.length > 0
                readAttributes(of: focused, around: range, into: &state)
            }
        } else {
            noteMiss(app: app, pid: pid)
        }

        state.alignment = readAlignment(app: app, pid: pid)
        return state
    }

    /// Element, w którym stoi kursor tekstowy. Trzy sposoby, od najtańszego:
    /// 1) program podaje go wprost, 2) pyta się całego systemu, 3) przeszukujemy okno.
    private func focusedTextElement(app: AXUIElement, pid: pid_t) -> AXUIElement? {
        let appFocused = element(app, kAXFocusedUIElementAttribute)
        if let f = appFocused, selectedRange(f) != nil {
            lastFocusSource = "program"
            return f
        }
        let system = AXUIElementCreateSystemWide()
        if let f = element(system, kAXFocusedUIElementAttribute), selectedRange(f) != nil {
            var owner: pid_t = 0
            if AXUIElementGetPid(f, &owner) == .success, owner == pid {
                lastFocusSource = "system"
                return f
            }
        }
        // Przeszukanie okna jest kosztowne – szukamy najwyżej co 1 s, a pomiędzy
        // korzystamy z zapamiętanego wyniku.
        let now = Date()
        if let last = lastFocusSearch[pid], now.timeIntervalSince(last) < 1 {
            if let cached = focusCache[pid], selectedRange(cached) != nil {
                lastFocusSource = "okno (zapamiętany)"
                return cached
            }
            return nil
        }
        lastFocusSearch[pid] = now
        // Pages podaje jako aktywny cały obszar dokumentu (AXScrollArea) – pole tekstowe
        // z kursorem jest w jego wnętrzu, więc najpierw szukamy tam, potem w całym oknie.
        if let area = appFocused, let found = searchFocusedText(in: area) {
            focusCache[pid] = found
            lastFocusSource = "wnętrze obszaru dokumentu"
            return found
        }
        guard let window = element(app, kAXFocusedWindowAttribute),
              let found = searchFocusedText(in: window)
        else {
            focusCache[pid] = nil
            return nil
        }
        focusCache[pid] = found
        lastFocusSource = "okno"
        return found
    }

    private func isFocused(_ el: AXUIElement) -> Bool {
        (attribute(el, kAXFocusedAttribute) as? NSNumber)?.boolValue ?? false
    }

    /// Szuka w oknie pola tekstowego z kursorem (AXFocused). Gdy program nie oznacza kursora,
    /// bierze pierwsze pole tekstowe, w którym coś jest zaznaczone.
    private func searchFocusedText(in window: AXUIElement) -> AXUIElement? {
        let skipRoles: Set<String> = ["AXTable", "AXOutline", "AXList", "AXMenuBar", "AXToolbar"]
        var queue: [AXUIElement] = [window]
        var visited = 0
        var withSelection: AXUIElement?
        while !queue.isEmpty && visited < 3000 {
            let node = queue.removeFirst()
            visited += 1
            let role = string(node, kAXRoleAttribute) ?? ""
            if skipRoles.contains(role) { continue }
            if Self.textRoles.contains(role), let range = selectedRange(node) {
                if isFocused(node) { return node }
                if withSelection == nil && range.length > 0 { withSelection = node }
            }
            queue.append(contentsOf: children(node))
        }
        return withSelection
    }

    /// Gdy przez ok. 2 s nie da się znaleźć kursora, włączamy w programie tryb dostępności,
    /// z którego korzysta VoiceOver – wtedy Pages i Keynote udostępniają pełny opis tekstu.
    private func noteMiss(app: AXUIElement, pid: pid_t) {
        let count = (misses[pid] ?? 0) + 1
        misses[pid] = count
        guard count == 6, !enhancedPIDs.contains(pid) else { return }
        if setEnhanced(app, true) {
            enhancedPIDs.insert(pid)
            Log.write("Włączono tryb dostępności (jak dla VoiceOver), żeby odczytać formatowanie tekstu")
        }
    }

    @discardableResult
    func setEnhanced(_ app: AXUIElement, _ on: Bool) -> Bool {
        let key = "AXEnhancedUserInterface" as CFString
        let result = on
            ? AXUIElementSetAttributeValue(app, key, kCFBooleanTrue)
            : AXUIElementSetAttributeValue(app, key, kCFBooleanFalse)
        return result == .success
    }

    /// Wyłącza tryb dostępności we wszystkich programach, w których go włączyliśmy.
    func restoreEnhanced() {
        for pid in enhancedPIDs {
            setEnhanced(AXUIElementCreateApplication(pid), false)
        }
        enhancedPIDs.removeAll()
    }

    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]

    private func selectedRange(_ el: AXUIElement) -> CFRange? {
        guard let raw = attribute(el, kAXSelectedTextRangeAttribute),
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Bierze pierwszy zaznaczony znak, a przy samym kursorze – znak przed nim
    /// (to jego formatowanie przejmie nowo wpisywany tekst).
    private func readAttributes(of el: AXUIElement, around range: CFRange, into state: inout TextState) {
        var location = range.location
        if range.length == 0 && location > 0 { location -= 1 }
        guard let attributed = attributedString(el, location: location) ?? attributedString(el, location: 0),
              attributed.length > 0
        else { return }

        let attrs = attributed.attributes(at: 0, effectiveRange: nil)
        state.formattingKnown = true

        if let font = attrs[Self.key("AXFont")] as? [String: Any] {
            if let size = font["AXFontSize"] as? NSNumber { state.size = size.doubleValue }
            if let name = font["AXFontName"] as? String {
                let traits = Self.traits(fontName: name)
                state.bold = traits.bold
                state.italic = traits.italic
            }
        }
        if let underline = attrs[Self.key("AXUnderline")] as? NSNumber {
            state.underline = underline.intValue != 0
        }
        if let strike = attrs[Self.key("AXStrikethrough")] as? NSNumber {
            state.strike = strike.intValue != 0
        }
        if let raw = attrs[Self.key("AXForegroundColor")] {
            let obj = raw as AnyObject
            if CFGetTypeID(obj) == CGColor.typeID {
                state.color = NSColor(cgColor: obj as! CGColor)
            }
        }
    }

    private func attributedString(_ el: AXUIElement, location: Int) -> NSAttributedString? {
        var range = CFRange(location: location, length: 1)
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            el, kAXAttributedStringForRangeParameterizedAttribute as CFString, value, &out)
        guard err == .success, let out else { return nil }
        return out as? NSAttributedString
    }

    private static func key(_ name: String) -> NSAttributedString.Key {
        NSAttributedString.Key(rawValue: name)
    }

    /// Pogrubienie i kursywa na podstawie nazwy kroju (np. "Helvetica-BoldOblique").
    static func traits(fontName: String) -> (bold: Bool, italic: Bool) {
        let lower = fontName.lowercased()
        var bold = ["bold", "black", "heavy", "semibold", "demibold", "extrabold", "ultrabold"]
            .contains { lower.contains($0) }
        var italic = lower.contains("italic") || lower.contains("oblique")
        if let font = NSFont(name: fontName, size: 12) {
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { bold = true }
            if traits.contains(.italicFontMask) { italic = true }
        }
        return (bold, italic)
    }

    // MARK: - Wyrównanie (panel Format)

    private func readAlignment(app: AXUIElement, pid: pid_t) -> Int? {
        if let group = alignmentCache[pid] {
            if let value = alignmentValue(group) { return value }
            alignmentCache[pid] = nil   // panel zamknięty lub okno zmienione
        }
        // Szukanie w całym oknie jest kosztowne – najwyżej raz na 2 sekundy.
        let now = Date()
        if let last = lastAlignmentSearch[pid], now.timeIntervalSince(last) < 2 { return nil }
        lastAlignmentSearch[pid] = now

        guard let window = element(app, kAXFocusedWindowAttribute),
              let group = findAlignmentGroup(in: window)
        else { return nil }
        alignmentCache[pid] = group
        return alignmentValue(group)
    }

    private func alignmentValue(_ group: AlignmentGroup) -> Int? {
        var anyRead = false
        for (index, button) in group.buttons.enumerated() {
            guard let raw = attribute(button, kAXValueAttribute) else { continue }
            anyRead = true
            if let number = raw as? NSNumber, number.intValue == 1 { return index }
        }
        // Brak odczytu = przyciski już nie istnieją; odczyt bez zaznaczenia = stan mieszany
        return anyRead ? -1 : nil
    }

    private static let alignmentWords: [[String]] = [
        ["lew", "left"],
        ["środ", "srod", "center", "centre", "wyśrodk"],
        ["praw", "right"],
        ["justu", "justif", "wyjust"],
    ]

    private static func alignmentIndex(for label: String) -> Int? {
        let l = label.lowercased()
        // Pomijamy wcięcia, marginesy i wyrównanie obiektów
        if ["wcię", "indent", "margin", "margines", "obiekt", "object"].contains(where: { l.contains($0) }) {
            return nil
        }
        for (index, words) in alignmentWords.enumerated() where words.contains(where: { l.contains($0) }) {
            return index
        }
        return nil
    }

    private func label(_ el: AXUIElement) -> String {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
            .compactMap { string(el, $0) }
            .joined(separator: " ")
    }

    /// Szuka czterech przycisków wyrównania, które mają wspólnego rodzica.
    private func findAlignmentGroup(in window: AXUIElement) -> AlignmentGroup? {
        let wantedRoles: Set<String> = ["AXRadioButton", "AXCheckBox", "AXButton"]
        let skipRoles: Set<String> = ["AXTextArea", "AXLayoutArea", "AXTable", "AXOutline", "AXList", "AXWebArea"]

        var queue: [AXUIElement] = [window]
        var visited = 0
        while !queue.isEmpty && visited < 4000 {
            let node = queue.removeFirst()
            visited += 1
            let role = string(node, kAXRoleAttribute) ?? ""
            if skipRoles.contains(role) { continue }

            let kids = children(node)
            // Czy wśród dzieci tego węzła są wszystkie cztery przyciski wyrównania?
            var found: [Int: AXUIElement] = [:]
            for kid in kids {
                guard wantedRoles.contains(string(kid, kAXRoleAttribute) ?? ""),
                      let index = Self.alignmentIndex(for: label(kid)),
                      found[index] == nil
                else { continue }
                found[index] = kid
            }
            if found.count == 4, let a = found[0], let b = found[1], let c = found[2], let d = found[3] {
                return AlignmentGroup(window: window, buttons: [a, b, c, d])
            }
            queue.append(contentsOf: kids)
        }
        return nil
    }

    // MARK: - Pomocnicze funkcje Dostępności

    private func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &ref) == .success else { return nil }
        return ref
    }

    private func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let raw = attribute(el, name), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private func string(_ el: AXUIElement, _ name: String) -> String? {
        attribute(el, name) as? String
    }

    private func children(_ el: AXUIElement) -> [AXUIElement] {
        (attribute(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    // MARK: - Diagnostyka

    /// Opisuje, co program widzi w aktywnym oknie – do dziennika zdarzeń.
    func diagnose(pid: pid_t, appName: String) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var lines: [String] = ["=== Diagnostyka iWorkBar \(version): \(appName) ==="]
        let app = AXUIElementCreateApplication(pid)
        lines.append("Dostępność(AX)=\(AXIsProcessTrusted()), tryb VoiceOver włączony przez iWorkBar=\(enhancedPIDs.contains(pid))")

        let direct = element(app, kAXFocusedUIElementAttribute)
        lines.append("Element z kursorem wg programu: " + (direct.map { describe($0) } ?? "BRAK"))
        let system = element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
        lines.append("Element z kursorem wg systemu: " + (system.map { describe($0) } ?? "BRAK"))

        if let window = element(app, kAXFocusedWindowAttribute) {
            lines.append("Okno: \(string(window, kAXTitleAttribute) ?? "?")")
            lines.append("Zawartość okna: " + summarize(window))
        } else {
            lines.append("Okno: BRAK (program nie udostępnia okna)")
        }

        // Próba z trybem VoiceOvera, jeżeli bez niego nie widać kursora
        var focused = focusedTextElement(app: app, pid: pid)
        if focused == nil && !enhancedPIDs.contains(pid) {
            lines.append("Kursora nie widać – próba z trybem dostępności VoiceOvera…")
            if setEnhanced(app, true) {
                enhancedPIDs.insert(pid)
                usleep(600_000)
                lastFocusSearch[pid] = nil
                focused = focusedTextElement(app: app, pid: pid)
                lines.append("Po włączeniu trybu: " + (focused.map { describe($0) } ?? "nadal BRAK"))
                if let window = element(app, kAXFocusedWindowAttribute) {
                    lines.append("Zawartość okna po włączeniu: " + summarize(window))
                }
            } else {
                lines.append("Programu nie da się przełączyć w tryb VoiceOvera")
            }
        }

        if let focused {
            lines.append("Użyty element (\(lastFocusSource)): \(describe(focused))")
            var params: CFArray?
            if AXUIElementCopyParameterizedAttributeNames(focused, &params) == .success, let list = params as? [String] {
                lines.append("Atrybuty z parametrem: \(list.joined(separator: ", "))")
            }
            if let range = selectedRange(focused) {
                lines.append("Zaznaczenie: od \(range.location), długość \(range.length)")
                let location = range.length == 0 && range.location > 0 ? range.location - 1 : range.location
                if let attributed = attributedString(focused, location: location), attributed.length > 0 {
                    for (k, v) in attributed.attributes(at: 0, effectiveRange: nil) {
                        lines.append("  \(k.rawValue) = \(String(describing: v).replacingOccurrences(of: "\n", with: " "))")
                    }
                } else {
                    lines.append("Atrybuty tekstu: NIEDOSTĘPNE")
                }
            }
        }

        let state = read(pid: pid)
        lines.append("Wynik: B=\(state.bold) I=\(state.italic) U=\(state.underline) S=\(state.strike) "
                     + "rozmiar=\(state.size.map { String($0) } ?? "?") "
                     + "wyrównanie=\(state.alignment.map { String($0) } ?? "nieznane (otwórz panel Format)") "
                     + "kursor w tekście=\(state.isEditingText) zaznaczenie=\(state.hasSelection)")
        if let group = alignmentCache[pid] {
            lines.append("Przyciski wyrównania: " + group.buttons.map { label($0) }.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    private func describe(_ el: AXUIElement) -> String {
        let role = string(el, kAXRoleAttribute) ?? "?"
        let sub = string(el, kAXSubroleAttribute) ?? "-"
        var names: CFArray?
        var attrs = ""
        if AXUIElementCopyAttributeNames(el, &names) == .success, let list = names as? [String] {
            attrs = list.joined(separator: ",")
        }
        return "rola=\(role) podrola=\(sub) opis=\(label(el)) atrybuty=[\(attrs)]"
    }

    /// Ile jest elementów każdej roli w oknie (pierwsze 1500 elementów).
    private func summarize(_ window: AXUIElement) -> String {
        var counts: [String: Int] = [:]
        var withSelection = 0
        var queue: [AXUIElement] = [window]
        var visited = 0
        while !queue.isEmpty && visited < 1500 {
            let node = queue.removeFirst()
            visited += 1
            let role = string(node, kAXRoleAttribute) ?? "?"
            counts[role, default: 0] += 1
            if Self.textRoles.contains(role), selectedRange(node) != nil { withSelection += 1 }
            queue.append(contentsOf: children(node))
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)×\($0.value)" }
        return "\(visited) elementów; pola tekstowe z kursorem/zaznaczeniem: \(withSelection); " + top.joined(separator: ", ")
    }
}
