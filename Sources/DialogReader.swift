// DialogReader.swift – okna dialogowe w Pages/Keynote/Numbers („Zachować zmiany?”, Zapisz, Otwórz…)
//
// Gdy program pokazuje okno dialogowe lub arkusz (sheet), iWorkBar chowa swój pasek,
// a macOS sam pokazuje na Touch Barze przyciski tego okna (np. „Zapisz”, „Nie zapisuj”, „Anuluj”).

import Cocoa
import ApplicationServices

struct DialogButton {
    let title: String
    let element: AXUIElement
    let isDefault: Bool
    let isCancel: Bool
}

struct DialogInfo {
    let container: AXUIElement
    let kind: String               // „arkusz” / „okno dialogowe”
    let buttons: [DialogButton]
    let cancel: AXUIElement?
    /// Do porównania, czy zestaw przycisków się zmienił
    var signature: String { kind + "|" + buttons.map { $0.title + ($0.isDefault ? "*" : "") }.joined(separator: "|") }
}

enum DialogReader {

    /// Okno dialogowe programu albo nil (zwykłe okno dokumentu). Szybkie – kilka zapytań Dostępności.
    /// Drugi element to powód (do dziennika).
    static func container(pid: pid_t) -> (AXUIElement, String)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        let role = string(window, kAXRoleAttribute) ?? ""
        let subrole = string(window, kAXSubroleAttribute) ?? ""
        let title = (string(window, kAXTitleAttribute) ?? "").lowercased()

        // Arkusz („Czy zachować zmiany?”, okno Zapisz) jako okno aktywne…
        if role == "AXSheet" { return (window, "arkusz") }
        // …albo przyczepiony do okna dokumentu (dokument jest wtedy zablokowany)
        if let kids = children(window),
           let sheet = kids.first(where: { string($0, kAXRoleAttribute) == "AXSheet" }) {
            return (sheet, "arkusz w oknie dokumentu")
        }
        // Samodzielne okno dialogowe (komunikat, ostrzeżenie)
        if subrole == "AXDialog" || subrole == "AXSystemDialog" {
            return (window, "okno dialogowe (\(subrole))")
        }
        // Okno Otwórz / wybór szablonu / Zapisz przy uruchamianiu programu
        let dialogTitles = ["otwórz", "open", "zapisz", "save", "wybierz szablon", "choose a template",
                            "wybierz motyw", "choose a theme", "eksportuj", "export"]
        if dialogTitles.contains(where: { title == $0 || title.hasPrefix($0 + " ") }) {
            return (window, "okno „\(title)”")
        }
        // Okno z przyciskiem domyślnym lub „Anuluj” (np. inne okna wyboru)
        if element(window, kAXCancelButtonAttribute) != nil {
            return (window, "okno z przyciskiem Anuluj")
        }
        return nil
    }

    /// Pełny odczyt: okno dialogowe i jego przyciski (najwyżej 6).
    static func read(container: AXUIElement, kind: String) -> DialogInfo {
        let defaultButton = element(container, kAXDefaultButtonAttribute)
        let cancelButton = element(container, kAXCancelButtonAttribute)

        var found: [DialogButton] = []
        var queue: [(AXUIElement, Int)] = [(container, 0)]
        var visited = 0
        while !queue.isEmpty && visited < 400 && found.count < 8 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            let role = string(el, kAXRoleAttribute) ?? ""
            if role == "AXButton" {
                let title = (string(el, kAXTitleAttribute) ?? "").trimmingCharacters(in: .whitespaces)
                let enabled = (attribute(el, kAXEnabledAttribute) as? Bool) ?? true
                // Tylko przyciski z napisem (bez „?” pomocy, strzałek itp.)
                if enabled, title.count > 1 {
                    let isDefault = defaultButton.map { CFEqual($0, el) } ?? false
                    let isCancel = cancelButton.map { CFEqual($0, el) } ?? false
                    if !found.contains(where: { $0.title == title }) {
                        found.append(DialogButton(title: title, element: el, isDefault: isDefault, isCancel: isCancel))
                    }
                }
                continue
            }
            // Nie schodzimy w treść dokumentu ani długie listy plików
            if depth < 7, !["AXTable", "AXOutline", "AXList", "AXBrowser", "AXTextArea", "AXWebArea"].contains(role),
               let kids = children(el) {
                for kid in kids { queue.append((kid, depth + 1)) }
            }
        }
        // Kolejność jak w macOS: najpierw pozostałe, „Anuluj” przed domyślnym, domyślny na końcu (po prawej)
        let others = found.filter { !$0.isDefault && !$0.isCancel }
        let cancel = found.filter { $0.isCancel && !$0.isDefault }
        let main = found.filter { $0.isDefault }
        let ordered = Array((others + cancel + main).suffix(6))
        return DialogInfo(container: container, kind: kind, buttons: ordered, cancel: cancelButton)
    }

    /// Czy element leży wewnątrz `container` (idziemy w górę po rodzicach).
    private static func isInside(_ el: AXUIElement, _ container: AXUIElement) -> Bool {
        var current: AXUIElement? = el
        var steps = 0
        while let node = current, steps < 25 {
            if CFEqual(node, container) { return true }
            current = element(node, kAXParentAttribute)
            steps += 1
        }
        return false
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    // MARK: - Pomocnicze

    private static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(el, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        attribute(el, name) as? String
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement]? {
        attribute(el, kAXChildrenAttribute) as? [AXUIElement]
    }
}
