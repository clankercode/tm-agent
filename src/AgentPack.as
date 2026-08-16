// AgentPack.as — tm-agent's own TmMcp tool pack (AskUser + OfferActions).
// Tools return immediately; the UI card is the side effect.

namespace AgentPack {

    string g_PackId = "";

    Json::Value@ Ok(Json::Value@ output) {
        Json::Value r = Json::Object();
        r["success"] = true;
        r["output"] = output;
        return r;
    }

    Json::Value@ Err(const string &in msg, const string &in code) {
        Json::Value r = Json::Object();
        r["success"] = false;
        r["error"] = msg;
        r["code"] = code;
        return r;
    }

    Json::Value@ Dispatch(const string &in name, Json::Value &in input) {
        if (name == "AskUser") return AskUser(input);
        if (name == "OfferActions") return OfferActions(input);
        return Err("unknown pack tool: " + name, "unknown_tool");
    }

    Json::Value@ AskUser(Json::Value@ input) {
        if (input is null || !input.HasKey("question") || string(input["question"]).Length == 0) {
            return Err("AskUser requires question", "bad_input");
        }
        Interactive::Card@ card = Interactive::OfferSurvey(input);
        AgentUI::AddInteractive(card.id, card.survey.question);
        auto o = Json::Object();
        o["status"] = "displayed";
        o["surveyId"] = card.id;
        o["optionCount"] = int(card.survey.options.Length);
        o["multiSelect"] = card.survey.multiSelect;
        return Ok(o);
    }

    Json::Value@ OfferActions(Json::Value@ input) {
        Interactive::Card@ card = Interactive::OfferActions(input);
        string title = card.actionsTitle.Length > 0 ? card.actionsTitle : "Actions";
        AgentUI::AddInteractive(card.id, title);
        auto o = Json::Object();
        o["status"] = "displayed";
        o["actionsId"] = card.id;
        o["groupCount"] = int(card.groups.Length);
        return Ok(o);
    }

    void Register() {
        auto plugin = Meta::ExecutingPlugin();
        if (plugin is null) {
            warn("tm-agent pack: no executing plugin");
            return;
        }
        g_PackId = plugin.ID;
        auto b = TmMcp::ToolPackBuilder();
        b.AddTool(
            "AskUser",
            "Ask the user a question with optional choices. Returns immediately (never blocks). "
            + "The survey appears in the chat; the user can pick options (multiSelect allows several) "
            + "and Submit, or just type a normal reply. Use this instead of guessing preferences. "
            + "question (required), options[] (optional), multiSelect (bool), allowFreeText (bool, default true).",
            '{"type":"object","properties":{"question":{"type":"string"},"options":{"type":"array","items":{"type":"string"}},"multiSelect":{"type":"boolean"},"allowFreeText":{"type":"boolean"}},"required":["question"],"additionalProperties":false}'
        );
        b.AddTool(
            "OfferActions",
            "Show grouped action buttons in the chat. Each group can have a view camera target "
            + "and a continuePrompt that prefills (or sends) a follow-up. Returns immediately. "
            + "Use after presenting alternatives (e.g. scenery islands): one group per option, "
            + "small view button + continue button. title, groups[{id,label,view:{x,y,z},continuePrompt}].",
            '{"type":"object","properties":{"title":{"type":"string"},"groups":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"label":{"type":"string"},"view":{"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"},"z":{"type":"number"}}},"continuePrompt":{"type":"string"}}}}},"additionalProperties":false}'
        );
        b.SetDispatch(Dispatch);
        auto r = TmMcp::RegisterToolPack(b);
        if (r !is null && r.HasKey("error") && string(r["error"]).IndexOf("already registered") >= 0) {
            TmMcp::UnregisterToolPack(g_PackId);
            r = TmMcp::RegisterToolPack(b);
        }
        if (r is null || !r.HasKey("success") || !bool(r["success"])) {
            string err = (r !is null && r.HasKey("error")) ? string(r["error"]) : "null";
            warn("tm-agent pack register failed: " + err);
            return;
        }
        print("tm-agent pack registered pack=" + g_PackId);
    }

    void Unregister() {
        if (g_PackId.Length == 0) return;
        TmMcp::UnregisterToolPack(g_PackId);
        g_PackId = "";
    }
}
