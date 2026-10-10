// Actions.swift – wykonywanie akcji przycisków: skróty klawiszowe, polecenia menu, AppleScript

import Cocoa
import ApplicationServices

enum Actions {

    // MARK: - Uprawnienia

    /// Sprawdza (i opcjonalnie prosi o) uprawnienie Dostępności, potrzebne do wysyłania skrótów
    /// i do wybierania poleceń z menu innego programu.
    @discardableResult
    static func checkAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
        if prompt && !CGPreflightPostEventAccess() {
            // Dopisuje program do listy „Dostępność” w Ustawieniach (osobna ścieżka niż AX).
            _ = CGRequestPostEventAccess()
        }
        return trusted
    }

    /// Czy macOS pozwala wysyłać zdarzenia klawiatury do innych programów.
    /// Oba testy dotyczą tego samego przełącznika „Dostępność”; wystarczy jeden pozytywny,
    /// żeby nie zablokować przycisku przez ewentualny błąd jednego z nich.
    static var canPostEvents: Bool { CGPreflightPostEventAccess() || AXIsProcessTrusted() }

    /// Czy macOS pozwala sterować menu innych programów.
    static var isAXTrusted: Bool { AXIsProcessTrusted() }

    // MARK: - Wykonanie przycisku

    enum Outcome {
        case ok
        case noPermission
        case failed(String)
    }

    @discardableResult
    static func perform(_ button: ButtonConfig, targetPID: pid_t?) -> Outcome {
        let outcome: Outcome
        if let shortcut = button.skrot {
            if !canPostEvents {
                outcome = .noPermission
            } else if sendShortcut(shortcut) {
                outcome = .ok
            } else {
                outcome = .failed("nieznany skrót „\(shortcut)”")
            }
        } else if let path = button.menu {
            if !isAXTrusted {
                outcome = .noPermission
            } else if let pid = targetPID, pressMenu(path: path, pid: pid) {
                outcome = .ok
            } else {
                outcome = .failed("nie znaleziono w menu: \(path.joined(separator: " → "))")
            }
        } else if let script = button.applescript {
            outcome = runAppleScript(script) ? .ok : .failed("błąd AppleScript")
        } else {
            outcome = .failed("przycisk nie ma akcji (skrot / menu / applescript)")
        }

        switch outcome {
        case .ok: break
        case .noPermission, .failed: NSSound.beep()
        }
        return outcome
    }

    // MARK: - Skróty klawiszowe

    /// Kody klawiszy (pozycje fizyczne; zgodne z układem Polski Pro).
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "spacja": 49,
        "`": 50, "delete": 51, "backspace": 51, "esc": 53, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "lewo": 123, "prawo": 124, "dol": 125, "gora": 126,
    ]

    /// Klawisze, które na prawdziwej klawiaturze niosą flagę Fn (strzałki, Home, End…).
    private static let fnKeys: Set<CGKeyCode> = [115, 116, 117, 119, 121, 123, 124, 125, 126]
    private static let arrowKeys: Set<CGKeyCode> = [123, 124, 125, 126]

    /// Przyjmuje zapis typu "cmd+shift+n", "alt+down", "esc".
    static func parseShortcut(_ text: String) -> (CGKeyCode, CGEventFlags)? {
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        // "+" jako separator; obsługa klawisza "+" zapisanego jako "plus"
        for raw in text.lowercased().split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "alt", "opt", "option", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "plus": key = 24; flags.insert(.maskShift)
            default:
                guard let code = keyCodes[part] else { return nil }
                key = code
            }
        }
        guard let k = key else { return nil }
        if fnKeys.contains(k) { flags.insert(.maskSecondaryFn) }
        if arrowKeys.contains(k) { flags.insert(.maskNumericPad) }
        return (k, flags)
    }

    @discardableResult
    static func sendShortcut(_ text: String) -> Bool {
        guard let (code, flags) = parseShortcut(text) else {
            Log.write("Nieznany skrót: \(text)")
            return false
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Polecenia menu (przez Dostępność)

    /// Ścieżka w menu, np. ["Tabela|Table", "Scal komórki|Merge Cells"].
    /// Każdy element może zawierać warianty rozdzielone „|” (różne języki systemu).
    static func pressMenu(path: [String], pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef
        else { return false }
        var current = menuBarRef as! AXUIElement

        for (index, segment) in path.enumerated() {
            let names = segment.split(separator: "|").map { normalize(String($0)) }
            guard let found = findChild(of: current, matching: names) else {
                Log.write("Nie znaleziono pozycji menu: \(segment)")
                return false
            }
            if index == path.count - 1 {
                return AXUIElementPerformAction(found, kAXPressAction as CFString) == .success
            }
            // Pozycja menu → jej podmenu (AXMenu) jest pierwszym dzieckiem
            guard let submenu = children(of: found).first else { return false }
            current = submenu
        }
        return false
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let list = ref as? [AXUIElement]
        else { return [] }
        return list
    }

    private static func title(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }

    /// Szuka wśród dzieci elementu (także w pośrednim AXMenu) pozycji o pasującym tytule.
    private static func findChild(of element: AXUIElement, matching names: [String]) -> AXUIElement? {
        var queue = children(of: element)
        var depth = 0
        while !queue.isEmpty && depth < 2 {
            var next: [AXUIElement] = []
            for child in queue {
                if let t = title(of: child), names.contains(normalize(t)) { return child }
                next.append(contentsOf: children(of: child))
            }
            queue = next
            depth += 1
        }
        return nil
    }

    /// Porównanie bez wielkości liter i bez wielokropka na końcu („Wstaw…” = „Wstaw”).
    private static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces).lowercased()
        while t.hasSuffix("…") || t.hasSuffix(".") { t.removeLast() }
        return t
    }

    // MARK: - AppleScript

    @discardableResult
    static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            Log.write("Błąd AppleScript: \(error)")
            return false
        }
        return true
    }

    // MARK: - Naprawa Touch Bara

    /// Restartuje procesy Touch Bara (wymaga hasła administratora).
    @discardableResult
    static func restartTouchBar() -> Bool {
        let script = "do shell script \"pkill TouchBarServer; killall ControlStrip; exit 0\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }
}
