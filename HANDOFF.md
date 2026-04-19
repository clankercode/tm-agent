# TM Agent Handoff

## Current State

Inventory, compaction, UI stats redesign, and improved system prompt work is complete and committed.

- `tm-agent` build/test paths are green.
- `tm-mcptm` exposes inventory summary/search tools.
- `tm-agent` wires those tools into the assembled tool list and unit tests.
- Dynamic editor state snapshot is injected as a system message on every LLM call.
- UI stats redesigned with visual progress bar and color-coded token tracking.
- Output/input token counts tracked from LLM API responses.
- The tracked repos are clean at the time of this handoff.

## Commit Pointers

- `tm-agent`: `0d2e365` - `Redesign UI stats with progress bar, color-coded token tracking, and output token stats`
- `tm-agent`: `363aa51` - `Add dynamic editor state snapshot and improved system prompt guidance`
- `tm-agent`: `89b7680` - `Wire inventory tools and context stats`
- `tm-aiapi`: `24c49ba` - `Add usage token tracking to Anthropic and OpenAI API responses`
- `tm-mcptm`: `55bc0da` - `Add inventory MCP search tools`

## Verified Commands

These passed during the last working session:

- `openplanet-lsp check .`
- `./build.sh unittest`
- `./build.sh dev`

## Important Files

- `src/LlmHistory.as`
  - Normalized history representation.
  - Deterministic compaction.
  - Shared context stats helper.
  - Injects editor state snapshot as a system message in `GetMessagesForLlm`.
  - Enhanced `BASE_SYSTEM_PROMPT` with early state-querying and inventory search rules.
- `src/ChatUI.as`
  - Redesigned stats strip with visual progress bar for context budget.
  - Color-coded token categories (Ctx, Rem, In, Out, Total Out, Sum, Hist, Tools, Msgs, Compact).
  - Provider/model/effort settings UI.
- `src/AgentLoop.as`
  - Captures usage token stats from LLM responses and passes to AgentUI.
- `src/ToolAssembler.as`
  - Includes inventory tools in the assembled tool list.
  - New `GetEditorStateSnapshot()` builds a text snapshot of map, cursor, placement mode, and inventory state.
- `src/UnitTests.as`
  - Covers defaults, tool list sync, context stats, compaction, and inventory tool presence.
- `../tm-mcptm/src/McpTM_Tools.as`
  - Implements `GetInventorySummary` and `FindInventory`.
- `../tm-aiapi/src/AiApi_Net.as`
  - Now returns `usage` object with `input_tokens`, `output_tokens`, `total_tokens` from API responses.

## Goal File

The persistent goal file is current:

- `.goal-loops/active-goal.md`

It currently says the active implementation work is complete.

## Next Likely Work

Future MCP surfaces doc-reviewed but not yet wired:

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
2. Inspect `src/LlmHistory.as` and `src/ChatUI.as` if changing prompt behavior.
3. If extending MCP coverage, start in `../tm-mcptm/src/McpTM_Tools.as` and mirror the tool wiring in `src/ToolAssembler.as`.
4. Re-run `openplanet-lsp check .`, `./build.sh unittest`, and `./build.sh dev`.

Generation date: Mon 20 Apr 2026 01:21:16 AEST
