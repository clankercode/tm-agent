namespace AgentUI {
    bool g_SettingsExpanded = false;
    float g_WindowWidth = 440;
    float g_WindowHeight = 620;
    vec2 g_WindowPos = vec2(120, 120);
    string g_InputText = "";
    int g_CurrentTurn = 0;
    int g_StepCount = 0;
    string g_Status = "Idle";

    int g_LastInputTokens = 0;
    int g_LastOutputTokens = 0;
    int g_LastTotalTokens = 0;
    int g_RunningOutputTokens = 0;

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

    string CurrentProviderLabel() {
        return AgentSettings::S_Provider == Provider::MiniMax ? "minimax" : "openai";
    }

    string CurrentModelLabel() {
        return AgentSettings::S_Provider == Provider::MiniMax ? AgentSettings::S_MiniMaxModel : AgentSettings::S_OpenAIModel;
    }

    void DrawProgressBar(float fillRatio) {
        vec4 fillColor = fillRatio > 0.85 ? vec4(0.96, 0.32, 0.30, 1.0) : fillRatio > 0.7 ? vec4(0.98, 0.70, 0.22, 1.0) : vec4(0.00, 0.82, 0.95, 1.0);

        UI::PushStyleColor(UI::Col::PlotHistogram, fillColor);
        UI::PushStyleColor(UI::Col::FrameBg, vec4(0.11, 0.12, 0.14, 1.0));
        UI::PushStyleVar(UI::StyleVar::FrameRounding, 2);
        UI::ProgressBar(fillRatio, vec2(-1, 3), "");
        UI::PopStyleVar();
        UI::PopStyleColor(2);
    }

    void DrawContextStats() {
        Json::Value@ tools = ToolAssembler::GetToolList();
        Json::Value@ stats = LlmHistory::BuildContextStats(tools, AgentSettings::S_MaxHistoryTokens);

        int maxTokens = AgentSettings::S_MaxHistoryTokens;
        int usedTokens = int(stats["estimatedTotalTokens"]);
        int remaining = int(stats["remainingBudgetTokens"]);
        float fillRatio = maxTokens > 0 ? Math::Clamp(float(usedTokens) / float(maxTokens), 0.0, 1.0) : 0.0;

        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(4, 4));
        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(8, 2));

        DrawProgressBar(fillRatio);

        UI::Dummy(vec2(0, 4));

        int pct = int(fillRatio * 100.0 + 0.5);
        DrawStatPair("CTX", FormatTokenCount(usedTokens) + " / " + FormatTokenCount(maxTokens) + " (" + pct + "%)");
        UI::SameLine();
        UI::Dummy(vec2(8, 0));
        UI::SameLine();
        vec4 remColor = remaining < 20000 ? vec4(0.96, 0.32, 0.30, 1.0) : vec4(0.88, 0.90, 0.93, 1.0);
        DrawStatPairColor("REM", FormatTokenCount(remaining), remColor);
        UI::SameLine();
        UI::Dummy(vec2(8, 0));
        UI::SameLine();
        DrawStatPair("MSGS", "" + int(stats["messageCount"]));

        UI::Dummy(vec2(0, 2));

        if (AccentCollapsingHeader("Token details")) {
            if (UI::BeginTable("stats", 2, UI::TableFlags::SizingFixedSame)) {
                UI::TableNextRow();
                UI::TableNextColumn();
                vec4 labelCol = vec4(0.45, 0.50, 0.58, 1.0);
                vec4 accentCol = vec4(0.95, 0.65, 0.15, 1.0);

                DrawStatRow("In", FormatTokenCount(g_LastInputTokens), labelCol);
                UI::TableNextColumn();
                DrawStatRow("Out", FormatTokenCount(g_LastOutputTokens), labelCol);

                UI::TableNextRow();
                UI::TableNextColumn();
                DrawStatRow("Total Out", FormatTokenCount(g_RunningOutputTokens), labelCol);
                UI::TableNextColumn();
                DrawStatRow("Sum", FormatTokenCount(int(stats["summaryTokens"])), labelCol);

                UI::TableNextRow();
                UI::TableNextColumn();
                DrawStatRow("Hist", FormatTokenCount(int(stats["historyTokens"])), labelCol);
                UI::TableNextColumn();
                DrawStatRow("Tools", FormatTokenCount(int(stats["toolSchemaTokens"])), labelCol);

                UI::TableNextRow();
                UI::TableNextColumn();
                string compaction = bool(stats["hasCompactedHistory"]) ? "yes" : "no";
                DrawStatRow("Compact", compaction, compaction == "yes" ? accentCol : labelCol);
                UI::TableNextColumn();
                UI::EndTable();
            }
        }

        UI::PopStyleVar(2);
    }

    void DrawStatRow(const string &in label, const string &in value, const vec4 &in color) {
        UI::PushStyleColor(UI::Col::Text, color);
        UI::Text(label + ":");
        UI::PopStyleColor();
        UI::SameLine();
        UI::Text(value);
    }

    void DrawStatPair(const string &in label, const string &in value) {
        UI::PushStyleColor(UI::Col::Text, vec4(0.45, 0.50, 0.58, 1.0));
        UI::Text(label);
        UI::PopStyleColor();
        UI::SameLine();
        UI::Text(value);
    }

    void DrawStatPairColor(const string &in label, const string &in value, const vec4 &in valueColor) {
        UI::PushStyleColor(UI::Col::Text, vec4(0.45, 0.50, 0.58, 1.0));
        UI::Text(label);
        UI::PopStyleColor();
        UI::SameLine();
        UI::PushStyleColor(UI::Col::Text, valueColor);
        UI::Text(value);
        UI::PopStyleColor();
    }

    bool AccentCollapsingHeader(const string &in label) {
        UI::PushStyleColor(UI::Col::Header, vec4(0.11, 0.13, 0.16, 1.0));
        UI::PushStyleColor(UI::Col::HeaderHovered, vec4(0.15, 0.18, 0.22, 1.0));
        UI::PushStyleColor(UI::Col::HeaderActive, vec4(0.18, 0.22, 0.27, 1.0));
        bool open = UI::CollapsingHeader(label);
        UI::PopStyleColor(3);
        return open;
    }

    void PushTheme() {
        UI::PushStyleColor(UI::Col::WindowBg, vec4(0.07, 0.08, 0.10, 1.0));
        UI::PushStyleColor(UI::Col::ChildBg, vec4(0.09, 0.10, 0.12, 1.0));
        UI::PushStyleColor(UI::Col::FrameBg, vec4(0.14, 0.16, 0.19, 1.0));
        UI::PushStyleColor(UI::Col::FrameBgHovered, vec4(0.18, 0.20, 0.24, 1.0));
        UI::PushStyleColor(UI::Col::FrameBgActive, vec4(0.20, 0.23, 0.27, 1.0));
        UI::PushStyleColor(UI::Col::TitleBg, vec4(0.07, 0.08, 0.10, 1.0));
        UI::PushStyleColor(UI::Col::TitleBgActive, vec4(0.07, 0.08, 0.10, 1.0));
        UI::PushStyleColor(UI::Col::TitleBgCollapsed, vec4(0.07, 0.08, 0.10, 1.0));
        UI::PushStyleColor(UI::Col::Header, vec4(0.15, 0.18, 0.22, 1.0));
        UI::PushStyleColor(UI::Col::HeaderHovered, vec4(0.20, 0.24, 0.29, 1.0));
        UI::PushStyleColor(UI::Col::HeaderActive, vec4(0.25, 0.30, 0.36, 1.0));
        UI::PushStyleColor(UI::Col::Button, vec4(0.18, 0.21, 0.25, 1.0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.24, 0.28, 0.33, 1.0));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.30, 0.35, 0.42, 1.0));
        UI::PushStyleColor(UI::Col::Separator, vec4(0.18, 0.20, 0.24, 1.0));
        UI::PushStyleColor(UI::Col::Text, vec4(0.88, 0.90, 0.93, 1.0));
        UI::PushStyleColor(UI::Col::TextDisabled, vec4(0.48, 0.52, 0.58, 1.0));
        UI::PushStyleColor(UI::Col::Border, vec4(0.95, 0.65, 0.15, 0.18));

        UI::PushStyleVar(UI::StyleVar::WindowPadding, vec2(12, 10));
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(8, 5));
        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(8, 6));
        UI::PushStyleVar(UI::StyleVar::FrameRounding, 4);
        UI::PushStyleVar(UI::StyleVar::WindowRounding, 5);
        UI::PushStyleVar(UI::StyleVar::GrabRounding, 3);
        UI::PushStyleVar(UI::StyleVar::WindowBorderSize, 1);
    }

    void PopTheme() {
        UI::PopStyleVar(7);
        UI::PopStyleColor(18);
    }

    void Render() {
        if (!AgentSettings::S_ShowWindow) return;

        // TEMP (dev only): Cond::Always pins the window so capture_ui.sh can crop to a known region.
        // Revert to Cond::FirstUseEver before shipping so users can drag/resize.
        UI::SetNextWindowSize(int(g_WindowWidth), int(g_WindowHeight), UI::Cond::Always);
        UI::SetNextWindowPos(int(g_WindowPos.x), int(g_WindowPos.y), UI::Cond::Always);

        PushTheme();

        if (UI::Begin("TM Agent", AgentSettings::S_ShowWindow, UI::WindowFlags::NoCollapse)) {
            auto app = cast<CGameManiaPlanet>(GetApp());
            auto editor = app !is null ? cast<CGameCtnEditorFree>(app.Editor) : null;

            if (editor is null) {
                DrawNotInEditor();
            } else {
                DrawHeader();
                DrawContextStats();
                UI::Separator();
                DrawMessages();
                DrawInput();
                DrawSettings();
            }

            auto winSize = UI::GetWindowSize();
            g_WindowWidth = winSize.x;
            g_WindowHeight = winSize.y;
            g_WindowPos = UI::GetWindowPos();
        }
        UI::End();

        PopTheme();
    }

    void DrawCenteredText(const string &in s, const vec4 &in color) {
        vec2 winPos = UI::GetWindowPos();
        float winW = UI::GetWindowSize().x;
        vec2 textSize = UI::MeasureString(s);
        vec2 cur = UI::GetCursorPos();
        float absX = winPos.x + (winW - textSize.x) * 0.5;
        float absY = winPos.y + cur.y - UI::GetScrollY();
        UI::GetWindowDrawList().AddText(vec2(absX, absY), color, s);
        UI::Dummy(vec2(0, textSize.y));
    }

    void DrawCentered(const string &in s) {
        DrawCenteredText(s, vec4(0.88, 0.90, 0.93, 1.0));
    }

    void DrawCenteredDisabled(const string &in s) {
        DrawCenteredText(s, vec4(0.48, 0.52, 0.58, 1.0));
    }

    void DrawBrandFooter() {
        DrawCenteredText("T M   \xE2\x80\xA2   A G E N T", vec4(0.32, 0.38, 0.46, 1.0));
    }

    void DrawCenteredOrnament(float width, const vec4 &in color) {
        vec2 winPos = UI::GetWindowPos();
        float winW = UI::GetWindowSize().x;
        vec2 cur = UI::GetCursorPos();
        float y = winPos.y + cur.y - UI::GetScrollY();
        float leftX = winPos.x + (winW - width) * 0.5;
        float midX = winPos.x + winW * 0.5;
        auto dl = UI::GetWindowDrawList();
        dl.AddLine(vec2(leftX, y + 4), vec2(midX - 6, y + 4), color, 1);
        dl.AddLine(vec2(midX + 6, y + 4), vec2(leftX + width, y + 4), color, 1);
        dl.AddCircleFilled(vec2(midX, y + 4), 2, color);
        UI::Dummy(vec2(0, 10));
    }

    void DrawCenteredBreadcrumb(const string &in left, const string &in sep, const string &in right, const vec4 &in dimCol, const vec4 &in sepCol, const vec4 &in brightCol) {
        float gap = 6.0;
        vec2 lSize = UI::MeasureString(left);
        vec2 sSize = UI::MeasureString(sep);
        vec2 rSize = UI::MeasureString(right);
        float totalW = lSize.x + sSize.x + rSize.x + gap * 2;

        vec2 winPos = UI::GetWindowPos();
        float winW = UI::GetWindowSize().x;
        vec2 cur = UI::GetCursorPos();
        float absX = winPos.x + (winW - totalW) * 0.5;
        float absY = winPos.y + cur.y - UI::GetScrollY();

        auto dl = UI::GetWindowDrawList();
        dl.AddText(vec2(absX, absY), dimCol, left);
        dl.AddText(vec2(absX + lSize.x + gap, absY), sepCol, sep);
        dl.AddText(vec2(absX + lSize.x + gap + sSize.x + gap, absY), brightCol, right);
        UI::Dummy(vec2(0, lSize.y));
    }

    void DrawIconBadge(float size, const string &in icon, const vec4 &in fillColor, const vec4 &in strokeColor, const vec4 &in iconColor) {
        vec2 winPos = UI::GetWindowPos();
        float winW = UI::GetWindowSize().x;
        vec2 cur = UI::GetCursorPos();
        float absX = winPos.x + (winW - size) * 0.5;
        float absY = winPos.y + cur.y - UI::GetScrollY();

        auto dl = UI::GetWindowDrawList();
        dl.AddRectFilled(vec4(absX, absY, size, size), fillColor, 8);
        dl.AddRect(vec4(absX, absY, size, size), strokeColor, 8, 1);

        vec2 iconSize = UI::MeasureString(icon);
        dl.AddText(vec2(absX + (size - iconSize.x) * 0.5, absY + (size - iconSize.y) * 0.5), iconColor, icon);

        UI::Dummy(vec2(0, size));
    }

    void DrawAmberTitleAccent() {
        vec4 accent = vec4(0.95, 0.65, 0.15, 0.9);
        vec4 accentFade = vec4(0.95, 0.65, 0.15, 0.0);
        vec2 winPos = UI::GetWindowPos();
        vec2 winSize = UI::GetWindowSize();
        vec2 cur = UI::GetCursorPos();
        auto dl = UI::GetWindowDrawList();
        float y = winPos.y + cur.y - UI::GetScrollY();
        dl.AddRectFilledMultiColor(vec4(winPos.x, y, winSize.x, 2), accent, accentFade, accentFade, accent);
        UI::Dummy(vec2(0, 6));
    }

    void DrawNotInEditor() {
        vec4 accent = vec4(0.95, 0.65, 0.15, 1.0);
        vec4 badgeFill = vec4(0.18, 0.13, 0.05, 1.0);
        vec4 badgeStroke = vec4(0.95, 0.65, 0.15, 0.35);
        vec4 iconColor = vec4(0.95, 0.65, 0.15, 1.0);

        DrawAmberTitleAccent();

        float availH = UI::GetContentRegionAvail().y;
        UI::Dummy(vec2(0, Math::Max(availH * 0.15, 12.0)));

        DrawIconBadge(56, Icons::ExclamationTriangle, badgeFill, badgeStroke, iconColor);

        UI::Dummy(vec2(0, 22));

        UI::PushFont(UI::Font::DefaultBold);
        UI::PushFontSize(22);
        DrawCenteredText("W A I T I N G   F O R   E D I T O R", accent);
        UI::PopFontSize();
        UI::PopFont();

        UI::Dummy(vec2(0, 18));
        DrawCentered("Ready when you open a track in the map editor.");
        UI::Dummy(vec2(0, 12));
        DrawCenteredBreadcrumb(
            "Create",
            "\xE2\x80\xBA",
            "Track Editor",
            vec4(0.48, 0.52, 0.58, 1.0),
            vec4(0.95, 0.65, 0.15, 0.55),
            vec4(0.88, 0.90, 0.93, 1.0)
        );

        float remaining = UI::GetContentRegionAvail().y;
        if (remaining > 80) {
            UI::Dummy(vec2(0, (remaining - 40) * 0.5));
            DrawCenteredOrnament(120, vec4(0.95, 0.65, 0.15, 0.30));
            UI::Dummy(vec2(0, (remaining - 40) * 0.5 - 18));
        }
        DrawBrandFooter();
    }

    void DrawHeader() {
        vec4 idleColor = vec4(0.00, 0.82, 0.95, 1.0);
        vec4 runColor = vec4(0.98, 0.70, 0.22, 1.0);
        vec4 errColor = vec4(0.96, 0.32, 0.30, 1.0);

        if (g_Status.StartsWith("Error:")) {
            DrawColoredText(errColor, "Turn " + g_CurrentTurn + "." + g_StepCount);
            UI::SameLine();
            DrawColoredText(errColor, g_Status);
        } else {
            UI::Text("Turn " + g_CurrentTurn + "." + g_StepCount);
            UI::SameLine();

            if (g_Status == "Idle") {
                DrawColoredText(idleColor, "[Idle]");
            } else if (g_Status == "Running" || g_Status == "Calling LLM...") {
                DrawColoredText(runColor, "[" + g_Status + "]");
                UI::SameLine();
                int dotCount = (Time::Now / 300) % 4;
                string dots = "";
                for (int i = 0; i < dotCount; i++) dots += ".";
                for (int i = dotCount; i < 3; i++) dots += " ";
                UI::TextDisabled(dots);
            } else {
                DrawColoredText(errColor, "[" + g_Status + "]");
            }
        }

        UI::SameLine();
        vec4 dotColor = vec4(0.00, 0.82, 0.95, 1.0);
        DrawColoredText(dotColor, "  \xE2\x80\xA2  ");
        UI::SameLine();
        UI::TextDisabled(CurrentProviderLabel() + " / " + CurrentModelLabel());

        UI::SameLine();
        UI::SetCursorPosX(UI::GetWindowSize().x - 70);
        UI::PushStyleColor(UI::Col::Button, vec4(0, 0, 0, 0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.00, 0.82, 0.95, 0.18));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.00, 0.82, 0.95, 0.30));
        UI::PushStyleColor(UI::Col::Text, vec4(0.55, 0.62, 0.70, 1.0));
        if (UI::Button("Clear")) {
            ClearMessages();
        }
        UI::PopStyleColor(4);

        UI::PushStyleColor(UI::Col::Separator, vec4(0.00, 0.82, 0.95, 0.35));
        UI::Separator();
        UI::PopStyleColor();
    }

    void DrawMessages() {
        float bottomReserve = 150;

        UI::PushStyleColor(UI::Col::ChildBg, vec4(0.035, 0.042, 0.055, 1.0));
        UI::PushStyleVar(UI::StyleVar::ChildRounding, 6);
        UI::PushStyleVar(UI::StyleVar::ChildBorderSize, 0);
        UI::PushStyleVar(UI::StyleVar::WindowPadding, vec2(14, 12));

        UI::BeginChild("##messages", vec2(0, -bottomReserve), false, UI::WindowFlags::AlwaysVerticalScrollbar);

        if (g_Messages.Length == 0) {
            DrawIdlePlaceholder();
        } else {
            for (uint i = 0; i < g_Messages.Length; i++) {
                auto @msg = g_Messages[i];
                DrawMessage(msg);
            }
            UI::SetScrollHereY(1.0f);
        }

        UI::EndChild();

        UI::PopStyleVar(3);
        UI::PopStyleColor();
    }

    void DrawIdlePlaceholder() {
        vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);

        UI::Dummy(vec2(0, 16));
        UI::PushStyleColor(UI::Col::Text, accent);
        UI::PushFont(UI::Font::DefaultBold);
        UI::PushFontSize(20);
        UI::Text("  TM AGENT");
        UI::PopFontSize();
        UI::PopFont();
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 2));
        UI::Indent(10);
        UI::TextWrapped("Your in-editor copilot. Inspect the map, find blocks or items, and place things at the cursor.");
        UI::Dummy(vec2(0, 10));

        UI::PushStyleColor(UI::Col::Text, vec4(0.55, 0.60, 0.68, 1.0));
        UI::Text("TRY");
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 2));

        DrawExampleLine(accent, "What's on the current map?");
        DrawExampleLine(accent, "Place a start block at the cursor.");
        DrawExampleLine(accent, "Find road blocks with 'dirt' in the name.");
        UI::Unindent(10);
    }

    void DrawExampleLine(const vec4 &in accent, const string &in example) {
        UI::PushStyleColor(UI::Col::Text, accent);
        UI::Text("  >");
        UI::PopStyleColor();
        UI::SameLine();
        UI::Text(example);
    }

    void DrawMessage(Message@ msg) {
        vec4 userAccent = vec4(0.55, 0.75, 1.00, 1.0);
        vec4 agentAccent = vec4(0.00, 0.82, 0.95, 1.0);

        if (msg.type == MsgType::User) {
            UI::Dummy(vec2(0, 4));
            DrawColoredText(userAccent, "YOU");
            UI::TextWrapped(msg.content);
            UI::Dummy(vec2(0, 6));
        } else if (msg.type == MsgType::Assistant) {
            UI::Dummy(vec2(0, 4));
            DrawColoredText(agentAccent, "AGENT");
            UI::TextWrapped(msg.content);
            UI::Dummy(vec2(0, 6));
        } else if (msg.type == MsgType::ToolCall) {
            UI::Indent();
            if (UI::TreeNode(msg.toolName + "()")) {
                UI::Text("Input: " + msg.content);
                UI::TreePop();
            }
            UI::Unindent();
        } else if (msg.type == MsgType::ToolResult) {
            UI::Indent();
            DrawColoredText(vec4(0.40, 0.82, 0.55, 1.0), msg.toolName + " result");
            UI::TextWrapped(msg.toolResult);
            UI::Unindent();
            DrawSpacing();
        } else if (msg.type == MsgType::System) {
            DrawColoredText(vec4(0.50, 0.54, 0.60, 1.0), msg.content);
            DrawSpacing();
        }
    }

    void DrawInput() {
        UI::Separator();

        float inputHeight = 96;
        float inputWidth = UI::GetWindowContentRegionWidth() - 84;

        g_InputText = UI::InputTextMultiline("##input", g_InputText, vec2(inputWidth, inputHeight));

        UI::SameLine();
        UI::PushStyleColor(UI::Col::Button, vec4(0.95, 0.65, 0.15, 0.12));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.95, 0.65, 0.15, 0.26));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.95, 0.65, 0.15, 0.42));
        UI::PushStyleColor(UI::Col::Border, vec4(0.95, 0.65, 0.15, 0.55));
        UI::PushStyleColor(UI::Col::Text, vec4(0.95, 0.65, 0.15, 1.0));
        UI::PushStyleVar(UI::StyleVar::FrameBorderSize, 1);
        if (UI::Button("Send", vec2(72, inputHeight))) {
            if (g_InputText.Length > 0) {
                SendMessage(g_InputText);
                g_InputText = "";
            }
        }
        UI::PopStyleColor(5);
        UI::PopStyleVar();
    }

    void DrawSettings() {
        if (AccentCollapsingHeader("Settings")) {
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
        g_LastInputTokens = 0;
        g_LastOutputTokens = 0;
        g_LastTotalTokens = 0;
        g_RunningOutputTokens = 0;
    }

    void UpdateTokenStats(int inputTokens, int outputTokens, int totalTokens) {
        g_LastInputTokens = inputTokens;
        g_LastOutputTokens = outputTokens;
        g_LastTotalTokens = totalTokens;
        g_RunningOutputTokens += outputTokens;
    }

    void RenderMenu() {
        if (UI::MenuItem("TM Agent", "", AgentSettings::S_ShowWindow)) {
            AgentSettings::S_ShowWindow = !AgentSettings::S_ShowWindow;
        }
    }
}
