# iWorkBar – własny Touch Bar dla Pages, Keynote i Numbers

> Touch Bar support for Pages, Numbers and Keynote – brings the Touch Bar back to Apple iWork apps on MacBook Pro. 🇬🇧 English description below.

Własny Touch Bar dla Pages, Keynote i Numbers – przywraca przyciski formatowania, które nowe wersje iWork usunęły.

**Wymagania:** MacBook Pro z Touch Barem, macOS 13 Ventura lub nowszy, Mac z procesorem Apple.

## 🇬🇧 English

**iWorkBar brings the Touch Bar back to Pages, Numbers and Keynote.**

Recent versions of Apple's iWork apps (15.2 and later) no longer support the Touch Bar on
MacBook Pro. iWorkBar fixes that: whenever Pages, Numbers or Keynote is the active app, your
Touch Bar shows a set of editing buttons again. When you switch to another app, the Touch Bar
returns to normal.

**Features**
- **Pages:** undo/redo, **B I U S**, text alignment, font size (− 12 +), text color, comment.
- **Numbers:** undo/redo, insert formula, add rows above/below and columns before/after, **B I U**, alignment.
- **Keynote:** Play, new slide, formatting, alignment, size, color, bring to front.
  During a slideshow the bar switches to previous · slide numbers · next · end.
- **Live highlighting:** the Bold/Italic/Underline buttons light up when the cursor is in formatted text,
  and the size field shows the current font size.
- **Fully customizable** via a simple JSON file: any keyboard shortcut, menu command or AppleScript
  can become a Touch Bar button (with SF Symbols icons).
- Menu bar icon: edit buttons, reload, restore defaults, fix a frozen Touch Bar.
- **Dialogs:** when an Open, Save or “Keep changes?” window appears, iWorkBar steps aside so macOS shows the dialog’s own buttons (Save · Don’t Save · Cancel) on the Touch Bar.

**Requirements:** MacBook Pro with Touch Bar, Apple silicon, macOS 13 Ventura or later.

**Install:** download **iWorkBar.dmg** from **Releases**, drag iWorkBar to Applications and open it.
The first time, macOS may warn that the app is not from the App Store – go to
System Settings → Privacy & Security → **Open Anyway** (or run
`xattr -dr com.apple.quarantine /Applications/iWorkBar.app`). Then grant the **Accessibility**
permission when asked (System Settings → Privacy & Security → Accessibility → turn on iWorkBar).

The app's interface and the rest of this README are in Polish.

Made by ks. Piotr Bułka · MIT License

---

## 🇵🇱 Po polsku

## Instalacja – najprościej (gotowy plik)

1. Wejdź w zakładkę **Releases** po prawej stronie tej strony i pobierz plik **iWorkBar.dmg**.
2. Otwórz pobrany plik i przeciągnij **iWorkBar** na folder **Aplikacje**.
3. Przy pierwszym uruchomieniu macOS może ostrzec, że programu nie pobrano z App Store
   (nie jest podpisany certyfikatem Apple). Wtedy:
   **Ustawienia systemowe → Prywatność i ochrona →** na dole **„Otwórz mimo to”**.
   Alternatywnie w Terminalu:
   ```
   xattr -dr com.apple.quarantine "/Applications/iWorkBar.app"
   ```
4. Nadaj uprawnienia, o które poprosi program (opis niżej).

## Instalacja ze źródeł (zbudowanie samemu)

Potrzebne są tylko darmowe narzędzia wiersza poleceń Apple (pełny Xcode nie jest potrzebny).
Pobierz kod przyciskiem **Code → Download ZIP**, rozpakuj do Pobranych i w Terminalu uruchom
skrypt `zrob-dmg.sh` z rozpakowanego folderu (szczegóły niżej).

---

Opracował ks. Piotr Bułka

Nowe wersje iWork (15.2 i nowsze) przestały obsługiwać Touch Bar. iWorkBar przywraca
przyciski: gdy na wierzchu jest Pages, Keynote lub Numbers, na Touch Barze pojawia się
Twój zestaw przycisków. Po przejściu do innego programu pasek wraca do normalnego stanu.

## Instalator .dmg (najprościej)

1. Rozpakuj folder `iWorkBar`.
2. Otwórz **Terminal**, wpisz `bash ` (ze spacją), przeciągnij plik `zrob-dmg.sh`
   do okna i naciśnij Enter. Przy pierwszym razie macOS może poprosić o instalację
   „narzędzi wiersza poleceń” – zgódź się i potem uruchom skrypt ponownie.
