# Changelog

All notable changes to **tm-agent** are documented here.

Versions follow `info.toml` `[meta] version`.

## [Unreleased]

### Added

- Follow camera for the working agent: while a run is in flight, every positional tool activity retargets the editor camera so you can watch the agent build. Four modes selectable in the chat header (persisted): `swing` (default — smooth per-frame follow: position eases to the target while the camera slowly orbits and holds a gentle down-tilt), `cinematic` (lazier ease, wider orbit, distance breathing), `steps` (one E++ animated hop per retarget, paced by a deadband), and `off` (manual control). The orbital camera's angles+distance imply the camera position (the sphere model), so retargets combine rotation and movement without jerk. Between runs the camera is fully manual again. Supersedes the old unconditional snap-focus on placement tools.
- "View" eye button on tool-call chips for tools that act on a position (PlaceBlock, PlaceItem, FocusCamera, …): clicking animates the editor camera to that spot (E++ `SetCamAnimationGoTo` via the new `tm-mcp-pack-epp` dependency; falls back to the core `SetEditorCamera` tool when the pack is absent). Core grid tools convert block-grid coordinates to map meters; pack tools use world meters. A failed focus surfaces a short system message in the chat.
- JSONL session persistence: every user/assistant message, tool call/result, LLM exchange (usage + raw response), and error is appended to `PluginStorage/tm-agent/sessions/session-<timestamp>.jsonl`. Sessions rotate on New/clear; records are written before the UI updates so a crash cannot lose what the agent sent or received.
- Driver (file-IPC) ops for verification: `call_tool`/`poll_async` (invoke any MCP tool, incl. suspending ones), `get_cam` (camera state), `focus_click` (simulate an eye-button click), `set_follow_mode`/`get_follow_state`/`cam_activity_sim`/`set_agent_busy` (follow-cam pipeline).

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