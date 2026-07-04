# needs_input coverage — Design

**Date:** 2026-07-04
**Status:** Implemented (user bug report: light stays yellow during a
question in a VS Code terminal)

## Root cause

`needs_input` was wired ONLY to the `Notification` hook with matcher
`idle_prompt|permission_prompt`. That misses two documented notification
types that also mean "waiting for the user":

- `agent_needs_input` — background-agent sessions (agents sidebar) that
  need input. Subagents run in the background by default since ~2.1.19x,
  so this is common — and the most plausible reproduction of the report.
- `elicitation_dialog` — an MCP server asking the user something.

## Spike findings (Claude Code 2.1.201, interactive pty sessions)

- A pending `AskUserQuestion` fires `UserPromptSubmit → PreToolUse
  (AskUserQuestion) → Notification(notification_type: permission_prompt)`.
  On current versions the old wiring therefore DID work for plain
  questions in the main session — the terminal (VS Code or not) is
  irrelevant, hooks fire CLI-side.
- `idle_prompt` did NOT fire during 90 s of a pending question — there is
  no idle safety net for missed notifications.
- 2.1.200 changed AskUserQuestion behavior (no more auto-continue);
  which Notification (if any) accompanies a pending question is version-
  dependent. `PreToolUse` with matcher `AskUserQuestion` fires on all
  versions, before the dialog renders (verified in isolation: a
  PreToolUse-only wiring wrote `needs_input`).

## Fix

Two additions to the wiring (installer, snippet, README, legacy comment):

1. `PreToolUse` matcher `AskUserQuestion` → `needs_input`. The user's
   answer fires `PostToolUse` → `resume` like any other tool.
2. Notification matcher extended to
   `permission_prompt|agent_needs_input|elicitation_dialog`. (`idle_prompt`
   was removed in parallel by a01d058 — the idle nudge is not a blocker
   and was turning every finished-but-open session red; both changes
   merged deliberately.)

Existing v1.0/v1.1 installs: the added event makes `detectStatus()` report
`needsRepair(.partialWiring)`; the existing Repair Hooks action rewrites
all our entries including the new matcher (installer test 13 covers the
upgrade; deliberately NO silent auto-rewrite of settings.json — a missing
event can also be a user's deliberate deletion).

## Not covered / accepted

- `agent_needs_input` end-to-end reproduction (needs a background agent
  that blocks on input) — matcher change is doc-backed, low risk.
- A question inside a background subagent marks the whole session
  `needs_input` via PreToolUse; arguably correct, and the
  `agent_needs_input` notification describes the same situation.