3. Otworzy się okno instalatora: przeciągnij **iWorkBar** na folder **Aplikacje**.
4. Uruchom iWorkBar z Aplikacji i nadaj uprawnienie Dostępności (patrz niżej).

Plik `iWorkBar.dmg` zostaje w folderze – możesz go zachować na później.

## Instalacja bez .dmg (alternatywa, ok. 3 minuty)

1. Rozpakuj folder `iWorkBar` np. do Dokumentów.
2. Otwórz **Terminal**, wpisz `bash ` (ze spacją), przeciągnij plik `zbuduj.sh` do okna
   Terminala i naciśnij Enter.
3. Jeśli pojawi się prośba o instalację „narzędzi wiersza poleceń”, zgódź się, poczekaj
   do końca i powtórz punkt 2.
4. Po uruchomieniu iWorkBar poprosi o uprawnienie **Dostępności**. W Ustawieniach
   systemowych → Prywatność i ochrona → Dostępność włącz „iWorkBar”.
5. Otwórz Pages – przyciski powinny pojawić się na Touch Barze.

W menu ikony na pasku menu (u góry ekranu) włącz „Uruchamiaj przy logowaniu”.

## Ikona na pasku menu

- **Edytuj przyciski…** – otwiera plik `config.json` w TextEdit.
- **Wczytaj przyciski ponownie** – zastosuj zmiany po edycji (⌘R w tym menu).
- **Przywróć przyciski domyślne…** – gdy coś się popsuje w pliku.
- **Napraw Touch Bar** – restartuje procesy Touch Bara, gdy pasek się zawiesi (pyta o hasło).

## Co jest na pasku (wersja 2.0)

**Pages:** cofnij/ponów · **B I U S** · wyrównanie (lewo, środek, prawo, justowanie) ·
rozmiar czcionki (− 12 +) · kolor tekstu · komentarz.

**Keynote (edycja):** Odtwórz · nowy slajd · **B I U** · wyrównanie · rozmiar · kolor · na wierzch.
**Keynote (w trakcie pokazu):** pasek sam zmienia się na: poprzedni · numery slajdów · następny ·
zakończ. Dotknięcie numeru przenosi do slajdu.

**Podświetlanie:** gdy kursor stoi w pogrubionym tekście, przycisk B świeci na niebiesko
(tak samo kursywa, podkreślenie, przekreślenie), a pole rozmiaru pokazuje wielkość czcionki.
Wyrównanie podświetla się, gdy po prawej stronie jest otwarty panel **Format**.

**Kolor:** zaznacz fragment tekstu i wybierz kolor na pasku. iWorkBar kopiuje zaznaczenie,
zmienia kolor i wkleja z powrotem (schowek zostaje przywrócony, ⌘Z cofa zmianę).

### Pierwsze uruchomienie z Keynote
macOS zapyta, czy iWorkBar może sterować programem Keynote – kliknij **OK**. Dzięki temu
pasek wie, kiedy trwa pokaz. (Później: Ustawienia → Prywatność i ochrona → Automatyzacja.)

### Gdy podświetlanie nie działa
W menu ikony iWorkBar wybierz **„Sprawdź, co widzi iWorkBar (za 3 s)”**, a potem w ciągu
3 sekund **kliknij dwukrotnie słowo** w Pages (albo w polu tekstowym Keynote), tak żeby było
zaznaczone. Dziennik pokaże, jakie informacje o tekście udostępnia program – ten zapis warto przesłać.

Gdy iWorkBar nie widzi kursora, sam włącza w Pages/Keynote tryb dostępności używany przez
VoiceOver (zapis „Włączono tryb dostępności” w dzienniku). Po zamknięciu iWorkBar tryb
jest wyłączany.

## Jak dodać lub zmienić element paska

Plik: `~/Library/Application Support/iWorkBar/config.json`
(stary plik z wersji 1 został zachowany jako `config.v1.json`).

Gotowe elementy wpisuje się przez `"typ"`:

| Typ | Co robi |
|---|---|
| `formatowanie` | B I U; z `"przekreslenie": true` także S |
| `wyrownanie` | do lewej, do środka, do prawej, wyjustuj |
| `rozmiar` | mniejsza / bieżący rozmiar / większa |
| `kolor` | systemowy wybór koloru tekstu |
| `cofnij` | cofnij / ponów |
| `slajdy` | numery slajdów (tylko w sekcji `"pokaz"` Keynote) |

