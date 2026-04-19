namespace AgentUI {
    bool g_WindowVisible = false;
    bool g_SettingsExpanded = false;
    float g_WindowWidth = 400;
    float g_WindowHeight = 500;
    vec2 g_WindowPos = vec2(50, 50);
    string g_InputText = "";
    int g_CurrentTurn = 0;
    int g_StepCount = 0;
    string g_Status = "Idle";

    enum MsgType { User, Assistant, ToolCall, ToolResult, System }

    class Message {
        MsgType type;
        string content;
        string toolName;
        string toolResult;
        bool expanded;

        Message(MsgType t, const string &in c) {
            type = t;
            content = c;
            expanded = false;
        }
    }

    array<Message@> g_Messages;

    void DrawColoredText(const vec4 &in color, const string &in text) {
        UI::PushStyleColor(UI::Col::Text, color);
        UI::Text(text);
        UI::PopStyleColor();
    }

    void DrawSpacing() {
        UI::Dummy(vec2(0, 4));
    }

    string FormatTokenCount(int tokens) {
        return "" + tokens;
    }

    string FormatAge(uint ageMs) {
        if (ageMs < 1000) return "" + ageMs + "ms";
        if (ageMs < 60000) return "" + (ageMs / 1000) + "s";
        if (ageMs < 3600000) return "" + (ageMs / 60000) + "m";
        return "" + (ageMs / 3600000) + "h";
    }

    void DrawContextStats() {
        Json::Value@ tools = ToolAssembler::GetToolList();
        Json::Value@ stats = LlmHistory::BuildContextStats(tools, AgentSettings::S_MaxHistoryTokens);

        string provider = AgentSettings::S_Provider == Provider::MiniMax ? "minimax" : "openai";
        string compaction = bool(stats["hasCompactedHistory"]) ? "yes" : "no";
        string lastCompaction = "never";
        if (stats["lastCompactionAt"].GetType() != Json::Type::Null) {
            uint lastAt = uint(stats["lastCompactionAt"]);
            if (lastAt > 0) {
                uint ago = Time::Now > lastAt ? Time::Now - lastAt : 0;
                lastCompaction = FormatAge(ago) + " ago";
            }
        }

        UI::Separator();
        string model = provider == "minimax" ? AgentSettings::S_MiniMaxModel : AgentSettings::S_OpenAIModel;
        string effort = provider == "openai" ? AgentSettings::S_OpenAIReasoningEffort : "n/a";
        UI::Text("Provider: " + provider + " | Model: " + model + " | Effort: " + effort);
        UI::Text(
            "Ctx " + FormatTokenCount(int(stats["estimatedTotalTokens"])) + "/" + FormatTokenCount(AgentSettings::S_MaxHistoryTokens)
            + "  Rem " + FormatTokenCount(int(stats["remainingBudgetTokens"]))
            + "  Prompt " + FormatTokenCount(int(stats["systemPromptTokens"]))
            + "  Tools " + FormatTokenCount(int(stats["toolSchemaTokens"]))
            + "  Hist " + FormatTokenCount(int(stats["historyTokens"]))
            + "  Sum " + FormatTokenCount(int(stats["summaryTokens"]))
        );
        UI::Text(
            "Msgs " + int(stats["messageCount"])
            + "  Compactions " + int(stats["compactionCount"])
            + "  Compacted " + compaction
            + "  Last " + lastCompaction
        );
    }

    void Render() {
        if (!g_WindowVisible) return;

        UI::SetNextWindowSize(int(g_WindowWidth), int(g_WindowHeight), UI::Cond::FirstUseEver);
        UI::SetNextWindowPos(int(g_WindowPos.x), int(g_WindowPos.y), UI::Cond::FirstUseEver);

        if (UI::Begin("TM Agent", g_WindowVisible, UI::WindowFlags::NoTitleBar)) {
            DrawHeader();
            DrawMessages();
            DrawInput();
            DrawContextStats();
            DrawSettings();

            auto winSize = UI::GetWindowSize();
            g_WindowWidth = winSize.x;
            g_WindowHeight = winSize.y;
            g_WindowPos = UI::GetWindowPos();
        }
        UI::End();
    }

    void DrawHeader() {
        if (g_Status.StartsWith("Error:")) {
            DrawColoredText(vec4(1, 0, 0, 1), "Turn " + g_CurrentTurn + "." + g_StepCount);
            UI::SameLine();
            DrawColoredText(vec4(1, 0, 0, 1), g_Status);
        } else {
            UI::Text("Turn " + g_CurrentTurn + "." + g_StepCount);
            UI::SameLine();

            if (g_Status == "Idle") {
                DrawColoredText(vec4(0, 1, 0, 1), "[Idle]");
            } else if (g_Status == "Running" || g_Status == "Calling LLM...") {
                DrawColoredText(vec4(1, 1, 0, 1), "[" + g_Status + "]");
                UI::SameLine();
                int dotCount = (Time::Now / 300) % 4;
                string dots = "";
                for (int i = 0; i < dotCount; i++) dots += ".";
                for (int i = dotCount; i < 3; i++) dots += " ";
                UI::TextDisabled(dots);
            } else {
                DrawColoredText(vec4(1, 0, 0, 1), "[" + g_Status + "]");
            }
        }

        UI::SameLine();
        UI::SetCursorPosX(UI::GetWindowSize().x - 60);
        if (UI::Button("Clear")) {
            ClearMessages();
        }

        UI::Separator();
    }

    void DrawMessages() {
        UI::BeginChild("##messages", vec2(0, -70), true, UI::WindowFlags::AlwaysVerticalScrollbar);

        for (uint i = 0; i < g_Messages.Length; i++) {
            auto @msg = g_Messages[i];
            DrawMessage(msg);
        }

        UI::SetScrollHereY(1.0f);
        UI::EndChild();
    }

    void DrawMessage(Message@ msg) {
        if (msg.type == MsgType::User) {
            DrawColoredText(vec4(0.5, 0.5, 1, 1), "You:");
            UI::Text(msg.content);
            DrawSpacing();
        } else if (msg.type == MsgType::Assistant) {
            DrawColoredText(vec4(1, 0.8, 0, 1), "Agent:");
            UI::Text(msg.content);
            DrawSpacing();
        } else if (msg.type == MsgType::ToolCall) {
            UI::Indent();
            if (UI::TreeNode(msg.toolName + "()")) {
                UI::Text("Input: " + msg.content);
                UI::TreePop();
            }
            UI::Unindent();
        } else if (msg.type == MsgType::ToolResult) {
            UI::Indent();
            DrawColoredText(vec4(0, 0.8, 0, 1), msg.toolName + " result:");
            UI::Text(msg.toolResult);
            UI::Unindent();
            DrawSpacing();
        } else if (msg.type == MsgType::System) {
            DrawColoredText(vec4(0.6, 0.6, 0.6, 1), msg.content);
            DrawSpacing();
        }
    }

    void DrawInput() {
        UI::Separator();

        float inputHeight = 60;
        float inputWidth = UI::GetWindowContentRegionWidth() - 80;

        g_InputText = UI::InputTextMultiline("##input", g_InputText, vec2(inputWidth, inputHeight));

        UI::SameLine();
        if (UI::Button("Send")) {
            if (g_InputText.Length > 0) {
                SendMessage(g_InputText);
                g_InputText = "";
            }
        }
    }

    void DrawSettings() {
        if (UI::CollapsingHeader("Settings")) {
            UI::Indent();

            string currentProvider = AgentSettings::S_Provider == Provider::MiniMax ? "minimax" : "openai";
            if (UI::BeginCombo("Provider", currentProvider)) {
                if (UI::Selectable("minimax", AgentSettings::S_Provider == Provider::MiniMax)) {
                    AgentSettings::S_Provider = Provider::MiniMax;
                }
                if (UI::Selectable("openai", AgentSettings::S_Provider == Provider::OpenAI)) {
                    AgentSettings::S_Provider = Provider::OpenAI;
                }
                UI::EndCombo();
            }

            if (AgentSettings::S_Provider == Provider::MiniMax) {
                UI::InputText("MiniMax API Key", AgentSettings::S_MiniMaxApiKey);
                UI::InputText("MiniMax Model", AgentSettings::S_MiniMaxModel);
            } else {
                UI::InputText("OpenAI API Key", AgentSettings::S_OpenAIApiKey);
                UI::InputText("OpenAI Model", AgentSettings::S_OpenAIModel);
                string currentEffort = AgentSettings::S_OpenAIReasoningEffort;
                if (UI::BeginCombo("OpenAI Effort", currentEffort)) {
                    if (UI::Selectable("none", currentEffort == "none")) {
                        AgentSettings::S_OpenAIReasoningEffort = "none";
                    }
                    if (UI::Selectable("minimal", currentEffort == "minimal")) {
                        AgentSettings::S_OpenAIReasoningEffort = "minimal";
                    }
                    if (UI::Selectable("low", currentEffort == "low")) {
                        AgentSettings::S_OpenAIReasoningEffort = "low";
                    }
                    if (UI::Selectable("medium", currentEffort == "medium")) {
                        AgentSettings::S_OpenAIReasoningEffort = "medium";
                    }
                    if (UI::Selectable("high", currentEffort == "high")) {
                        AgentSettings::S_OpenAIReasoningEffort = "high";
                    }
                    if (UI::Selectable("xhigh", currentEffort == "xhigh")) {
                        AgentSettings::S_OpenAIReasoningEffort = "xhigh";
                    }
                    UI::EndCombo();
                }
            }

            if (UI::Button("Clear History")) {
                ClearMessages();
            }
            UI::Unindent();
        }
    }

    void SendMessage(const string &in text) {
        AddMessage(MsgType::User, text);
        g_CurrentTurn++;
        g_StepCount = 1;
        g_Status = "Running";

        startnew(SendMessageCoro, text);
    }

    void IncrementStep() {
        g_StepCount++;
    }

    void SendMessageCoro(const string &in text) {
        ::SendMessage(text);
    }

    void AddMessage(MsgType t, const string &in content) {
        g_Messages.InsertLast(Message(t, content));
    }

    void AddToolCall(const string &in toolName, const string &in inputJson) {
        auto msg = Message(MsgType::ToolCall, inputJson);
        msg.toolName = toolName;
        g_Messages.InsertLast(msg);
    }

    void AddToolResult(const string &in toolName, const string &in result) {
        auto msg = Message(MsgType::ToolResult, result);
        msg.toolName = toolName;
        g_Messages.InsertLast(msg);
    }

    void SetStatus(const string &in status) {
        g_Status = status;
    }

    void ClearMessages() {
        LlmHistory::ClearHistory();
        g_Messages.RemoveRange(0, g_Messages.Length);
        g_CurrentTurn = 0;
        g_StepCount = 0;
        g_Status = "Idle";
    }

    void RenderMenu() {
        if (UI::MenuItem("TM Agent", "", g_WindowVisible)) {
            g_WindowVisible = !g_WindowVisible;
        }
    }
}
