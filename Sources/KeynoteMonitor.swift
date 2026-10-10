// KeynoteMonitor.swift – sprawdza, czy Keynote odtwarza prezentację, i który slajd jest na ekranie
//
// Korzysta z AppleScript (słownik Keynote: właściwość „playing” i „current slide”).
// Przy pierwszym użyciu macOS zapyta, czy iWorkBar może sterować programem Keynote.

import Cocoa

final class KeynoteMonitor {

    struct Status: Equatable {
        var playing: Bool
        var slideCount: Int
        var currentSlide: Int
    }

    private var script: NSAppleScript?
    private var scriptBundleID = ""
    private var lastErrorCode: Int?

    func status(bundleID: String) -> Status? {
        if script == nil || scriptBundleID != bundleID {
            let source = """
            with timeout of 1 second
                tell application id "\(bundleID)"
                    try
                        if playing then
                            set d to front document
                            return {true, (count of slides of d), (slide number of current slide of d)}
                        end if
                    end try
                    return {false, 0, 0}
                end tell
            end timeout
            """
            script = NSAppleScript(source: source)
            scriptBundleID = bundleID
        }

        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error) else {
            let code = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            if code != lastErrorCode {
                lastErrorCode = code
                if code == -1743 {
                    Log.write("Keynote: brak zgody na sterowanie – włącz iWorkBar w Ustawieniach → "
                              + "Prywatność i ochrona → Automatyzacja → Keynote")
                } else {
                    Log.write("Keynote: nie udało się odczytać stanu pokazu (kod \(code))")
                }
            }
            return nil
        }
        lastErrorCode = nil
        guard result.numberOfItems >= 3 else { return nil }
        return Status(
            playing: result.atIndex(1)?.booleanValue ?? false,
            slideCount: Int(result.atIndex(2)?.int32Value ?? 0),
            currentSlide: Int(result.atIndex(3)?.int32Value ?? 0)
        )
    }
}
