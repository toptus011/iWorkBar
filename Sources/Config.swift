// Config.swift – wczytywanie konfiguracji paska z pliku JSON

import Foundation

/// Jeden element paska.
///
/// `typ` decyduje o rodzaju elementu:
/// - "przycisk" (domyślny) – zwykły przycisk z akcją `skrot`, `menu` albo `applescript`
/// - "formatowanie" – połączone przyciski B I U (oraz S, gdy `przekreslenie` = true)
/// - "wyrownanie"   – do lewej, do środka, do prawej, wyjustuj
/// - "rozmiar"      – mniejsza / bieżący rozmiar / większa
/// - "kolor"        – systemowy wybór koloru tekstu
/// - "cofnij"       – cofnij / ponów
/// - "slajdy"       – numery slajdów Keynote (tylko w trybie pokazu)
struct ButtonConfig: Codable {
    var typ: String?
    var tytul: String?
    var ikona: String?          // nazwa symbolu SF Symbols, np. "bold"
    var zTytulem: Bool?         // pokaż ikonę i tytuł razem (domyślnie tylko ikona)
    var kolor: String?          // kolor tła przycisku w HEX, np. "#2D6CDF"
    var szerokosc: Double?      // stała szerokość przycisku w punktach
    var skrot: String?
    var menu: [String]?         // np. ["Format|Format", "Czcionka|Font", "Pogrubienie|Bold"]
    var applescript: String?
    var przekreslenie: Bool?    // dla typu "formatowanie"

    var kind: String { (typ ?? "przycisk").lowercased() }
    var label: String { tytul ?? typ ?? "" }
}

struct AppConfig: Codable {
    var przyciski: [ButtonConfig]
    /// Pasek pokazywany w trakcie prezentacji (Keynote).
    var pokaz: [ButtonConfig]?
}

struct Config: Codable {
    /// Wersja formatu pliku. Starsze pliki są automatycznie zastępowane nowym zestawem.
    var wersja: Int?
    /// true – pasek zajmuje cały Touch Bar (bez Control Strip z głośnością i jasnością)
    var pelnaSzerokosc: Bool?
    /// pokaż własny klawisz Esc na początku paska
    var pokazEsc: Bool?
    /// podświetlaj aktywne formatowanie tekstu pod kursorem
    var odczytFormatowania: Bool?
    /// klucz: nazwa programu ("Pages") lub fragment identyfikatora ("com.apple.iWork.Pages")
    var aplikacje: [String: AppConfig]

    var fullWidth: Bool { pelnaSzerokosc ?? false }
    var showEsc: Bool { pokazEsc ?? true }
    var readsFormatting: Bool { odczytFormatowania ?? true }

    /// Znajduje konfigurację dla programu po nazwie lub identyfikatorze pakietu.
    func appConfig(name: String?, bundleID: String?) -> (String, AppConfig)? {
        for (key, value) in aplikacje {
            let k = key.lowercased()
            if let n = name?.lowercased(), n == k { return (key, value) }
            if let b = bundleID?.lowercased(), b == k || b.hasSuffix("." + k) { return (key, value) }
        }
        return nil
    }
}

/// Błąd wczytywania konfiguracji z opisem dla człowieka.
struct ConfigError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

enum ConfigStore {
    static let currentVersion = 2

    static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("iWorkBar", isDirectory: true)
    }

    static var fileURL: URL { folderURL.appendingPathComponent("config.json") }

    /// Przy pierwszym uruchomieniu kopiuje domyślną konfigurację z pakietu aplikacji.
    static func ensureExists() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: fileURL.path) else { return }
        if let bundled = Bundle.main.url(forResource: "config.default", withExtension: "json") {
            try? fm.copyItem(at: bundled, to: fileURL)
        }
    }

    /// Plik z wersji 1.x zostaje zachowany jako config.v1.json i zastąpiony nowym zestawem.
    private static func migrateIfNeeded(_ config: Config) -> Bool {
        guard (config.wersja ?? 1) < currentVersion else { return false }
        let fm = FileManager.default
        let backup = folderURL.appendingPathComponent("config.v1.json")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: fileURL, to: backup)
        ensureExists()
        Log.write("Konfiguracja z wersji 1 zapisana jako config.v1.json – wczytano nowy zestaw paska")
        return true
    }

    /// Wczytuje konfigurację. Zwraca błąd czytelny dla człowieka, gdy JSON jest niepoprawny.
    static func load() -> Result<Config, ConfigError> {
        ensureExists()
        do {
            var config = try decode()
            if migrateIfNeeded(config) { config = try decode() }
            return .success(config)
        } catch let DecodingError.dataCorrupted(ctx) {
            return .failure(ConfigError("Błąd składni JSON: \(ctx.debugDescription)"))
        } catch let DecodingError.keyNotFound(key, _) {
            return .failure(ConfigError("Brakuje pola „\(key.stringValue)” w konfiguracji."))
        } catch let DecodingError.typeMismatch(_, ctx) {
            let path = ctx.codingPath.map { $0.stringValue }.joined(separator: " → ")
            return .failure(ConfigError("Zły typ wartości w: \(path)"))
        } catch {
            return .failure(ConfigError("Nie można wczytać pliku: \(error.localizedDescription)"))
        }
    }

    private static func decode() throws -> Config {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Config.self, from: data)
    }
}
