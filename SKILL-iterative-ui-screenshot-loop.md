---
name: iterative-ui-screenshot-loop
description: Use when iterating on an ImGui (or similar immediate-mode) UI inside a game or plugin where you can capture screenshots of the rendered window - especially Openplanet/Trackmania AngelScript plugins - and need to push the design past "stock dev tool" toward polished and branded.
---

# Iterative UI Screenshot Loop

## Overview

Visual UI work requires visual feedback. Descriptions lie - screenshots don't. This skill packages a tight code-change -> build -> screenshot -> critique -> iterate loop, plus the failure modes and API traps that waste time in ImGui-style plugin UIs.

**Core principle:** Self-critique has a low ceiling. You normalize to your last iteration and rate everything "much better." A fresh subagent with a blunt prompt finds the issues you cannot see.

## When to Use

Trigger on any of:
- Iterating on a plugin/game UI built with ImGui or similar immediate-mode toolkit
- You have (or can write) a script that captures the window as a PNG
- Design goal is "stylish / branded / polished," not just functional
- Previous iteration felt "much better" but you haven't had an outside eye look at it
- Output looks like a generic dark-theme dev tool

Do NOT use for:
- Pure logic/backend changes with no visual surface
- UI toolkits with a live inspector/hot-reload that's already faster than screenshots

## The Loop

