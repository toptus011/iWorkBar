// PrivateTouchBar.swift – wyświetlanie paska „systemowego” niezależnie od aktywnego programu
//
// Zwykły program może pokazywać przyciski na Touch Barze tylko wtedy, gdy sam jest aktywny.
// Narzędzia takie jak BetterTouchTool, MTMR czy Pock używają do tego nieudokumentowanych
// funkcji AppKit/DFRFoundation. Robimy tak samo, sprawdzając przed wywołaniem, czy dana
// funkcja istnieje – dzięki temu program się nie wysypie, gdy Apple coś zmieni.

import Cocoa

enum PrivateTouchBar {

    private typealias PresentFn = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString?) -> Void
    private typealias PresentShortFn = @convention(c) (AnyObject, Selector, NSTouchBar, NSString?) -> Void
    private typealias SetPresenceFn = @convention(c) (CFString, Bool) -> Void
    private typealias ShowCloseBoxFn = @convention(c) (Bool) -> Void

    private static let dfr: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

    static var isAvailable: Bool {
        presentSelector != nil || presentShortSelector != nil
    }

    private static var presentSelector: Selector? {
        for name in ["presentSystemModalTouchBar:placement:systemTrayItemIdentifier:",
                     "presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:"] {
            let sel = NSSelectorFromString(name)
            if class_getClassMethod(NSTouchBar.self, sel) != nil { return sel }
        }
        return nil
    }

    private static var presentShortSelector: Selector? {
        for name in ["presentSystemModalTouchBar:systemTrayItemIdentifier:",
                     "presentSystemModalFunctionBar:systemTrayItemIdentifier:"] {
            let sel = NSSelectorFromString(name)
            if class_getClassMethod(NSTouchBar.self, sel) != nil { return sel }
        }
        return nil
    }

    /// Ukrywa systemowy przycisk „X” przy pasku modalnym.
    static func hideCloseBox() {
        guard let dfr, let sym = dlsym(dfr, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        unsafeBitCast(sym, to: ShowCloseBoxFn.self)(false)
    }

    /// Dodaje ikonę do Control Strip, która po dotknięciu ponownie otwiera nasz pasek.
    static func addTrayItem(_ item: NSTouchBarItem) {
        let sel = NSSelectorFromString("addSystemTrayItem:")
        guard class_getClassMethod(NSTouchBarItem.self, sel) != nil else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(sel, with: item)
        setControlStripPresence(item.identifier.rawValue, true)
    }

    static func removeTrayItem(_ item: NSTouchBarItem) {
        setControlStripPresence(item.identifier.rawValue, false)
        let sel = NSSelectorFromString("removeSystemTrayItem:")
        guard class_getClassMethod(NSTouchBarItem.self, sel) != nil else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(sel, with: item)
    }

    private static func setControlStripPresence(_ identifier: String, _ present: Bool) {
        guard let dfr, let sym = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        unsafeBitCast(sym, to: SetPresenceFn.self)(identifier as CFString, present)
    }

    /// Pokazuje pasek. `fullWidth` = true zasłania też Control Strip.
    @discardableResult
    static func present(_ bar: NSTouchBar, fullWidth: Bool, trayIdentifier: String) -> Bool {
        let target: AnyObject = NSTouchBar.self as AnyObject
        if let sel = presentSelector, let method = class_getClassMethod(NSTouchBar.self, sel) {
            let fn = unsafeBitCast(method_getImplementation(method), to: PresentFn.self)
            fn(target, sel, bar, fullWidth ? 1 : 0, trayIdentifier as NSString)
            return true
        }
        if let sel = presentShortSelector, let method = class_getClassMethod(NSTouchBar.self, sel) {
            let fn = unsafeBitCast(method_getImplementation(method), to: PresentShortFn.self)
            fn(target, sel, bar, trayIdentifier as NSString)
            return true
        }
        return false
    }

    static func dismiss(_ bar: NSTouchBar) {
        for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
            let sel = NSSelectorFromString(name)
            if class_getClassMethod(NSTouchBar.self, sel) != nil {
                _ = (NSTouchBar.self as AnyObject).perform(sel, with: bar)
                return
            }
        }
    }

    static func minimize(_ bar: NSTouchBar) {
        for name in ["minimizeSystemModalTouchBar:", "minimizeSystemModalFunctionBar:"] {
            let sel = NSSelectorFromString(name)
            if class_getClassMethod(NSTouchBar.self, sel) != nil {
                _ = (NSTouchBar.self as AnyObject).perform(sel, with: bar)
                return
            }
        }
    }
}
