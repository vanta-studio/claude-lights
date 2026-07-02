# ClaudeLights

A native macOS menu bar app that shows the status of your running
[Claude Code](https://claude.com/claude-code) sessions as a traffic-light icon.

- 🟢 **Green** — Claude Code is done / waiting for a new prompt
- 🟡 **Yellow** — Claude Code is working
- 🔴 **Red** — Claude Code needs your input (permission, question, idle prompt)

With multiple sessions running in parallel, the menu bar shows the **worst**
status (`needs_input` > `working` > `done`) so a single glance tells you whether
anything needs attention. Clicking the icon opens a panel that lists every
active session with its individual status and last-updated time.

### Features
- **Popover panel** listing all active sessions (worst first), with a colored
  status dot and live relative time.
- **Five states**: 🟢 done · 🟡 working · 🔵 compacting (PreCompact) · 🔴 needs
  input · ⚪️ idle (a long-done session, dimmed).
- **Click a session → jump to its terminal window**: focuses the exact window/tab
  (Terminal.app / iTerm2 via the captured tty), falling back to activating the
  terminal app chosen in Settings.
- **Desktop notifications**, individually toggleable per state, coalesced
  (debounced) to avoid spam on rapid flips, plus an optional **sound on needs
  input**.
- **Usage**: today's token counts (input / output / cache) read straight from
  Claude Code's transcripts, plus **time spent per state** today.
- **History** of recent state transitions (persisted).
- **Auto-cleanup**: finished sessions are removed on `SessionEnd`; anything left
  behind expires after 2 hours. Plus manual remove / clear finished.
- **Auto-updates** via Sparkle, **Start at Login** via `SMAppService`.

## How it works

```
Claude Code hooks ──► hooks/*.sh ──► ~/.claude/claudelights-status.json ──► ClaudeLights.app ──► menu bar
   (per event)          (jq merge)        (one entry per session_id)         (fs watcher)      (traffic light)
```

1. **Hooks** (`UserPromptSubmit`, `Stop`, `Notification`) run a small shell
   script that reads the hook payload from stdin, extracts the `session_id`
   (and `cwd`), and merges **only that session's entry** into the shared JSON
   status file. Other sessions are never overwritten.
2. **The app** watches that file with a real filesystem watcher
   (`DispatchSource` on a file descriptor — not polling) and updates the menu
   bar icon. It also expires sessions that haven't updated in **2 hours**.
3. The app is a **menu-bar-only** agent (`LSUIElement`) — no Dock icon.

### Status file format

`~/.claude/claudelights-status.json` is a JSON object keyed by `session_id`:

```json
{
  "aaaaaaaa-1111-2222-3333-444444444444": {
    "state": "working",
    "session_id": "aaaaaaaa-1111-2222-3333-444444444444",
    "project": "frontend",
    "timestamp": "2026-07-01T14:46:36Z"
  }
}
```

Valid `state` values: `working`, `done`, `needs_input`.

## Requirements

- macOS 13 (Ventura) or later — required for `SMAppService` ("Start at Login").
- [`jq`](https://jqlang.github.io/jq/) for the hook scripts
  (`brew install jq`).
- **Xcode** (full, from the App Store) to build the app. The Command Line Tools
  alone are not enough to build a `.app` bundle.

## 1. Install the hooks

The hook scripts live in `hooks/` and are self-contained; they only need `jq`.

```sh
# From the repository root — make sure they're executable (they already are in git):
chmod +x hooks/*.sh
```

Wire them into Claude Code by merging `settings.snippet.json` into your
`~/.claude/settings.json`. **Replace `/ABSOLUTE/PATH/TO/claude-lights`** with the
real path to this repository (the paths are single-quoted so spaces are fine):

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "'/Users/you/claude-lights/hooks/working.sh'" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "'/Users/you/claude-lights/hooks/done.sh'" } ] }
    ],
    "Notification": [
      { "matcher": "idle_prompt|permission_prompt",
        "hooks": [ { "type": "command", "command": "'/Users/you/claude-lights/hooks/needs_input.sh'" } ] }
    ]
  }
}
```

If your `settings.json` already has a `hooks` block, merge the arrays rather than
replacing the whole object. Restart Claude Code (or start a new session) so it
picks up the hooks.

## 2. Build and run the app

Open the project in Xcode:

```sh
open ClaudeLights.xcodeproj
```

Then **Product ▸ Run** (⌘R). The traffic-light icon appears in the menu bar.

Or build from the command line (requires full Xcode selected via
`sudo xcode-select -s /Applications/Xcode.app`):

```sh
xcodebuild -project ClaudeLights.xcodeproj -scheme ClaudeLights -configuration Release build
# The built app is under the printed BUILT_PRODUCTS_DIR, e.g.:
#   ~/Library/Developer/Xcode/DerivedData/ClaudeLights-*/Build/Products/Release/ClaudeLights.app
open <path>/ClaudeLights.app
```

The project builds with ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) out of the
box, so it runs locally without an Apple Developer account. See
[Distribution](#distribution-dmg-outside-the-app-store) to sign/notarize.

### Without full Xcode (quick local build)

If you only have the Command Line Tools, you can still build a runnable app with
`swiftc`:

```sh
scripts/dev-build.sh --run
```

This produces `build/ClaudeLights.app` (ad-hoc signed) and launches it. It is
for local testing only; features that need a properly signed bundle (login item,
notification delivery) may be limited. Use the Xcode build / `release.sh` for the
real thing.

### The panel

Clicking the icon opens a popover with:

- one row per active session — colored dot, project name, state, live relative
  time; **click a row to focus its terminal window**, or hover and click ✕ to
  remove it. "Clear finished" removes all done sessions,
- a **chart** button → **Usage** (today's tokens + time per state),
- a **clock** button → recent state-transition **history**,
- a **gear** button → **Settings** (terminal app, per-state notifications, sound),
- **Start at Login**, **Check for Updates…** (with Sparkle), and **Quit**.

## 3. Manual testing (without Claude Code)

You can drive everything by piping example hook payloads into the scripts. Use a
throwaway status file so you don't touch your real one:

```sh
export CLAUDELIGHTS_STATUS_FILE="$(mktemp -d)/status.json"

