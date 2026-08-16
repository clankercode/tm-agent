// StartupSuggestion.as — map-aware TRY-list starter. Fills the composer
// with a scenery-sampler prompt; the user reviews and sends.

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

    // Featured TRY-list label. Icon lives here so the chip can draw it.
    string ButtonLabel(bool mapHasRoute) {
        return mapHasRoute
            ? Icons::Magic + " Scenery: design & place around your route"
            : Icons::Magic + " Scenery: design & place sample islands";
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
}
