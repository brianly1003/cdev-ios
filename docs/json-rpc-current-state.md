# JSON-RPC Current State

This document describes the current JSON-RPC documentation sources for
`cdev-ios`.

## Primary Specs

- `rpc-spec.json` - method catalog and schema references.
- `swagger.json` - OpenAPI-style compatibility reference.

## Runtime-Oriented Docs

- `api-migration-guide.md` - migration behavior and compatibility notes.
- `codex-agent-integration.md` - runtime routing and method usage model.
- `agent-event-routing-and-permissions.md` - event and permission control flow.

## Current Direction

- JSON-RPC over WebSocket is the primary integration path.
- Runtime routing depends on `agent_type` and selected runtime context.
- Session/watch/message flows are coordinated by runtime strategy in app code.

## Historical Plan

The December 2025 migration planning document has been archived:

- `archive/json-rpc-migration-plan-2025.md`