# Session A starts working:
echo '{"session_id":"A","cwd":"/Users/me/projects/frontend"}' | hooks/working.sh

# Session B needs input:
echo '{"session_id":"B","cwd":"/Users/me/projects/api"}' | hooks/needs_input.sh

# Session A finishes (updates only A):
echo '{"session_id":"A","cwd":"/Users/me/projects/frontend"}' | hooks/done.sh

cat "$CLAUDELIGHTS_STATUS_FILE" | jq .
```

To watch the **app** react live, point it at the real file (the default,
`~/.claude/claudelights-status.json`) and run the same commands **without**
`CLAUDELIGHTS_STATUS_FILE`:

```sh
echo '{"session_id":"demo","cwd":"'"$PWD"'"}' | hooks/needs_input.sh   # icon -> red
echo '{"session_id":"demo","cwd":"'"$PWD"'"}' | hooks/working.sh       # icon -> yellow
echo '{"session_id":"demo","cwd":"'"$PWD"'"}' | hooks/done.sh          # icon -> green
```

The icon updates within moments — the app is watching the file, not polling it.

## Project layout

```
claude-lights/
├── ClaudeLights.xcodeproj/        # Xcode project (AppKit + SwiftUI panel, no Dock icon)
├── ClaudeLights/
│   ├── main.swift                 # Entry point (.accessory activation policy)
│   ├── AppDelegate.swift          # Wires watcher + store + model + services
│   ├── Models.swift               # SessionState / SessionStatus + severity
│   ├── StateAppearance.swift      # SessionState -> traffic-light color
│   ├── SessionStore.swift         # Parsing, worst-state, stale cleanup, transitions, removal
│   ├── SessionHistory.swift       # Persisted transition log + time-per-state
│   ├── UsageStats.swift           # Token usage aggregated from transcripts
│   ├── FileWatcher.swift          # DispatchSource file watcher (re-arms on rename)
│   ├── Preferences.swift          # UserDefaults: terminal, notifications, sound
│   ├── AppModel.swift             # ObservableObject: UI state + intents
│   ├── PanelView.swift            # SwiftUI popover: sessions, history, settings
│   ├── StatusController.swift     # NSStatusItem: colored icon + NSPopover
│   ├── TerminalLauncher.swift     # Brings the chosen terminal app to the front
│   ├── NotificationManager.swift  # UNUserNotificationCenter + attention sound
│   ├── Updater.swift              # Sparkle updater (guarded by canImport)
│   ├── LoginItem.swift            # SMAppService "Start at Login"
│   ├── Info.plist                 # LSUIElement = YES
│   ├── Assets.xcassets/           # App icon slot (unused while menu-bar-only)
│   └── Localizable.xcstrings      # String Catalog (English base)
├── hooks/
│   ├── update-status.sh           # Shared: merge/remove one session entry (jq, atomic)
│   ├── working.sh                 # UserPromptSubmit  -> working
│   ├── done.sh                    # Stop              -> done
│   ├── needs_input.sh             # Notification      -> needs_input (pauses timer)
│   ├── compacting.sh              # PreCompact        -> compacting
│   ├── resume.sh                  # PostToolUse       -> resume (working, resumes timer)
│   └── ended.sh                   # SessionEnd        -> remove entry
├── scripts/
│   ├── dev-build.sh               # Build/run a local .app with swiftc (no Xcode)
│   ├── release.sh                 # Signed + notarized, styled .dmg (needs Xcode)
│   ├── make-dmg.sh                # Styled "drag to Applications" DMG
│   ├── dmg-background.png         # DMG window background (rendered)
│   ├── dmg-background.swift       # Renderer for the background
│   └── sparkle-appcast.sh         # Sign updates + generate appcast.xml
├── docs/superpowers/specs/        # Design docs
├── settings.snippet.json          # Hook wiring to copy into ~/.claude/settings.json
└── README.md
```

## Internationalization

All UI strings go through a String Catalog (`Localizable.xcstrings`) with an
English base localization, so more languages can be added in Xcode without code
changes. Timestamps use `RelativeDateTimeFormatter` / locale-aware
`DateFormatter` — no hardcoded US formatting.

## Distribution (`.dmg`, outside the App Store)

ClaudeLights is distributed as a signed, notarized `.dmg` — **not** through the
Mac App Store (which requires App Sandbox; this app deliberately needs
unrestricted access to `~/.claude/`). Hardened Runtime is enabled, ready for
Developer ID signing and notarization.

### One-time setup
1. Full Xcode installed and selected: `sudo xcode-select -s /Applications/Xcode.app`
2. An Apple Developer Program membership with a *Developer ID Application*
   certificate in your login keychain.
3. Store notarization credentials once:
   ```sh
   xcrun notarytool store-credentials claudelights \
     --apple-id "you@example.com" --team-id "YOURTEAMID" \
     --password "app-specific-password"
   ```
4. Change `PRODUCT_BUNDLE_IDENTIFIER` (currently `studio.vanta.claudelights`) to
   your own reverse-DNS id, e.g. `com.yourdomain.claudelights`.

### Build the DMG
```sh
TEAM_ID=YOURTEAMID scripts/release.sh
```
This archives, exports with Developer ID, builds `build/ClaudeLights.dmg` with
`hdiutil`, notarizes it, and staples the ticket — using only Apple tooling.

### Auto-updates (Sparkle, via GitHub Releases)

The app is already wired for [Sparkle](https://sparkle-project.org/): the updater
lives in `Updater.swift` (guarded by `#if canImport(Sparkle)`), a
"Check for Updates…" item appears in the panel when Sparkle is linked, and the
feed keys are in `Info.plist`. To finish setup:

