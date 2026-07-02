# ClaudeLights — Feature-Ausbau & Direktvertrieb (Design)

Datum: 2026-07-01
Status: Freigegeben

## Ausgangslage
ClaudeLights v1 zeigt den Status laufender Claude-Code-Sessions als Ampel in der
Menüleiste (grün/gelb/rot), gespeist aus `~/.claude/claudelights-status.json`,
gefüttert von drei Hook-Skripten, beobachtet per `DispatchSource`-Dateiwatcher.

Dieses Dokument beschreibt den Ausbau zu einem direkt vertriebenen Produkt
(`.dmg` statt Mac App Store) plus neue Features.

## Freigegebene Entscheidungen
- **Vertrieb:** ausschließlich `.dmg`, Developer-ID-signiert + notarisiert;
  Auto-Updates über **Sparkle**.
- **Terminal:** Auswahl der Terminal-App in den Einstellungen; **Klick auf eine
  Session im Panel holt die gewählte Terminal-App in den Vordergrund** (App-Ebene,
  kein Einzelfenster-Fokus).
- **Benachrichtigungen:** **pro Status einzeln** ein-/ausschaltbar
  (working / done / needs_input).
- **Extras:** Popover-Panel statt `NSMenu`, Sound bei `needs_input`,
  Session-Historie, Sessions manuell entfernbar.

## Bewusste Abweichungen von „nur AppKit / minimale Deps"
1. **SwiftUI im Popover** (via `NSHostingController` in `NSPopover`) für die
   klickbare Liste, Settings-Toggles und Historie. SwiftUI ist Teil des Systems,
   keine externe Abhängigkeit. Der Rest der App bleibt AppKit.
2. **Sparkle** als einzige externe Abhängigkeit (nur für Auto-Updates beim
   Direktvertrieb), eingebunden per Swift Package Manager.

## Architektur

Datenfluss (unverändert im Kern):
```
Hooks → claudelights-status.json → FileWatcher → SessionStore(+Diff)
      → AppModel → { Popover-UI · NotificationManager · Sound · SessionHistory }
```

Bausteine (neu/geändert):

| Baustein | Zweck |
|---|---|
| `Preferences` | UserDefaults-Wrapper: Terminal-Wahl, Notify-Flags je Status, Sound an/aus |
| `AppModel` | `ObservableObject` als einzige UI-Quelle; hält Sessions + Intents (activate/remove/quit/login) |
| `TerminalLauncher` | Holt die konfigurierte Terminal-App nach vorn (Bundle-ID → `NSWorkspace`) |
| `NotificationManager` | `UNUserNotificationCenter`: Auth, Notifications feuern, Klick → `TerminalLauncher` |
| `SessionHistory` | Persistiertes rollierendes Log der Statusübergänge (Application Support) |
| `SessionStore` (erweitert) | Übergangs-Erkennung: alten Zustand je `session_id` merken, Diff → Events |
| Popover-UI (SwiftUI) | `PanelView`: Session-Liste (Klick→Terminal, Entfernen), Settings (Terminal, Notify-Toggles, Sound, Start-at-Login), Historie, Quit |
| `StatusController` (umgebaut) | `NSStatusItem`-Button toggelt Popover statt Menü; färbt das Icon |
| Hooks (erweitert) | zusätzlich `TERM_PROGRAM` erfassen → Feld `term` im JSON |

## Roadmap (inkrementell)
- **Phase 1 – Popover-Panel:** `Preferences` + `AppModel` + SwiftUI-`PanelView`
  (Session-Liste, Start-at-Login, Quit) ersetzt das `NSMenu`; `StatusController`
  auf `NSPopover` umgebaut.
- **Phase 2 – Terminal-Auswahl & Klick-Aktion:** Picker in Settings,
  `TerminalLauncher`, `TERM_PROGRAM` in Hooks, Klick-auf-Session-öffnet-Terminal.
- **Phase 3 – Desktop-Benachrichtigungen:** `NotificationManager`,
  Übergangs-Erkennung im Store, Toggles pro Status, Sound bei `needs_input`,
  Klick auf Notification → Terminal.
- **Phase 4 – Historie & manuelles Entfernen:** `SessionHistory` (persistiert) +
  UI; Entfernen einzeln / alle erledigten.
- **Phase 5 – Vertrieb als `.dmg`:** Sparkle einbauen, `scripts/`
  (archive · sign · notarize · dmg · appcast), `SUFeedURL` in Info.plist,
  README-Vertriebskapitel.

## Bekannte Einschränkungen
- Desktop-Benachrichtigungen funktionieren zuverlässig erst im signierten/
  notarisierten Build; im lokalen `swiftc`-Schnellbundle kann macOS die
  Zustellung blocken (Code muss dort robust bleiben, nicht crashen).
- Phase 5 wird als Skripte + Xcode-Setup vorbereitet, aber erst mit vollem Xcode
  ausführbar (hier nur Command Line Tools installiert).
