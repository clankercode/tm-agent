# TM Agent Handoff

## Current State

The requested inventory, compaction, and UI stats work is complete and committed.

- `tm-agent` build/test paths are green.
- `tm-mcptm` now exposes inventory summary/search tools.
- `tm-agent` wires those tools into the assembled tool list and unit tests.
- The tracked repos are clean at the time of this handoff.

## Commit Pointers

- `tm-agent`: `89b7680` - `Wire inventory tools and context stats`
- `tm-mcptm`: `55bc0da` - `Add inventory MCP search tools`
- `tm-aiapi`: `c40a5a1` - `Add build script and export module, fix JSON API usage`

## Verified Commands

These passed during the last working session:

- `openplanet-lsp check .`
- `./build.sh unittest`
- `./build.sh dev`

The `./build.sh unittest` run reported `Tests run: 6` and `Tests passed: 6`.

## Important Files

- `src/LlmHistory.as`
  - Normalized history representation.
  - Deterministic compaction.
  - Shared context stats helper.
- `src/ChatUI.as`
  - Live context/token stats strip.
  - Provider/model/effort settings UI.
- `src/AgentLoop.as`
  - Uses the shared history/compaction path.
  - Passes OpenAI reasoning effort through.
- `src/ToolAssembler.as`
  - Includes inventory tools in the assembled tool list.
- `src/UnitTests.as`
  - Covers defaults, tool list sync, context stats, compaction, and inventory tool presence.
- `../tm-mcptm/src/McpTM_Tools.as`
  - Implements `GetInventorySummary` and `FindInventory`.

## Goal File

The persistent goal file is current:

- `.goal-loops/active-goal.md`

It currently says the active implementation work is complete and the remaining items are only future MCP follow-ups.

## Next Likely Work

If the next agent is continuing product work, the most natural follow-up is to improve the default system prompt with better map guidance.

Possible prompt topics:

- Current map name and size.
- Current mode and placement mode.
- Cursor position and selected block/item.
- Whether inventory is available, plus the current inventory path and selected node.
- A short rule telling the model to use the browse/search tools before guessing item or block paths.

There are also doc-reviewed future MCP surfaces worth considering later:

- `RequestEnterPlayground`
- `RequestLeavePlayground`
- `ClearMapMetadata`
- `ValidationStatus`
- `Mode`
- `Users`
- `Players`

## Constraints To Preserve

- Keep the unittest harness free of MiniMax API calls.
- Treat token counts and context size as estimates unless the API gives actual usage.
- Keep compaction from splitting tool-call and tool-result pairs.
- Do not revert unrelated user changes if the tree is dirty again.

## Suggested Resume Path

1. Reread `.goal-loops/active-goal.md`.
2. Inspect `src/LlmHistory.as` and `src/ChatUI.as` if you are changing prompt behavior.
3. If you are extending MCP coverage, start in `../tm-mcptm/src/McpTM_Tools.as` and mirror the tool wiring in `src/ToolAssembler.as`.
4. Re-run `openplanet-lsp check .`, `./build.sh unittest`, and `./build.sh dev`.

