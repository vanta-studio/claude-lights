# Background Tasks in Session State — Design

**Date:** 2026-07-04
**Status:** Approved (brainstormed with Daniel)

## Context & Goal

When a Claude Code session has a background task still running (a background
subagent or a `run_in_background` Bash task), the main loop can end its turn
and the `idle_prompt` notification fires anyway. ClaudeLights then shows
`needs_input` even though the session will resume on its own — the light
misleads for however long the background task keeps running (it can be
minutes). Goal: the "Open Sessions" panel and the desktop notification should
say what is still running, so a waiting-but-busy session is not mistaken for
one that is actually blocked on the user.

## Spike findings (Claude Code 2.1.201)

- The `Stop` hook payload contains an **undocumented** `background_tasks`
  array, one entry per still-running task:
  `{id, type: "subagent"|"shell", status: "running", description,
  agent_type?, command?}`. It covers both background subagents and
  background Bash tasks. An empty array means nothing is running.
- The `Notification` payload does **not** carry the field (not verified for
  `idle_prompt`, which can't fire headless — treated as absent defensively).
  That is fine: the `Stop` that precedes an `idle_prompt` has just written
  the current list.
- When a background task completes, Claude Code re-invokes the main agent
  via `UserPromptSubmit` (`<task-notification>` prompt), so the existing
  `working` transition already flips the light back on its own.
- `SubagentStart`/`SubagentStop` hooks exist and fire, but are not needed:
  the `Stop` payload alone is sufficient, so **no settings.json hook changes
  are required** — only the helper binary changes.

## Behavior

### 1. Hook helper (`ClaudeLightsHook/main.swift`)
- When the incoming payload contains `background_tasks`, store a compact
  form in the session entry of the status file: the count and, per task, a
  short display description (subagents: `description`; shell tasks:
  `description` falling back to `command`).
- When the payload lacks the field (e.g. `Notification` → `needs_input`),
  **preserve** the last stored value — the preceding `Stop` wrote it fresh.
  A payload with an empty array clears it.
- Bump `helperVersion` so the app's self-heal replaces the installed binary
  automatically on next launch.

### 2. Panel ("Open Sessions")
- Sessions in `needs_input` or `done` with a non-empty background-task list
  show an extra line, e.g. "⏳ 1 task still running: Sleep then reply done".
  With multiple tasks the line shows the count and the first task's
  description: "⏳ 3 tasks still running: Sleep then reply done, …".
- Sessions in `working`/`compacting` show nothing extra — the session is
  visibly active anyway.

### 3. Desktop notification
- The `needs_input` (and `done`) notification body gets a suffix when tasks
  are still running, e.g. "… — 1 background task still running". No
  suppression in v1: the session may genuinely need input at the same time
  (e.g. a permission prompt while an agent runs).

## Error handling / limits

- `background_tasks` is undocumented and may change or disappear in any
  Claude Code release. The helper parses it defensively: missing, malformed,
  or unexpected shapes are ignored and everything behaves exactly as today.
- Stale data is possible (e.g. a task list written at `Stop` is not updated
  while the turn is idle). Accepted: the line is a hint, not a state; it
  self-corrects at the next `Stop` and disappears when the session resumes.
- The app's JSON decoding must tolerate entries without the new field
  (old helper versions, hand-written files).

## Testing

- Helper: extend the existing installer/helper tests (`tests/`) with
  payloads containing `background_tasks` (present, empty, absent, malformed)
  and assert the stored session entry.
- App: unit-test the SessionStatus decoding with and without the field, and
  the display-string formatting (0/1/n tasks).
- Manual: re-run the spike scenario (background subagent + background Bash)
  against a dev build and watch panel + notification.
