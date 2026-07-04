# Donation Flow — Design

**Date:** 2026-07-03
**Status:** Approved (brainstormed with Daniel)

## Context & Goal

ClaudeLights ships free (donationware) for now; a paid one-time-purchase
version via a Merchant of Record comes later. Until then, donations via
Stripe Payment Links are the only revenue channel. Goal: maximize the number
of donations in the $5–$25 range (floor $2 via the custom-amount link), while
staying respectful enough that the later switch to a paid model doesn't burn
goodwill. A subscription was considered and rejected: no recurring value or
server cost to justify it, and the developer audience would rather rebuild
the tool than rent it.

## Behavior

### 1. Welcome screen (support card)
*(Updated 2026-07-04: the original caption-style "soft seed" line was too
easy to miss — the app lives on voluntary support, so the welcome screen
now makes the ask visible.)*

A tinted card (pink fill + border) between the setup steps and the footer:

> ☕ **ClaudeLights is free and made by one person.**
> It runs entirely on voluntary support — if it saves you time, consider
> chipping in.
> [ Support ClaudeLights ♥ ] *(full-width, borderedProminent, pink)*

The button opens the donation window. Still no amount buttons in the
welcome screen — the anchored tiers stay in the donation window.

### 2. Donation window (the real ask)
A small window (~380 pt wide) that auto-opens **once at app launch after 25
completed sessions** (launch is an attention moment; the user is not
mid-work). Content:

- Header: app icon + "Enjoying ClaudeLights?"
- Value proof: "ClaudeLights has watched **N sessions** finish for you."
  (N = persisted count of transitions into the `done` state)
- Amount tiers: `$5` · `$10` (visually emphasized, badged "Popular") · `$25`,
  below them a subtle "Custom amount" link. Each opens its Stripe Payment
  Link in the browser.
- Footer (auto-shown context only): "Maybe later" — re-ask once after 50
  further completed sessions, then never again automatically — and
  "Don't ask again".

Anchoring rationale: no visible $2 tier (average would anchor low); $25
exists mainly as a decoy to make $10 feel moderate; emphasized middle tier
anchors the average near $10.

### 3. Always reachable
Panel footer button "Support ClaudeLights ♥" (above Quit) opens the same
window without the later/never footer. After the user clicks any tier, the
label becomes "Thank you ♥ — Support again" and the window never auto-opens
again. (No backend, so a tier click is optimistically treated as a donation.)

## Technical Design

New files (each added to project.pbxproj; dev-build picks them up via glob):

- **`ClaudeLights/DonationPrompt.swift`** (Foundation only, testable):
  - `DonationLinks` — four Stripe Payment Link URL constants (5/10/25/custom).
    Ship with `REPLACE_…` placeholder slugs; `DonationLinks.isConfigured`
    is false until real links are pasted in, and every donation entry point
    (welcome line, panel button, auto-prompt) stays hidden while unconfigured.
  - `DonationState` — value struct: `completedSessions`, `autoShowCount`,
    `lastShownAtCount`, `dismissedForever`, `donated`.
  - `DonationPromptRule.shouldAutoShow(state:)` — pure function.
    Thresholds: first ask at ≥ 25 completed sessions; after "Maybe later"
    one re-ask at ≥ lastShownAtCount + 50; hard cap of 2 auto-shows;
    never when `dismissedForever` or `donated`.
  - `DonationStateStore` — persists `DonationState` in `UserDefaults`
    (injectable suite for tests).
- **`ClaudeLights/DonationView.swift`** — SwiftUI window content as above.
- **`ClaudeLights/DonationController.swift`** — owns the NSWindow
  (OnboardingController pattern), the state store, tier-click handling
  (open URL + mark donated), and `autoShowIfEligible()`.

Wiring:

- `AppDelegate.handleTransitions` calls
  `donations.recordCompletions(transitions)` (counts `.done` transitions).
- `AppDelegate.applicationDidFinishLaunching` calls
  `donations.autoShowIfEligible()` when onboarding is not being shown.
- `AppModel` gains `donationAvailable`, `hasDonated`, `showDonationHandler`
  — same handler pattern as the other intents.

## Stripe setup (manual, outside the app)

Create four Payment Links in the Stripe dashboard: fixed $5, $10, $25 and
one "customer chooses price" link with a $2 minimum. Paste the URLs into
`DonationLinks`. Until then the feature is invisible.

## Testing

`tests/donation/main.swift` + `scripts/test-donation.sh` (test-focus.sh
pattern): pure-rule cases (below/at threshold, re-ask window, 2-show cap,
dismissed-forever, donated) and a `DonationStateStore` round-trip against a
scratch `UserDefaults` suite.

## Out of scope

- Payment verification (no backend; tier click ≈ donation).
- Subscriptions (rejected — see Context).
- License keys / paid version (later, separate project).
