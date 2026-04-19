# TM Agent Handoff

## Current State

UI improvement iteration is in progress. Core functionality is complete; visual design is being iteratively refined.

- `tm-agent` build/test paths are green.
- `tm-mcptm` exposes inventory summary/search tools.
- `tm-agent` wires those tools into the assembled tool list and unit tests.
- Dynamic editor state snapshot is injected as a system message on every LLM call.
- UI stats redesigned with visual progress bar and color-coded token tracking.
- Output/input token counts tracked from LLM API responses.
- S_ShowWindow persistent setting controls window visibility.
- Window uses NoCollapse flag (not NoTitleBar) for window identification.

## UI Issues Identified (Pending Fixes)

Resolved in current pass:
- Idle placeholder/onboarding text added (welcome + example prompts)
- Stats panel now always visible at top (progress bar + Ctx/Rem/Msgs); full token breakdown collapsed under "Token details"
- Default spawn position moved to (120, 120) away from editor toolbar
- Default window size bumped to 440x620 so all sections fit
- Input height increased to 100px, Send button full-height
- Redundant Clear History button removed from Settings (header Clear remains)
- Provider/model surfaced inline in header

Still open:
- No keyboard shortcut hints (e.g., Ctrl+Enter to send)

## Scripts

- `capture_ui.sh` — Screenshot using xdotool + ImageMagick (filters for exact "Trackmania" window name)
- `analyze_ui.sh` — Uses `ccc cc +0 :opus ..text` to analyze screenshot

## Commit Pointers

- `tm-agent`: `0d2e365` - `Redesign UI stats with progress bar, color-coded token tracking, and output token stats`
- `tm-agent`: `363aa51` - `Add dynamic editor state snapshot and improved system prompt guidance`
- `tm-agent`: `89b7680` - `Wire inventory tools and context stats`
- `tm-aiapi`: `24c49ba` - `Add usage token tracking to Anthropic and OpenAI API responses`
- `tm-mcptm`: `55bc0da` - `Add inventory MCP search tools`

## Verified Commands

- `openplanet-lsp check .`
- `./build.sh unittest`
- `./build.sh dev`

## Important Files

- `src/ChatUI.as`
  - Visual progress bar for context budget (green/yellow/red color coding)
  - Color-coded token categories (Ctx, Rem, In, Out, Total Out, Sum, Hist, Tools, Msgs, Compact)
  - Provider/model/effort settings UI
  - Header with turn counter, status, and Clear button
- `src/LlmHistory.as`
  - Normalized history representation
  - Deterministic compaction
  - Shared context stats helper
  - Injects editor state snapshot as a system message in `GetMessagesForLlm`
  - Enhanced `BASE_SYSTEM_PROMPT` with early state-querying and inventory search rules
- `src/AgentLoop.as`
  - Captures usage token stats from LLM responses and passes to AgentUI
- `src/ToolAssembler.as`
  - Includes inventory tools in the assembled tool list
  - `GetEditorStateSnapshot()` builds text snapshot of map, cursor, placement mode, inventory state
- `src/Settings.as`
  - `S_ShowWindow` persistent setting
- `src/UnitTests.as`
  - Covers defaults, tool list sync, context stats, compaction, and inventory tool presence
- `../tm-mcptm/src/McpTM_Tools.as`
  - Implements `GetInventorySummary` and `FindInventory`
- `../tm-aiapi/src/AiApi_Net.as`
  - Returns `usage` object with `input_tokens`, `output_tokens`, `total_tokens` from API responses

## Goal File

- `.goal-loops/active-goal.md` — Primary goal is UI improvement with visual progress bars and token tracking

## Next Likely Work

1. Keyboard shortcut for Send (Ctrl+Enter) + hint label
2. Wire the future MCP surfaces listed below

Future MCP surfaces doc-reviewed but not yet wired:
- `RequestEnterPlayground`
- `RequestLeavePlayground`
- `ClearMapMetadata`
- `ValidationStatus`
- `Mode`
- `Users`
- `Players`

## Constraints To Preserve

- Keep the unittest harness free of MiniMax API calls
- Treat token counts and context size as estimates unless the API gives actual usage
- Keep compaction from splitting tool-call and tool-result pairs
- Do not revert unrelated user changes if the tree is dirty again

## Suggested Resume Path

1. Read `.goal-loops/active-goal.md` for current iteration status
2. Run `./capture_ui.sh && ./analyze_ui.sh` to see current UI state
3. Implement UI fixes identified above
4. Re-run `openplanet-lsp check .`, `./build.sh unittest`, and `./build.sh dev`

Generation date: Mon 20 Apr 2026 02:20:00 AEST
