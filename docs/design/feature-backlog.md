# Feature Backlog (Active)

This document consolidates older design drafts into an actionable, current
backlog aligned with the present architecture.

## Constraints

- iOS app operates as a client to `cdev-agent`.
- File system and command execution occur on agent side.
- Session lifecycle and permission control are server-driven.

## Backlog Themes

## 1) Session Operations

- Multi-session overview with clearer active-state indicators
- Faster tab/window handoff with context continuity
- Local bookmarks for important conversation checkpoints

## 2) Permission and Interaction Flow

- Improve pending interaction discoverability when not on terminal tab
- Expand diagnostics around unresolved/resolved-elsewhere events
- Safer bulk approval controls with explicit scope visibility

## 3) Mobile Productivity

- Prompt templates and reusable quick actions
- Better local search/filter over cached session content
- Export/share selected session artifacts

## 4) Reliability and Debuggability

- Runtime/session mismatch diagnostics surfaced in debug tools
- Structured trace package export for incident triage
- Recovery tooling for reconnect and state resync validation

## Deferred / Exploratory

- Deeper offline behavior beyond read-only cache
- Expanded wearable/widget surfaces beyond status visibility
- Broader multi-agent UX abstractions after runtime parity matures

## Source Consolidation Note

This file supersedes prior draft transcripts that were removed during
documentation cleanup.