1. **Add the Sparkle package.** The project already references it
   (`https://github.com/sparkle-project/Sparkle`, 2.x). Open the project in Xcode
   and let it resolve packages (*File ▸ Packages ▸ Resolve Package Versions*). If
   Xcode ever complains about the reference, remove it and re-add via
   *File ▸ Add Package Dependencies…* — the code compiles either way.

2. **Signing keys.** Already generated — the public EdDSA key is set in
   `Info.plist` → `SUPublicEDKey`, and the private key lives in your login
   keychain. (To regenerate, run Sparkle's `generate_keys` and paste the new
   public key.)

3. **Feed URL.** Already configured and automatic checks enabled — the feed uses
   GitHub's "latest release asset" redirect:
   `https://github.com/vanta-studio/claude-lights/releases/latest/download/appcast.xml`.

4. **Cut a release.** Build the DMG (`TEAM_ID=… scripts/release.sh`), then sign
   the update and generate the appcast:
   ```sh
   scripts/sparkle-appcast.sh build      # signs build/ClaudeLights.dmg → build/appcast.xml
   ```

5. **Publish.** Create a GitHub Release and upload **both** `ClaudeLights.dmg`
   **and** `appcast.xml` as assets. Installed apps then update themselves from
   the latest release.

## Configuration

| Environment variable        | Purpose                                            | Default                                  |
| --------------------------- | -------------------------------------------------- | ---------------------------------------- |
| `CLAUDELIGHTS_STATUS_FILE`  | Override the status file path (used by the hooks). | `~/.claude/claudelights-status.json`     |

The 2-hour stale-session window is defined in `SessionStore.swift`
(`staleInterval`).
