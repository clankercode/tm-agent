# Changelog

All notable changes to **tm-agent** are documented here.

Versions follow `info.toml` `[meta] version`.

## [Unreleased]

### Fixed

- Crash when scrolling the chat history up: the virtual-scroll cull path advanced the cursor with a bare `SetCursorPos`, tripping ImGui's `ErrorCheckUsingSetCursorPosToExtendParentBoundaries` assertion at `EndChild` whenever the newest messages were off-screen. The cull advance now submits a `Dummy` sized to the cached row height (ChatUI.as `DrawMessages`).

## [0.2.0] - 2026-08-12

### Changed

- Hardened agent cancellation, tool polling, provider errors, and busy-message admission.
- Preserved native Anthropic tool history and OpenAI Responses reasoning state.
- Redesigned the in-game chat with richer conversation controls, tool activity, status, and context-pressure presentation.
- Added agent-driven camera focus, UI capture and analysis utilities, inventory tools, runtime statistics, context compaction, and release validation.

### Fixed

- Prevented cancelled and stale asynchronous runs from mutating a new conversation.
- Recovered cleanly from provider and tool exceptions without leaving the agent busy.
- Corrected nested MCP result semantics and provider-native tool history conversion.
- Prevented malformed tool calls and unknown tool names from corrupting subsequent model turns.

## [0.1.0]

Initial development version.