Zwykły przycisk (bez `typ`):

```json
{ "tytul": "Nowy slajd", "ikona": "plus.rectangle", "zTytulem": true, "skrot": "cmd+shift+n" }
```

| Pole | Znaczenie |
|---|---|
| `tytul` | nazwa przycisku (wyświetlana, gdy nie ma ikony) |
| `ikona` | nazwa symbolu z bezpłatnej aplikacji Apple **SF Symbols** (np. `bold`, `play.fill`) |
| `zTytulem` | `true` – pokaż ikonę i tytuł razem |
| `kolor` | kolor tła, np. `"#2E7D32"` |
| `szerokosc` | stała szerokość w punktach, np. `80` |
| `skrot` | skrót klawiszowy (patrz niżej) |
| `menu` | polecenie z menu programu, np. `["Wstaw|Insert", "Tabela|Table"]` |
| `applescript` | dowolny skrypt AppleScript |

**Zapis skrótów:** modyfikatory `cmd`, `shift`, `alt` (Option), `ctrl` oraz klawisz,
połączone znakiem `+`, np. `cmd+b`, `alt+cmd+p`, `alt+down`. Klawisze specjalne:
`esc`, `return`, `tab`, `space`, `delete`, `left`, `right`, `up`, `down`, `home`, `end`,
`pageup`, `pagedown`, `f1`…`f12`. Znak plus zapisz jako `plus`.

**Menu:** każdy poziom może mieć warianty nazw rozdzielone `|` – przydatne, bo nazwy
zależą od języka systemu. Wielokropek „…” na końcu nazwy można pominąć.

**Ustawienia ogólne** (na początku pliku):
- `pelnaSzerokosc` – `true` zasłania cały Touch Bar (bez głośności i jasności).
- `pokazEsc` – własny klawisz Esc po lewej stronie.
- `odczytFormatowania` – `false` wyłącza podświetlanie aktywnego formatowania.

Można dodać kolejne programy, np. `"Preview": { "przyciski": [ … ] }` – klucz to nazwa
programu widoczna w Docku.

## Gdy przyciski są widoczne, ale nie działają

1. Kliknij ikonę iWorkBar na pasku menu. Druga linijka pokazuje stan uprawnienia
   (✅ nadane / ❌ brak). Gdy ikona to trójkąt z wykrzyknikiem, uprawnienia brakuje.
2. Wyczyść stare wpisy jednym poleceniem w Terminalu:
   `tccutil reset Accessibility pl.bulka.iworkbar`
   Następnie uruchom iWorkBar i włącz go w Ustawieniach → Prywatność i ochrona → Dostępność.
   Po nadaniu uprawnienia program sam uruchomi się ponownie.
3. Menu → **Pokaż dziennik zdarzeń** – każde dotknięcie przycisku jest tam zapisane
   (np. „Pogrubienie → wysłano do Keynote” albo „ZABLOKOWANE: brak uprawnienia”).
   Ten plik warto przesłać, gdy coś nadal nie działa.

## Okna dialogowe (wersja 2.3.2)

Gdy Pages, Keynote lub Numbers pokazuje okno dialogowe – okno Otwórz przy uruchamianiu,
„Czy zachować zmiany?” albo Zapisz przy zamykaniu – iWorkBar chowa swój pasek, a macOS pokazuje
na Touch Barze **przyciski tego okna** (np. Nie zapisuj · Anuluj · Zapisz). Po zamknięciu okna
wracają narzędzia pisania. W dzienniku widać, kiedy okno zostało wykryte i dlaczego.

## Dobrze wiedzieć

- Pokazywanie paska nad innym programem korzysta z nieudokumentowanych funkcji macOS
  (tak samo jak BetterTouchTool, MTMR i Pock). Program sprawdza ich dostępność i nie
  zawiesi systemu, ale przyszła aktualizacja macOS może wymagać poprawki.
- Od wersji 1.2 aplikacja ma stały podpis, więc uprawnienie Dostępności powinno
  przetrwać kolejne aktualizacje.
- Gdy przycisk nie działa, Mac wyda krótki dźwięk – zwykle oznacza to błędny skrót albo
  inną nazwę pozycji menu.

## Licencja

MIT – możesz używać, zmieniać i rozpowszechniać, zachowując informację o autorze.

© 2026 ks. Piotr Bułka
