// ColorApplier.swift – zmiana koloru zaznaczonego tekstu
//
// Pages i Keynote nie mają skrótu ani polecenia „ustaw kolor zaznaczenia”, które można
// wywołać z zewnątrz. Dlatego: kopiujemy zaznaczenie (⌘C), zmieniamy kolor w kopii,
// wklejamy z powrotem (⌘V) i przywracamy wcześniejszą zawartość schowka.
// Reszta formatowania (krój, rozmiar, pogrubienie, wyrównanie) zostaje zachowana,
// a jedno ⌘Z cofa całą zmianę.

import Cocoa

final class ColorApplier {

    private var busy = false

    /// `completion` dostaje nil przy powodzeniu albo opis problemu.
    func apply(_ color: NSColor, pid: pid_t, reader: StateReader, completion: @escaping (String?) -> Void) {
        guard !busy else { completion("poprzednia zmiana koloru jeszcze trwa"); return }

        // Bezpiecznik: działamy tylko na zaznaczonym fragmencie tekstu w trakcie edycji.
        // Inaczej ⌘C/⌘V mogłoby skopiować i wkleić cały obiekt (np. pole tekstowe w Keynote).
        let state = reader.read(pid: pid)
        guard state.isEditingText else {
            completion("kursor nie jest w tekście – kliknij w tekst i zaznacz fragment"); return
        }
        guard state.hasSelection else {
            completion("najpierw zaznacz fragment tekstu"); return
        }

        busy = true
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount

        Actions.sendShortcut("cmd+c")
        waitForChange(pasteboard, from: before, attempts: 20) { [weak self] changed in
            guard let self else { return }
            guard changed else {
                self.finish(restoring: saved, error: "program nie skopiował zaznaczenia", completion: completion)
                return
            }
            guard let recolored = self.recolor(pasteboard, with: color) else {
                let types = pasteboard.types?.map { $0.rawValue }.joined(separator: ", ") ?? "-"
                self.finish(restoring: saved, error: "w schowku brak tekstu z formatowaniem (typy: \(types))",
                            completion: completion)
                return
            }

            pasteboard.clearContents()
            pasteboard.setData(recolored.rtf, forType: .rtf)
            pasteboard.setString(recolored.plain, forType: .string)

            Actions.sendShortcut("cmd+v")
            // Dajemy programowi chwilę na odczyt schowka, zanim go przywrócimy.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.finish(restoring: saved, error: nil, completion: completion)
            }
        }
    }

    private func finish(restoring saved: [NSPasteboardItem], error: String?, completion: (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        busy = false
        completion(error)
    }

    // MARK: - Schowek

    private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private func waitForChange(_ pasteboard: NSPasteboard, from count: Int, attempts: Int,
                               done: @escaping (Bool) -> Void) {
        if pasteboard.changeCount != count { done(true); return }
        guard attempts > 0 else { done(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.waitForChange(pasteboard, from: count, attempts: attempts - 1, done: done)
        }
    }

    /// Odczytuje sformatowany tekst ze schowka i nadaje mu nowy kolor.
    private func recolor(_ pasteboard: NSPasteboard, with color: NSColor) -> (rtf: Data, plain: String)? {
        let candidates: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.rtfd, .rtfd), (.rtf, .rtf),
        ]
        for (type, docType) in candidates {
            guard let data = pasteboard.data(forType: type),
                  let text = try? NSMutableAttributedString(
                      data: data, options: [.documentType: docType], documentAttributes: nil),
                  text.length > 0
            else { continue }

            let range = NSRange(location: 0, length: text.length)
            let srgb = color.usingColorSpace(.sRGB) ?? color
            text.addAttribute(.foregroundColor, value: srgb, range: range)
            guard let rtf = text.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            else { continue }
            return (rtf, text.string)
        }
        return nil
    }
}
