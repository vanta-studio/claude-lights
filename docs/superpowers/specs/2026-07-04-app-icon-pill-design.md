# App icon redesign: menu-bar pill motif

**Date:** 2026-07-04
**Status:** Approved (variant B chosen from three rendered drafts)

## Goal

Replace the v1.0 app icon (spark + three orbs + tick marks), which reads as
dated, with a modern icon built on the app's own visual language: the
menu-bar pill with three status lights.

## Design (chosen: variant B)

- macOS squircle (824 pt on the 1024 grid, radius 185, drop shadow), deep
  navy vertical gradient — keeps brand continuity with v1.0's dark ground.
- Centered horizontal glass pill (620×250 pt): translucent white gradient
  fill, light rim stroke, top inner highlight, soft grounding shadow, faint
  radial light source behind it.
- Three status lights inside — green, yellow, red (traffic-light order).
  The yellow light blooms strongly ("Claude is working right now"); green
  and red are dimmed to ~55 % with a small glow.

Rejected alternatives: A (all three lights lit evenly — quieter but tells
no story), C (graphite body with dark inset window — hardware look).

## Implementation

- `scripts/make-app-icon.swift` renders the icon at 1024 px with
  AppKit/CoreGraphics and downsamples to every size in
  `ClaudeLights/Assets.xcassets/AppIcon.appiconset/` (16–1024,
  filenames per `Contents.json`). Regenerating the icon is one command:
  `swift scripts/make-app-icon.swift`.
- No code changes; `Contents.json` stays as is. The menu-bar template
  icon is unaffected.

## Verification

- All seven PNGs regenerated, correct pixel sizes.
- Dev build (`scripts/dev-build.sh`) shows the new icon on the app bundle.
- Legibility spot-check at 16/32 px (dots still read as three colors).