1. **Write down critique first.** Before the next code change, list the specific issues you're fixing. If the list is empty, get a subagent critique (see below) - don't code blindly.
2. **Make ONE focused change.** Multiple simultaneous changes muddy the next screenshot.
3. **Build, then capture.** Run the plugin build, wait ~2s for reload, then run the capture script. Confirm the PNG mtime updated before reading it.
4. **Crop to the window region.** A cropped image (e.g. 460x640) surfaces details a full-screen capture hides. Pin window position/size with `UI::Cond::Always` during iteration so crop coordinates stay valid - leave a `// TEMP (dev only)` comment adjacent so it's reverted before ship.
5. **Read the PNG and describe what you see.** Not what you intended. If describing reveals no issues, dispatch a subagent (you've hit the self-critique ceiling).
6. **Every 2-3 iterations, dispatch a subagent critique** (see next section). Mandatory at "I think this looks good" moments.
7. **Use a recurring reminder** (`/loop 4m`) when doing long UI work - drift from the goal is the default, the reminder is what keeps iteration honest.
8. **If the game crashes or build socket dies**, don't spin. Keep making LSP-verifiable changes, note the blocker, wait for the user to report the game is back.

## Subagent Critique (Non-Negotiable)

Your internal critic stalls around "polished dev tool." Break it with a fresh agent.

**Prompt template:**
> You are reviewing an ImGui plugin UI screenshot at `<path>`. Goal: stylish and attractive, not a generic dark theme. Constraints: ImGui only, no CSS, fixed palette. First, describe what you actually see in 2-3 sentences (forces observation, defeats my confirmation bias). Then give the 5-7 most impactful fixes, ranked by impact. Be ruthless. Under 300 words. No pleasantries, no preamble.

**Cadence:**
- At least one pass per major iteration.
- Two passes when pushing from "good" to "great."
- Always a pass before declaring done.

## Red Flags - Stock ImGui Tells

Scan every screenshot for these. Any hit means "not done."

| Tell | Fix |
|------|-----|
| Default magenta CollapsingHeader | `PushStyleColor(Header / HeaderHovered / HeaderActive)` with palette |
| Default blue ProgressBar | Restyle; use muted accent, not saturated |
| Flat gray titlebar | `TitleBg / TitleBgActive` styled, or hide and draw a custom header/accent line just below it |
| Bright neon accent (pure green/cyan/magenta) | Swap to muted (teal, amber, desaturated cyan) |
| Horizontal hairline separators in a narrow window | Replace with asymmetric accent: short colored segment, vertical bar, icon anchor |
| Everything one size/weight | Fake hierarchy: `UI::Font::DefaultBold` for titles, color + UPPERCASE + inserted spaces for tracking |
| Empty state with no icon | Anchor with a Font Awesome glyph (`Icons::*`) inside a rounded icon badge |
| Content clipping at the bottom of a child | Bottom-reserve on the child was hardcoded smaller than actual footer |
| Cramped "efficient" layout | Use an 8/16/24 spacing rhythm; breathing room is a style choice |
| Game background bleeding through window | Set `WindowBg` alpha to 1.0; translucency is ImGui default, not a brand choice |

## Principles

1. Screenshot every non-trivial visual change. Don't trust the description.
2. Write critique BEFORE the next code change, not after.
3. Muted > saturated for accents.
4. Symbolic anchors (icons, small-caps labels) create identity where ImGui defaults erase it.
5. Balance `PushStyleColor`/`PushStyleVar` pop counts across ALL code paths, including early returns. Crashes in styled UI are almost always imbalance.
6. When the internal critic says "much better," dispatch a subagent.
7. Reach for built-ins (`UI::Font::DefaultBold`) before custom-loading fonts; weight is a cheap hierarchy win.

## Openplanet / AngelScript API Gotchas

*(Openplanet-specific. Skip this section for other ImGui contexts.)*

**Look up bindings in this order:**
1. Local cache: `~/scrape/openplanet/root/docs/api/` (grep it, it's fast)
2. Online: https://openplanet.dev/docs/api/UI
3. Known-working call in the current repo (`Grep` for the same method)

Never guess from raw ImGui - Openplanet bindings diverge.

| Wrong | Right |
|-------|-------|
| `UI::CalcTextSize(s)` | `UI::MeasureString(s)` returns `vec2` |
| `UI::BulletText("x")` | `UI::Text("  - x")` or custom chevron |
| `UI::GetCursorPosX()` / `UI::GetCursorPosY()` | `UI::GetCursorPos().x` / `.y` |
| `dl.AddRectFilled(x1, y1, x2, y2, col)` (ImGui corner-corner) | `dl.AddRectFilled(vec4(x, y, w, h), col, rounding)` - the vec4 is pos+size, NOT corner-corner |
| `dl.AddRect(rect, col, rounding, 0, thickness)` (5 args) | `dl.AddRect(rect, col, rounding, thickness)` - 4 args |
| `UI::LoadFont(...)` just to get bold/mono text | `UI::PushFont(UI::Font::DefaultBold)` or `UI::Font::DefaultMono` - built-in, no load, no null-check |
| Custom unicode glyphs like diamonds or arrows | May render as `?`; use `Icons::*` (Font Awesome) anchors |
| Assuming `UI::StyleVar::ChildBorderSize` is missing | It exists, use it |

**Fonts:** Default/DefaultBold/DefaultMono are instant built-ins. Only reach for `UI::LoadFont("DroidSans-Bold.ttf", size, -1, -1, true, true, true)` when you need a **custom size**. Custom-loaded fonts must be loaded via `startnew(LoadFonts)` in `Main()` and null-checked before `UI::PushFont` (coroutine may not have completed on first render).

**Icons:** `Icons::ExclamationTriangle`, `Icons::Check`, `Icons::Cogs`, `Icons::Play`, etc. Grep the repo for `Icons::` for the available set.

## Visual Layout Assertions

When a layout calculation is wrong and the screenshot disagrees with the math, stop guessing — draw your assumed coordinates onto the screen as colored rectangles via the drawlist, rebuild, and screenshot. The rectangles are the assertion: if they don't land where the math predicted, the coordinate system assumption was wrong (content-origin vs window-origin, padding, scrollbar inset, scroll offset).

```angelscript
auto dl = UI::GetWindowDrawList();
// center marker - expected text center point
dl.AddRectFilled(vec4(centerX - 2, y, 4, 10), vec4(1,0,1,1));
// text bounds - expected text bounding box
dl.AddRect(vec4(textX, y, textW, textH), vec4(0,1,0,1), 0, 1);
```

Magenta/green are loud on a dark theme. Remove after debugging. This is faster than one more round of "try a different formula and reload."

## Common Mistakes

- **Skipping the screenshot** because "the change was small." Small changes interact with existing styling in surprising ways. Screenshot anyway.
- **Reading a stale screenshot.** If the capture script didn't actually fire after the build, you're critiquing the old UI. Check the PNG mtime.
- **Self-rating "much better"** across 5 iterations without a subagent pass. Normalization is real.
- **Unbalanced push/pop** after an early return - crash on next render. Count pushes/pops per code path, including the `not in editor` fallback.
- **Leaving `UI::Cond::Always` pinning in the shipped code.** Tag pin code with `// TEMP (dev only)` immediately when you add it.
- **Batching visual changes.** If the screenshot looks worse, you don't know which change did it.
- **Claiming a visible change without verifying the screenshot updated.** If a user says "the screenshot didn't update," they mean you trusted the code diff over the actual render. Always re-read the PNG.

## Quick Reference - Critique Prompt

```
Review ImGui plugin UI at <path>. Goal: stylish, branded, not generic
dark theme. Constraints: ImGui, no CSS, fixed palette.
1. Describe what you see in 2-3 sentences.
2. 5-7 most impactful fixes, ranked by impact.
Ruthless. <300 words. No pleasantries.
```
