// StartupSuggestion.as — map-aware "try this" row above the composer when the
// chat is fresh (empty history, idle). Fills the composer with a starter
// prompt; the user reviews and sends — nothing auto-runs.

namespace StartupSuggestion {

    bool g_Dismissed = false;

    // Show only on a fresh chat: no messages yet, agent idle, not already
    // dismissed this session.
    bool ShouldShow() {
        if (g_Dismissed) return false;
        if (AgentUI::g_Messages.Length > 0) return false;
        if (FollowCam::g_AgentBusy) return false;
        return true;
    }

    // Concise try-button label, adapted to what the map already has.
    string ButtonLabel(bool mapHasRoute) {
        return mapHasRoute
            ? Icons::Magic + " Scenery around your route"
            : Icons::Magic + " Scenery sampler";
    }

    // The long-form starter prompt dropped into the composer.
    string ComposerPrompt(bool mapHasRoute) {
        string head = mapHasRoute
            ? "This map already has a route. Create scenery that fits it."
            : "This map is mostly empty. Let's find a scenery style worth committing to.";
        return head + "\n\n"
            + "Plan:\n"
            + "1. Build 4-8 small sample scenery islands spread across open areas of the map"
            + " (not on the route). Give each a distinct style/mood (e.g. forest, cliffs,"
            + " industrial ruins, alien organic, minimalist zen).\n"
            + "2. Take a focused screenshot of each island (TakeScreenshot with focus +"
            + " distance), then show me the shots and a one-line description per island.\n"
            + "3. I'll pick one (or a mix); then either iterate that one island further OR"
            + " develop the style into the surrounding base terrain.\n"
            + "4. Once the look is right, build/extend the driving route on top of it.\n"
            + "While building, prefer REUSING existing macroblocks (check the inventory"
            + " first), and CREATE new custom macroblocks for repeated creative elements"
            + " instead of placing the same blocks one by one everywhere. Use combinations"
            + " creatively - overlap, mirror, and mix macroblocks for richer results.\n"
            + "After the samples, call tm-agent.OfferActions with one group per island "
            + "(view position + continuePrompt) so I can look at or continue a group with a click.\n"
            + "Start with step 1 now; keep each island under ~25 blocks so the samples"
            + " stay quick.";
    }

    void Draw(bool mapHasRoute) {
        if (!ShouldShow()) return;
        vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);
        auto dl = UI::GetWindowDrawList();

        UI::Dummy(vec2(0, 4));
        vec2 rowPos = UI::GetCursorPos();
        float w = UI::GetWindowContentRegionWidth();
        float rowH = 30;

        // Tight pill row: label + try button, right-aligned like the follow pills.
        string labelText = "Try:";
        vec2 labelSz = UI::MeasureString(labelText);
        string btnLabel = ButtonLabel(mapHasRoute);
        vec2 btnSz = UI::MeasureString(btnLabel) + vec2(18, 8);

        UI::Dummy(vec2(w, rowH));
        vec2 abs = UI::GetWindowPos() + rowPos - vec2(UI::GetScrollX(), UI::GetScrollY());
        float labelX = w - labelSz.x - btnSz.x - 14 - 8;
        dl.AddText(vec2(abs.x + labelX, abs.y + (rowH - labelSz.y) * 0.5), vec4(0.40, 0.44, 0.50, 1.0), labelText);

        // Try button: manual hit-rect (full-height Dummy hover region, same
        // proven pattern as the follow pills).
        vec2 btnPos = vec2(abs.x + w - btnSz.x - 4, abs.y + (rowH - btnSz.y) * 0.5);
        UI::SetCursorPos(rowPos + vec2(w - btnSz.x - 4, 0));
        UI::Dummy(btnSz);
        vec4 btnRect = vec4(btnPos.x, btnPos.y, btnSz.x, btnSz.y);
        dl.AddRectFilled(btnRect, vec4(accent.x, accent.y, accent.z, 0.16), 4);
        dl.AddRect(btnRect, vec4(accent.x, accent.y, accent.z, 0.55), 4);
        dl.AddText(vec2(btnRect.x + (btnSz.x - UI::MeasureString(btnLabel).x) * 0.5, btnRect.y + 4), vec4(0.85, 0.97, 1.00, 1.0), btnLabel);
        UI::SetCursorPos(rowPos + vec2(0, rowH));
        if (UI::IsItemHovered() && UI::IsMouseClicked(UI::MouseButton::Left)) {
            AgentUI::g_InputText = ComposerPrompt(mapHasRoute);
            g_Dismissed = true;
        }
    }
}
