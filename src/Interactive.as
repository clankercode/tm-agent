// Interactive.as — surveys (AskUser) and grouped action cards (OfferActions).
// Tools return immediately; the card lives in the chatlog until the user
// submits, types a free-text reply, or clicks an action.

namespace Interactive {

    const uint POPOUT_THRESHOLD = 6;

    class Survey {
        string id;
        string question;
        array<string> options;
        array<bool> selected;
        bool multiSelect;
        bool allowFreeText;
        bool answered;
        string answerText;
        bool popOutOpen;
    }

    class ActionGroup {
        string id;
        string label;
        bool hasView;
        vec3 viewPos;
        string continuePrompt;
    }

    class Card {
        string id;
        string kind; // "survey" | "actions"
        Survey@ survey;
        string actionsTitle;
        array<ActionGroup@> groups;
    }

    array<Card@> g_Cards;
    uint g_NextId = 1;

    void ResetForTests() {
        g_Cards.RemoveRange(0, g_Cards.Length);
        g_NextId = 1;
    }

    string NextId(const string &in prefix) {
        string id = prefix + "-" + g_NextId;
        g_NextId++;
        return id;
    }

    Card@ Find(const string &in id) {
        for (uint i = 0; i < g_Cards.Length; i++) {
            if (g_Cards[i].id == id) return g_Cards[i];
        }
        return null;
    }

    bool JsonBool(Json::Value@ o, const string &in key, bool fallback) {
        if (o is null || !o.HasKey(key)) return fallback;
        if (o[key].GetType() != Json::Type::Boolean) return fallback;
        return bool(o[key]);
    }

    string JsonStr(Json::Value@ o, const string &in key) {
        if (o is null || !o.HasKey(key)) return "";
        return string(o[key]);
    }

    bool ParseView(Json::Value@ o, vec3 &out pos) {
        if (o is null || o.GetType() != Json::Type::Object) return false;
        if (!o.HasKey("x") || !o.HasKey("y") || !o.HasKey("z")) return false;
        pos = vec3(float(o["x"]), float(o["y"]), float(o["z"]));
        return true;
    }

    Card@ OfferSurvey(Json::Value@ input) {
        auto s = Survey();
        s.id = NextId("survey");
        s.question = JsonStr(input, "question");
        s.multiSelect = JsonBool(input, "multiSelect", false);
        s.allowFreeText = JsonBool(input, "allowFreeText", true);
        s.answered = false;
        s.popOutOpen = false;
        if (input !is null && input.HasKey("options") && input["options"].GetType() == Json::Type::Array) {
            auto opts = input["options"];
            for (uint i = 0; i < opts.Length; i++) {
                s.options.InsertLast(string(opts[i]));
                s.selected.InsertLast(false);
            }
        }
        auto card = Card();
        card.id = s.id;
        card.kind = "survey";
        @card.survey = s;
        g_Cards.InsertLast(card);
        return card;
    }

    Card@ OfferActions(Json::Value@ input) {
        auto card = Card();
        card.id = NextId("actions");
        card.kind = "actions";
        card.actionsTitle = JsonStr(input, "title");
        if (input !is null && input.HasKey("groups") && input["groups"].GetType() == Json::Type::Array) {
            auto gs = input["groups"];
            for (uint i = 0; i < gs.Length; i++) {
                auto g = ActionGroup();
                g.id = JsonStr(gs[i], "id");
                if (g.id.Length == 0) g.id = "g" + i;
                g.label = JsonStr(gs[i], "label");
                g.continuePrompt = JsonStr(gs[i], "continuePrompt");
                vec3 vp;
                g.hasView = gs[i].HasKey("view") && ParseView(gs[i]["view"], vp);
                if (g.hasView) g.viewPos = vp;
                card.groups.InsertLast(g);
            }
        }
        g_Cards.InsertLast(card);
        return card;
    }

    void ToggleOption(Survey@ s, uint i) {
        if (s is null || i >= s.options.Length || s.answered) return;
        if (s.multiSelect) {
            s.selected[i] = !s.selected[i];
            return;
        }
        for (uint j = 0; j < s.selected.Length; j++) {
            s.selected[j] = (j == i);
        }
    }

    string FormatSurveyAnswer(Survey@ s) {
        if (s is null) return "";
        if (s.answerText.Length > 0) return s.answerText;
        string ans = "";
        for (uint i = 0; i < s.options.Length; i++) {
            if (!s.selected[i]) continue;
            if (ans.Length > 0) ans += ", ";
            ans += s.options[i];
        }
        return ans;
    }

    void MarkAnswered(Survey@ s, const string &in text) {
        if (s is null) return;
        s.answered = true;
        s.answerText = text;
        s.popOutOpen = false;
    }

    void OnUserFreeText(const string &in text) {
        for (uint i = 0; i < g_Cards.Length; i++) {
            if (g_Cards[i].kind != "survey") continue;
            auto s = g_Cards[i].survey;
            if (s is null || s.answered) continue;
            MarkAnswered(s, text);
        }
    }

    bool WantsPopOut(Survey@ s) {
        return s !is null && s.options.Length > POPOUT_THRESHOLD;
    }

    Json::Value@ CardsToJson() {
        auto arr = Json::Array();
        for (uint i = 0; i < g_Cards.Length; i++) {
            auto o = Json::Object();
            o["id"] = g_Cards[i].id;
            o["kind"] = g_Cards[i].kind;
            if (g_Cards[i].survey !is null) {
                o["answered"] = g_Cards[i].survey.answered;
                o["optionCount"] = int(g_Cards[i].survey.options.Length);
                o["question"] = g_Cards[i].survey.question;
            }
            o["groupCount"] = int(g_Cards[i].groups.Length);
            arr.Add(o);
        }
        return arr;
    }
}
