namespace AgentUI {
    bool g_SettingsExpanded = false;
    bool g_ShowSettings = false;
    bool g_PendingScrollBottom = false;
    // DEV-ONLY: when true, Render() draws the chat UI even without the
    // track editor open. Used for iterating on chat visuals from the
    // driver without needing a live map. Revert to false before ship.
    bool g_DemoMode = false;
    float g_WindowWidth = 440;
    float g_WindowHeight = 620;
    vec2 g_WindowPos = vec2(120, 120);

    // Settings window is managed by ImGui — we record its last-known pos/size
    // during Render so the driver can report it without asking ImGui directly.
    vec2 g_SettingsPos = vec2(0, 0);
    vec2 g_SettingsSize = vec2(0, 0);
    string g_InputText = "";
    int g_CurrentTurn = 0;
    int g_StepCount = 0;
    // DEV/UNITTEST-only: when >= 0, DrawMessages reports this as the child's
    // scroll position instead of the real one, letting tests force culling
    // conditions (tail cull = the crash repro) without real scroll input.
    float g_ForceScrollY = -1.0;
    // Status state — enum + optional description, only mutated atomically via
    // `Status.Set(kind, desc)`. A string "Error: foo" can't get passed around
    // and mis-parsed anymore; callers pass StatusKind::Error + "foo" explicitly.
    enum StatusKind { Idle, Running, CallingLLM, Cancelled, Error }

    class AgentStatus {
        private StatusKind m_kind = StatusKind::Idle;
        private string m_desc = "";

        void Set(StatusKind k, const string &in desc = "") {
            m_kind = k;
            m_desc = desc;
        }

        StatusKind get_Kind() const property { return m_kind; }
        string get_Description() const property { return m_desc; }

        bool get_InFlight() const property {
            return m_kind == StatusKind::Running || m_kind == StatusKind::CallingLLM;
        }

        string get_Label() const property {
            if (m_kind == StatusKind::Idle) return "IDLE";
            if (m_kind == StatusKind::Running) return "RUNNING";
            if (m_kind == StatusKind::CallingLLM) return "CALLING LLM";
            if (m_kind == StatusKind::Cancelled) return "CANCELLED";
            if (m_kind == StatusKind::Error) return m_desc.Length > 0 ? m_desc.ToUpper() : "ERROR";
            return "";
        }

        // Wire-format string used by the file-IPC driver (and human logs).
        // Must round-trip via FromWire to preserve state.
        string get_Wire() const property {
            if (m_kind == StatusKind::Idle) return "Idle";
            if (m_kind == StatusKind::Running) return "Running";
            if (m_kind == StatusKind::CallingLLM) return "Calling LLM...";
            if (m_kind == StatusKind::Cancelled) return "Cancelled";
            if (m_kind == StatusKind::Error) return "Error: " + m_desc;
            return "";
        }

        bool FromWire(const string &in s) {
            if (s == "Idle") { Set(StatusKind::Idle); return true; }
            if (s == "Running") { Set(StatusKind::Running); return true; }
            if (s == "Calling LLM..." || s == "Calling LLM") { Set(StatusKind::CallingLLM); return true; }
            if (s == "Cancelled") { Set(StatusKind::Cancelled); return true; }
            if (s.StartsWith("Error:")) {
                string body = s.SubStr(6);
                while (body.Length > 0 && body.SubStr(0, 1) == " ") body = body.SubStr(1);
                Set(StatusKind::Error, body);
                return true;
            }
            return false;
        }
    }

    AgentStatus g_Status;

    int g_LastInputTokens = 0;
    int g_LastCachedReadTokens = 0;
    int g_LastCacheWriteTokens = 0;
    int g_LastOutputTokens = 0;
    int g_LastTotalTokens = 0;
    // DEV/driver: one-shot force-open of the Token details header (verification).
    bool g_ForceTokenDetailsOpen = false;
    int g_RunningOutputTokens = 0;

    // Provider-test feedback shown under the Test button in Settings.
    string g_TestResult = "";
    vec4 g_TestColor = vec4(0.48, 0.52, 0.58, 1.0);
    bool g_TestRunning = false;

    enum MsgType { User, Assistant, ToolCall, ToolResult, System, Error, Interactive }

    class Message {
        MsgType type;
        string content;
        string toolName;
        string toolResult;
        bool expanded;
        string imagePath;   // screenshot shown inside a ToolResult chip
        string interactiveId; // Interactive::Card id for survey/action cards

        // Layout cache — filled on first draw, invalidated when width or
        // expanded state changes. Used by the virtual-scroll cull path.
        float cachedHeight;
        float cachedForWidth;
        bool cachedExpanded;

        // Formatting caches — avoid re-parsing/truncating per frame.
        string cachedPretty;       // prettified JSON for expanded body
        bool prettyComputed;
        string cachedPeek;         // truncated single-line preview
        float peekForWidth;        // availW at which cachedPeek was truncated

        Message(MsgType t, const string &in c) {
            type = t;
            content = c;
            expanded = false;
            cachedHeight = 0;
            cachedForWidth = 0;
            cachedExpanded = false;
            prettyComputed = false;
            peekForWidth = -1;
        }

        void InvalidateLayout() {
            cachedHeight = 0;
            cachedForWidth = 0;
            peekForWidth = -1;
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
        if (tokens < 1000) return "" + tokens;
        if (tokens < 10000) return Text::Format("%.1fk", float(tokens) / 1000.0);
        if (tokens < 1000000) return "" + (tokens / 1000) + "k";
        return Text::Format("%.1fM", float(tokens) / 1000000.0);
    }

    string FormatAge(uint ageMs) {
        if (ageMs < 1000) return "" + ageMs + "ms";
        if (ageMs < 60000) return "" + (ageMs / 1000) + "s";
        if (ageMs < 3600000) return "" + (ageMs / 60000) + "m";
        return "" + (ageMs / 3600000) + "h";
    }

    string CurrentProviderLabel() {
        return AgentSettings::CurrentProviderLabel();
    }

    string CurrentModelLabel() {
        return AgentSettings::CurrentModel();
    }

    void DrawProgressBar(float fillRatio) {
        vec4 fillColor = fillRatio > 0.85 ? vec4(0.96, 0.32, 0.30, 1.0) : fillRatio > 0.7 ? vec4(0.98, 0.70, 0.22, 1.0) : vec4(0.00, 0.82, 0.95, 1.0);

        // Track is visibly lighter than the child bg (0.035, 0.042, 0.055)
        // so the "capacity" strip reads even when fill is near-empty.
        UI::PushStyleColor(UI::Col::PlotHistogram, fillColor);
        UI::PushStyleColor(UI::Col::FrameBg, vec4(0.16, 0.18, 0.22, 1.0));
        UI::PushStyleVar(UI::StyleVar::FrameRounding, 4);
        UI::ProgressBar(fillRatio, vec2(-1, 8), "");
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

        vec4 remColor = remaining < 20000 ? vec4(0.96, 0.32, 0.30, 1.0) : vec4(0.88, 0.90, 0.93, 1.0);
        array<string> topLabels = {"CTX", "REM", "MSGS"};
        array<string> topValues = {
            FormatTokenCount(usedTokens) + " / " + FormatTokenCount(maxTokens),
            FormatTokenCount(remaining),
            "" + int(stats["messageCount"])
        };
        array<vec4> topColors = {
            vec4(0.88, 0.90, 0.93, 1.0),
            remColor,
            vec4(0.88, 0.90, 0.93, 1.0)
        };
        vec2 winPosTop = UI::GetWindowPos();
        float rightEdgeTop = winPosTop.x + UI::GetWindowSize().x - 16;
        float gapW = 14;
        for (uint i = 0; i < topLabels.Length; i++) {
            float chunkW = UI::MeasureString(topLabels[i]).x + 4 + UI::MeasureString(topValues[i]).x;
            if (i > 0) {
                vec4 prev = UI::GetItemRect();
                float prevRight = prev.x + prev.z;
                if (prevRight + gapW + chunkW < rightEdgeTop) {
                    UI::SameLine();
                    UI::Dummy(vec2(gapW - 8, 0));
                    UI::SameLine();
                }
            }
            DrawStatPairColor(topLabels[i], topValues[i], topColors[i]);
        }

        UI::Dummy(vec2(0, 2));

        bool forceOpen = g_ForceTokenDetailsOpen;
        g_ForceTokenDetailsOpen = false;
        if (forceOpen) UI::SetNextItemOpen(true, UI::Cond::Always);
        if (AccentCollapsingHeader("Token details")) {
            vec4 labelCol = vec4(0.45, 0.50, 0.58, 1.0);
            vec4 sepCol = vec4(0.30, 0.33, 0.38, 1.0);
            vec4 accentCol = vec4(0.95, 0.65, 0.15, 1.0);
            bool compacted = bool(stats["hasCompactedHistory"]);

            array<string> labels = {"In", "Cache", "Out", "Session", "Summary", "History", "Tools"};
            // Cache stat hidden when the provider reports no cache fields:
            // keeps the row tight for providers without prompt caching.
            bool hasCache = g_LastCachedReadTokens > 0 || g_LastCacheWriteTokens > 0;
            if (!hasCache) labels.RemoveAt(1);
            array<string> values = {
                FormatTokenCount(g_LastInputTokens),
                FormatTokenCount(g_LastCachedReadTokens) + "r" + (g_LastCacheWriteTokens > 0 ? "+" + FormatTokenCount(g_LastCacheWriteTokens) + "w" : ""),
                FormatTokenCount(g_LastOutputTokens),
                FormatTokenCount(g_RunningOutputTokens),
                FormatTokenCount(int(stats["summaryTokens"])),
                FormatTokenCount(int(stats["historyTokens"])),
                FormatTokenCount(int(stats["toolSchemaTokens"]))
            };
            if (!hasCache) values.RemoveAt(1);

            vec2 winPos = UI::GetWindowPos();
            float rightEdge = winPos.x + UI::GetWindowSize().x - 16;
            float sepW = UI::MeasureString("\xC2\xB7").x + 8;
            for (uint i = 0; i < labels.Length; i++) {
                float chunkW = UI::MeasureString(labels[i]).x + 4 + UI::MeasureString(values[i]).x;
                if (i > 0) {
                    vec4 prev = UI::GetItemRect();
                    float prevRight = prev.x + prev.z;
                    if (prevRight + sepW + chunkW < rightEdge) {
                        UI::SameLine();
                        DrawInlineSep(sepCol);
                        UI::SameLine();
                    }
                }
                DrawInlineStat(labels[i], values[i], labelCol);
                if (hasCache && labels[i] == "Cache" && UI::IsItemHovered()) {
                    int fresh = g_LastInputTokens - g_LastCachedReadTokens - g_LastCacheWriteTokens;
                    UI::SetTooltip(
                        "Prompt cache (last request)\n"
                        "cached read: " + FormatTokenCount(g_LastCachedReadTokens) + " input tokens served from cache (cheap)\n"
                        "cache write: " + FormatTokenCount(g_LastCacheWriteTokens) + " input tokens newly written (Anthropic bills 1.25x)\n"
                        "fresh input: " + FormatTokenCount(Math::Max(fresh, 0)) + " input tokens billed at full price"
                    );
                }
                if (labels[i] == "In" && UI::IsItemHovered()) {
                    UI::SetTooltip("Input tokens of the last request (all input, incl. cached)");
                }
            }

            if (compacted) {
                UI::Dummy(vec2(0, 2));
                vec2 badgePos = UI::GetCursorPos();
                float badgeAbsX = UI::GetWindowPos().x + badgePos.x;
                float badgeAbsY = UI::GetWindowPos().y + badgePos.y - UI::GetScrollY();
                string txt = Icons::Compress + "  Compacted";
                vec2 sz = UI::MeasureString(txt);
                float padX = 6;
                float padY = 2;
                auto dl = UI::GetWindowDrawList();
                dl.AddRectFilled(
                    vec4(badgeAbsX, badgeAbsY, sz.x + padX * 2, sz.y + padY * 2),
                    vec4(accentCol.x, accentCol.y, accentCol.z, 0.18),
                    3
                );
                UI::Dummy(vec2(padX, 0));
                UI::SameLine(0, 0);
                UI::PushStyleColor(UI::Col::Text, accentCol);
                UI::Text(txt);
                UI::PopStyleColor();
                UI::Dummy(vec2(0, padY));
            }

            DrawLifetimeStats(labelCol, sepCol);
        }

        UI::PopStyleVar(2);
    }

    void DrawLifetimeStats(const vec4 &in labelCol, const vec4 &in sepCol) {
        UI::Dummy(vec2(0, 6));

        vec4 headerCol = vec4(0.40, 0.45, 0.52, 1.0);
        vec4 ruleCol = vec4(0.40, 0.45, 0.52, 0.28);
        UI::PushStyleColor(UI::Col::Text, headerCol);
        UI::Text("L I F E T I M E");
        UI::PopStyleColor();
        vec4 hRect = UI::GetItemRect();
        auto dl = UI::GetWindowDrawList();
        float ruleY = hRect.y + hRect.w * 0.58;
        float ruleX1 = hRect.x + hRect.z + 10;
        float ruleX2 = UI::GetWindowPos().x + UI::GetWindowContentRegionWidth() - 4;
        if (ruleX2 > ruleX1 + 10) dl.AddLine(vec2(ruleX1, ruleY), vec2(ruleX2, ruleY), ruleCol, 1);
        UI::Dummy(vec2(0, 2));

        // Lifetime cached input: shown once any cache activity has ever been
        // recorded; hidden otherwise so cache-less installs keep a tight row.
        bool lifetimeHasCache = AgentStats::S_TotalCachedReadTokens > 0 || AgentStats::S_TotalCacheWriteTokens > 0;
        array<string> labels = {"In", "Cached", "Out", "Msgs", "Turns", "Steps", "Placed", "Removed"};
        if (!lifetimeHasCache) labels.RemoveAt(1);
        array<string> values = {
            FormatTokenCount(AgentStats::S_TotalInputTokens),
            FormatTokenCount(AgentStats::S_TotalCachedReadTokens + AgentStats::S_TotalCacheWriteTokens),
            FormatTokenCount(AgentStats::S_TotalOutputTokens),
            "" + AgentStats::S_TotalUserMessages,
            "" + AgentStats::S_TotalTurns,
            "" + AgentStats::S_TotalSteps,
            "" + AgentStats::S_TotalBlocksPlaced,
            "" + AgentStats::S_TotalBlocksRemoved
        };
        if (!lifetimeHasCache) values.RemoveAt(1);

        vec2 winPos = UI::GetWindowPos();
        float rightEdge = winPos.x + UI::GetWindowSize().x - 16;
        float sepW = UI::MeasureString("\xC2\xB7").x + 8;
        for (uint i = 0; i < labels.Length; i++) {
            float chunkW = UI::MeasureString(labels[i]).x + 4 + UI::MeasureString(values[i]).x;
            if (i > 0) {
                vec4 prev = UI::GetItemRect();
                float prevRight = prev.x + prev.z;
                if (prevRight + sepW + chunkW < rightEdge) {
                    UI::SameLine();
                    DrawInlineSep(sepCol);
                    UI::SameLine();
                }
            }
            DrawInlineStat(labels[i], values[i], labelCol);
            if (lifetimeHasCache && labels[i] == "Cached" && UI::IsItemHovered()) {
                UI::SetTooltip(
                    "Lifetime cached input\n"
                    "cached read: " + FormatTokenCount(AgentStats::S_TotalCachedReadTokens) + " input tokens served from cache (cheap)\n"
                    "cache write: " + FormatTokenCount(AgentStats::S_TotalCacheWriteTokens) + " input tokens newly written (Anthropic bills 1.25x)"
                );
            }
        }
    }

    void DrawStatRow(const string &in label, const string &in value, const vec4 &in color) {
        UI::PushStyleColor(UI::Col::Text, color);
        UI::Text(label + ":");
        UI::PopStyleColor();
        UI::SameLine();
        UI::Text(value);
    }

    void DrawInlineStat(const string &in label, const string &in value, const vec4 &in labelColor) {
        UI::PushStyleColor(UI::Col::Text, labelColor);
        UI::Text(label);
        UI::PopStyleColor();
        UI::SameLine(0, 4);
        UI::PushFont(UI::Font::DefaultMono);
        UI::Text(value);
        UI::PopFont();
    }

    void DrawInlineSep(const vec4 &in color) {
        UI::PushStyleColor(UI::Col::Text, color);
        UI::Text("\xC2\xB7");
        UI::PopStyleColor();
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
        UI::PushStyleColor(UI::Col::Header, vec4(0.08, 0.09, 0.11, 1.0));
        UI::PushStyleColor(UI::Col::HeaderHovered, vec4(0.12, 0.14, 0.17, 1.0));
        UI::PushStyleColor(UI::Col::HeaderActive, vec4(0.16, 0.19, 0.23, 1.0));
        UI::PushStyleColor(UI::Col::Text, vec4(0.55, 0.60, 0.68, 1.0));
        bool open = UI::CollapsingHeader(label);
        UI::PopStyleColor(4);
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
        UI::PushStyleColor(UI::Col::Border, vec4(0.30, 0.33, 0.38, 0.85));
        UI::PushStyleColor(UI::Col::ScrollbarBg, vec4(0.05, 0.06, 0.08, 1.0));
        UI::PushStyleColor(UI::Col::ScrollbarGrab, vec4(0.40, 0.44, 0.50, 0.28));
        UI::PushStyleColor(UI::Col::ScrollbarGrabHovered, vec4(0.55, 0.60, 0.68, 0.48));
        UI::PushStyleColor(UI::Col::ScrollbarGrabActive, vec4(0.70, 0.75, 0.82, 0.66));

        UI::PushStyleVar(UI::StyleVar::WindowPadding, vec2(12, 10));
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(8, 5));
        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(8, 6));
        UI::PushStyleVar(UI::StyleVar::FrameRounding, 4);
        UI::PushStyleVar(UI::StyleVar::WindowRounding, 5);
        UI::PushStyleVar(UI::StyleVar::GrabRounding, 3);
        // Suppress ImGui's built-in 1px border — BorderEffect::Swirl /
        // BorderEffect::Static draw our own border inside the window scope
        // so it respects z-order with overlapping windows.
        UI::PushStyleVar(UI::StyleVar::WindowBorderSize, 0);
    }

    void PopTheme() {
        UI::PopStyleVar(7);
        UI::PopStyleColor(22);
    }

    // Route heuristic for the startup suggestion: the map has meaningful
    // placed content already (any blocks at all reads as "route exists" for
    // our purposes — an empty map suggests sampling, a built one suggests
    // scenery around existing work).
    bool MapHasRoute() {
        auto app = cast<CGameManiaPlanet>(GetApp());
        auto editor = app !is null ? cast<CGameCtnEditorFree>(app.Editor) : null;
        if (editor is null || editor.Challenge is null) return false;
        return editor.Challenge.Blocks.Length > 8;
    }

    void Render() {
        if (!AgentSettings::S_ShowWindow) return;

        UI::SetNextWindowSize(int(g_WindowWidth), int(g_WindowHeight), UI::Cond::FirstUseEver);
        UI::SetNextWindowPos(int(g_WindowPos.x), int(g_WindowPos.y), UI::Cond::FirstUseEver);
        UI::SetNextWindowSizeConstraints(340, 360, 1600, 1400);

        PushTheme();

        int winFlags = UI::WindowFlags::NoCollapse;
        if (UI::Begin(Icons::Rocket + "  TM Agent", AgentSettings::S_ShowWindow, winFlags)) {
            auto app = cast<CGameManiaPlanet>(GetApp());
            auto editor = app !is null ? cast<CGameCtnEditorFree>(app.Editor) : null;

            if (editor is null && !g_DemoMode) {
                DrawNotInEditor();
            } else {
                DrawHeader();
                DrawContextStats();
                UI::Separator();
                DrawMessages();
                DrawInput();
                DrawBottomToolbar();
            }

            auto winSize = UI::GetWindowSize();
            g_WindowWidth = winSize.x;
            g_WindowHeight = winSize.y;
            g_WindowPos = UI::GetWindowPos();

            if (g_Status.InFlight) {
                BorderEffect::Swirl();
            } else {
                BorderEffect::Static();
            }
        }
        UI::End();

        DrawInteractivePopouts();

        PopTheme();

        if (g_ShowSettings) {
            RenderSettingsWindow();
        }
    }

    void DrawCustomTitleBar() {
        vec4 amber = vec4(0.95, 0.65, 0.15, 1.0);
        vec4 titleCol = vec4(0.78, 0.82, 0.88, 1.0);
        vec4 ruleCol = vec4(0.20, 0.23, 0.28, 1.0);

        float barH = 20;
        vec2 winPos = UI::GetWindowPos();
        float winW = UI::GetWindowSize().x;
        vec2 cur = UI::GetCursorPos();
        float absY = winPos.y + cur.y;
        auto dl = UI::GetWindowDrawList();

        dl.AddLine(vec2(winPos.x + 8, absY + barH), vec2(winPos.x + winW - 8, absY + barH), ruleCol, 1);

        float glyphY = absY + barH * 0.5 - 2.5;
        dl.AddRectFilled(vec4(winPos.x + 10, glyphY, 5, 5), amber, 1);

        dl.AddText(vec2(winPos.x + 22, absY + 3), titleCol, "TM AGENT");

        float closeSize = 14;
        UI::SetCursorPos(vec2(winW - closeSize - 8, cur.y + (barH - closeSize) * 0.5));
        UI::PushStyleColor(UI::Col::Button, vec4(0, 0, 0, 0));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(0.96, 0.32, 0.30, 0.30));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(0.96, 0.32, 0.30, 0.50));
        UI::PushStyleColor(UI::Col::Text, vec4(0.50, 0.54, 0.60, 1.0));
        UI::PushStyleVar(UI::StyleVar::FramePadding, vec2(2, 1));
        if (UI::Button(Icons::Times + "##close", vec2(closeSize, closeSize))) {
            AgentSettings::S_ShowWindow = false;
        }
        UI::PopStyleVar();
        UI::PopStyleColor(4);

        UI::SetCursorPos(vec2(cur.x, cur.y + barH + 2));
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

    // Unified slow breathing cycle used across the waiting-state UI so
    // every pulsing element (icon badge, ornament, etc) breathes together.
    // Returns 0..1 with a ~6s period. `periodSec` lets callers retune locally.
    float BreathPulse(float periodSec = 6.0) {
        float t = float(Time::Now) / 1000.0;
        float omega = Math::PI * 2.0 / periodSec;
        return 0.5 - 0.5 * Math::Cos(t * omega);
    }

    // Interpolate color.a against a pulse-weighted range (base..base+amp).
    vec4 PulsedAlpha(const vec4 &in c, float base, float amp, float pulse) {
        return vec4(c.x, c.y, c.z, base + amp * pulse);
    }

    void DrawCenteredOrnament(float width, const vec4 &in color) {
        vec2 winPos = UI::GetWindowPos();
        float winW = UI::GetWindowSize().x;
        vec2 cur = UI::GetCursorPos();
        float y = winPos.y + cur.y - UI::GetScrollY();
        float leftX = winPos.x + (winW - width) * 0.5;
        float midX = winPos.x + winW * 0.5;
        auto dl = UI::GetWindowDrawList();

        float pulse = BreathPulse();
        vec4 lineCol = vec4(color.x, color.y, color.z, color.w * (0.55 + 0.45 * pulse));
        vec4 dotCol  = PulsedAlpha(color, 0.35, 0.55, pulse);
        float dotR = 2.0 + 1.2 * pulse;

        dl.AddLine(vec2(leftX, y + 4), vec2(midX - 8, y + 4), lineCol, 1);
        dl.AddLine(vec2(midX + 8, y + 4), vec2(leftX + width, y + 4), lineCol, 1);
        vec4 glowCol = PulsedAlpha(color, 0.08, 0.12, pulse);
        dl.AddCircleFilled(vec2(midX, y + 4), dotR + 3.0, glowCol);
        dl.AddCircleFilled(vec2(midX, y + 4), dotR, dotCol);
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

        // Soft breathing halo behind the badge — many thin concentric
        // rounded rects with decreasing alpha, summing to a continuous
        // glow rather than visible discrete rings. Expands on pulse peak.
        float pulse = BreathPulse();
        float cx = absX + size * 0.5;
        float cy = absY + size * 0.5;
        int rings = 10;
        float maxExtra = 14.0 + 10.0 * pulse;
        for (int i = rings; i >= 1; i--) {
            float f = float(i) / float(rings);
            float ring = size + f * maxExtra * 2.0;
            float a = (0.035 + 0.04 * pulse) * (1.0 - f);
            vec4 haloCol = vec4(strokeColor.x, strokeColor.y, strokeColor.z, a);
            float r = 8.0 + f * 14.0;
            dl.AddRectFilled(vec4(cx - ring * 0.5, cy - ring * 0.5, ring, ring), haloCol, r);
        }

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
        // Subtract our pushed WindowPadding.y (10) so the accent sits flush
        // with the bottom of the titlebar instead of floating below it.
        float y = winPos.y + cur.y - UI::GetScrollY() - 10;
        dl.AddRectFilledMultiColor(vec4(winPos.x, y, winSize.x, 2), accent, accentFade, accentFade, accent);
        UI::Dummy(vec2(0, 6));
    }

    // Shared settings gear button. Draws a square icon button with the gear
    // glyph centered via drawlist — ImGui's built-in text centering with
    // asymmetric FramePadding(8,5) and the cog glyph's metrics lands the
    // icon slightly off-center, so we compute the position manually.
    void DrawSettingsButton(const string &in idSuffix) {
        float size = UI::GetFrameHeight();
        vec2 btnMin = UI::GetCursorScreenPos();
        bool clicked = UI::Button("##settings_" + idSuffix, vec2(size, size));
        vec2 iconSize = UI::MeasureString(Icons::Cog);
        vec4 textCol = UI::GetStyleColor(UI::Col::Text);
        UI::GetWindowDrawList().AddText(
            vec2(
                btnMin.x + (size - iconSize.x) * 0.5,
                btnMin.y + (size - iconSize.y) * 0.5
            ),
            textCol,
            Icons::Cog
        );
        if (clicked) g_ShowSettings = !g_ShowSettings;
        if (UI::IsItemHovered()) UI::SetTooltip("Settings");
    }

    void StartProviderTest() {
        if (g_TestRunning) return;
        g_TestRunning = true;
        g_TestResult = "Testing…";
        g_TestColor = vec4(0.98, 0.70, 0.22, 1.0);
        // Coro lives at global scope (see below) — calling imported funcs
        // like AiApi::OpenAI_Complete through a namespace-scoped coro
        // entrypoint produced "Unbound function called" at runtime.
        startnew(::ProviderTestCoro);
    }

    void DrawNotInEditor() {
        vec4 headingCol = vec4(0.78, 0.82, 0.88, 1.0);
        // Slow breath cycle — unified across waiting-state elements
        // (icon badge, ornament dot) via BreathPulse() so they all
        // inhale/exhale together, matching the wave across the title.
        float pulse = BreathPulse();
        vec4 amber = vec4(0.95, 0.65, 0.15, 1.0);
        vec4 badgeFill   = PulsedAlpha(amber, 0.06, 0.06, pulse);
        vec4 badgeStroke = PulsedAlpha(amber, 0.18, 0.18, pulse);
        vec4 iconColor   = PulsedAlpha(amber, 0.72, 0.20, pulse);

        // Floating gear, top-right. Save/restore cursor so the rest of the
        // waiting layout flows from the top unchanged.
        vec2 savedCursor = UI::GetCursorPos();
        float gearSize = UI::GetFrameHeight();
        UI::SetCursorPos(vec2(UI::GetWindowSize().x - gearSize - 12, savedCursor.y));
        DrawSettingsButton("wait");
        UI::SetCursorPos(savedCursor);

        DrawAmberTitleAccent();

        float availH = UI::GetContentRegionAvail().y;
        UI::Dummy(vec2(0, Math::Max(availH * 0.08, 12.0)));

        DrawIconBadge(56, Icons::MapO, badgeFill, badgeStroke, iconColor);

        UI::Dummy(vec2(0, 22));

        UI::PushFont(UI::Font::DefaultBold);
        UI::PushFontSize(18);
        TextEffect::WaveCentered(
            "WAITING FOR EDITOR",
            -1.0,
            headingCol,
            vec4(1.00, 0.88, 0.45, 1.0)
        );
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

        // Ornament sits ~18px below the breadcrumb as a content
        // terminator rather than floating mid-gap — keeps the content
        // block visually tight. Footer anchors 22px above the bottom.
        UI::Dummy(vec2(0, 18));
        DrawCenteredOrnament(120, vec4(0.95, 0.65, 0.15, 0.30));

        float afterOrnament = UI::GetContentRegionAvail().y;
        if (afterOrnament > 24) {
            UI::Dummy(vec2(0, afterOrnament - 22));
        }
        DrawBrandFooter();
    }

    string TruncateToWidth(const string &in s, float maxW) {
        if (UI::MeasureString(s).x <= maxW) return s;
        string ell = "\xE2\x80\xA6";
        string result = s;
        while (result.Length > 0 && UI::MeasureString(result + ell).x > maxW) {
            result = result.SubStr(0, result.Length - 1);
        }
        return result + ell;
    }

    void DrawStatusPill(const string &in label, const vec4 &in color) {
        vec2 pad = vec2(7, 2);
        vec2 textSize = UI::MeasureString(label);
        vec2 pillSize = textSize + pad * 2;
        float framePadY = 5;
        vec2 cur = UI::GetCursorPos();
        vec2 abs = UI::GetWindowPos() + cur - vec2(0, UI::GetScrollY());
        float pillY = abs.y + framePadY - pad.y;
        auto dl = UI::GetWindowDrawList();
        vec4 fill = vec4(color.x, color.y, color.z, 0.22);
        dl.AddRectFilled(vec4(abs.x, pillY, pillSize.x, pillSize.y), fill, pillSize.y * 0.5);
        dl.AddText(vec2(abs.x + pad.x, pillY + pad.y), color, label);
        UI::Dummy(vec2(pillSize.x + 2, pillSize.y + framePadY));
    }

    void DrawHeader() {
        vec4 idleColor = vec4(0.00, 0.82, 0.95, 1.0);
        vec4 runColor = vec4(0.98, 0.70, 0.22, 1.0);
        vec4 errColor = vec4(0.96, 0.32, 0.30, 1.0);

        StatusKind kind = g_Status.Kind;
        if (kind == StatusKind::Error) {
            string pillLabel = Icons::ExclamationTriangle + "  " + g_Status.Label;
            DrawStatusPill(pillLabel, errColor);
        } else if (kind == StatusKind::Idle) {
            DrawStatusPill("IDLE", idleColor);
        } else if (g_Status.InFlight) {
            DrawStatusPill(g_Status.Label, runColor);
            UI::SameLine();
            UI::AlignTextToFramePadding();
            string thinking = kind == StatusKind::CallingLLM ? "calling llm" : "thinking";
            TextEffect::DoubleWave(
                thinking,
                -1.0,
                vec4(0.40, 0.44, 0.50, 1.0),
                vec4(0.98, 0.70, 0.22, 1.0),
                vec4(0.00, 0.82, 0.95, 1.0),
                1.0, -1.0,
                2.0,
                5.0, 7.0, 0.0
            );
        } else {
            DrawStatusPill(g_Status.Label, errColor);
        }

        UI::SameLine();
        UI::AlignTextToFramePadding();
        UI::PushFont(UI::Font::DefaultMono);
        UI::PushStyleColor(UI::Col::Text, vec4(0.55, 0.60, 0.68, 1.0));
        string modelText = CurrentProviderLabel() + " / " + CurrentModelLabel();
        bool showTurn = g_CurrentTurn > 0 || g_StepCount > 0;
        string turnText = showTurn ? ("t" + g_CurrentTurn + "\xC2\xB7s" + g_StepCount) : "";
        string combined = showTurn ? (modelText + "   " + turnText) : modelText;
        vec2 combinedSize = UI::MeasureString(combined);
        float rightEdge = UI::GetWindowSize().x - 12;
        float cursorX = UI::GetCursorPos().x;
        float availableW = rightEdge - cursorX;
        if (combinedSize.x <= availableW) {
            UI::SetCursorPosX(rightEdge - combinedSize.x);
            UI::Text(combined);
        } else {
            UI::Text(TruncateToWidth(modelText, availableW));
        }
        UI::PopStyleColor();
        UI::PopFont();

        // Second header row: follow-cam selector right-aligned.
        DrawFollowCamSelector();

        UI::Dummy(vec2(0, 3));
        UI::Separator();
        UI::Dummy(vec2(0, 5));
    }

    // Last-known pill rects (screen coords) from the most recent
    // DrawFollowCamSelector pass — lets the driver verify hit-box layout.
    Json::Value@ g_LastPillRects = Json::Array();

    Json::Value@ GetLastPillRects() {
        return g_LastPillRects;
    }

    // Segmented button group, right-aligned in the current window. Returns the
    // clicked segment index, or -1. Segment IDs are uniquified (tag + index):
    // duplicate ##-ids make ImGui collapse hit boxes onto the first item.
    // prefixIcon (e.g. Icons::VideoCamera, or "" for none) is drawn before the
    // segments as a non-interactive label. When rectsOut is given it receives
    // per-segment screen rects (x,y,w,h) for hit-box verification.
    int DrawButtonGroup(const string &in tag, string[] &in labels, int active, const string &in prefixIcon, Json::Value@ rectsOut = null) {
        float iconW = prefixIcon.Length > 0 ? UI::MeasureString(prefixIcon).x + 6 : 0;
        float rowW = iconW;
        for (uint i = 0; i < labels.Length; i++) {
            rowW += UI::MeasureString(labels[i]).x + 14 /* item pad */ + 4 /* spacing */;
        }
        float rightEdge = UI::GetWindowSize().x - 12;
        UI::SetCursorPosX(Math::Max(8.0, rightEdge - rowW));
        UI::AlignTextToFramePadding();

        if (prefixIcon.Length > 0) {
            UI::PushStyleColor(UI::Col::Text, vec4(0.55, 0.60, 0.68, 1.0));
            UI::Text(prefixIcon);
            UI::PopStyleColor();
        }

        int clicked = -1;
        for (uint i = 0; i < labels.Length; i++) {
            if (i > 0) UI::SameLine(0, 4);
            else if (prefixIcon.Length > 0) UI::SameLine(0, 6);
            bool isActive = int(i) == active;
            // Manual hit rect: Openplanet's Selectable takes no explicit
            // size arg, and its default SpanAvailWidth stretches every item
            // to the window's right edge (the first pill would swallow the
            // row). Dummy() reserves exactly the label width; hover/click are
            // read from the item state like the eye button does.
            vec2 labelSz = UI::MeasureString(labels[i]);
            float rowH = UI::GetFrameHeight();
            // Height matters: a zero-height Dummy has an empty hit rect and
            // IsItemHovered never fires (the drawn text still rendered, which
            // is why the pills looked fine but ignored clicks).
            UI::Dummy(vec2(labelSz.x + 10, rowH));
            bool hover = UI::IsItemHovered();
            if (hover && UI::IsMouseClicked(UI::MouseButton::Left)) clicked = int(i);
            vec4 itemRect = UI::GetItemRect();
            vec4 hitRect = vec4(itemRect.x, itemRect.y, labelSz.x + 10, rowH);
            if (rectsOut !is null) {
                Json::Value@ e = Json::Object();
                e["i"] = int(i);
                e["label"] = labels[i];
                e["x"] = hitRect.x;
                e["y"] = hitRect.y;
                e["w"] = hitRect.z;
                e["h"] = hitRect.w;
                rectsOut.Add(e);
            }
            vec4 col = isActive ? vec4(0.00, 0.82, 0.95, 1.0)
                : hover ? vec4(0.62, 0.66, 0.72, 1.0)
                : vec4(0.42, 0.46, 0.52, 0.9);
            UI::GetWindowDrawList().AddText(
                vec2(hitRect.x + 5, hitRect.y + (hitRect.w - labelSz.y) * 0.5),
                col, labels[i]);
        }
        return clicked;
    }

    // Follow-cam mode pills: [icon off steps swing cine] on their own header
    // row via the shared button-group helper, right-aligned so all four are
    // always visible and clickable.
    void DrawFollowCamSelector() {
        if (!AgentSettings::S_FollowCamEnabled) return;

        FollowCam::FollowMode[] order = {
            FollowCam::FollowMode::Off,
            FollowCam::FollowMode::Steps,
            FollowCam::FollowMode::Swing,
            FollowCam::FollowMode::Cinematic
        };
        string[] labels = { "off", "steps", "swing", "cine" };
        Json::Value@ rects = Json::Array();
        int clicked = DrawButtonGroup("followmode", labels, int(FollowCam::g_Mode), Icons::VideoCamera, rects);
        @g_LastPillRects = rects;
        if (clicked >= 0) {
            FollowCam::SetMode(order[clicked]);
            AgentSettings::S_FollowCamMode = FollowCam::ModeToString(order[clicked]);
        }
        if (UI::IsItemHovered()) {
            UI::SetTooltip("Follow cam — moves the camera to watch the agent while it works");
        }
    }

    void DrawMessages() {
        // Reserve just enough for input (84 + borders), send button pad,
        // and the bottom toolbar (~40). Keeps the chat area maximal so
        // the window bottom edge isn't wasted as dead space.
        float bottomReserve = 156;

        UI::PushStyleColor(UI::Col::ChildBg, vec4(0.035, 0.042, 0.055, 1.0));
        UI::PushStyleVar(UI::StyleVar::ChildRounding, 6);
        UI::PushStyleVar(UI::StyleVar::ChildBorderSize, 0);
        UI::PushStyleVar(UI::StyleVar::WindowPadding, vec2(14, 12));

        UI::BeginChild("##messages", vec2(0, -bottomReserve), false, UI::WindowFlags::AlwaysVerticalScrollbar);

        if (g_Messages.Length == 0) {
            DrawIdlePlaceholder();
        } else {
            // Virtual-scroll cull. ListClipper wants uniform row height;
            // our messages have wildly variable heights (markdown wrap,
            // expanded JSON, compact chips) so we roll our own: cache each
            // message's measured advance, then on later frames advance the
            // message's measured advance, then on later frames advance the
            // cursor with a zero-width Dummy sized to the cached height.
            float scrollY = g_ForceScrollY >= 0 ? g_ForceScrollY : UI::GetScrollY();
            float viewH = UI::GetWindowSize().y;
            // One viewport of over-render above/below smooths fast scrolls
            // and keeps near-edge items ready to receive clicks.
            float viewTop = scrollY - viewH;
            float viewBot = scrollY + viewH * 2.0;
            float availW = UI::GetContentRegionAvail().x;

            for (uint i = 0; i < g_Messages.Length; i++) {
                auto @msg = g_Messages[i];
                bool tightTop = i > 0
                    && msg.type == MsgType::ToolResult
                    && g_Messages[i-1].type == MsgType::ToolCall
                    && g_Messages[i-1].toolName == msg.toolName;
                // Call followed by its paired result: render both with
                // zero inter-item spacing so they read as one call→result
                // unit rather than two independent chips separated by air.
                bool tightBottom = i + 1 < g_Messages.Length
                    && msg.type == MsgType::ToolCall
                    && g_Messages[i+1].type == MsgType::ToolResult
                    && g_Messages[i+1].toolName == msg.toolName;

                float preY = UI::GetCursorPos().y;
                bool canCull = msg.cachedHeight > 0
                    && msg.cachedForWidth == availW
                    && msg.cachedExpanded == msg.expanded;
                bool offScreen = canCull
                    && (preY + msg.cachedHeight < viewTop || preY > viewBot);

                if (offScreen) {
                    // Reproduce the exact cursor advance without invoking
                    // any layout or drawlist work for this message.
                    // A bare SetCursorPos here trips ImGui's
                    // ErrorCheckUsingSetCursorPosToExtendParentBoundaries
                    // assert at EndChild when the culled tail extends the
                    // child's content bounds with no item submitted after
                    // it (crash observed 2026-08-16, log line 19533).
                    // Dummy submits an item (clears DC.IsSetPos) and
                    // advances h + ItemSpacing.y, so we size it to land
                    // exactly where the draw path leaves the cursor.
                    vec2 spacing = UI::GetStyleVarVec2(UI::StyleVar::ItemSpacing);
                    float advance = msg.cachedHeight > spacing.y
                        ? msg.cachedHeight - spacing.y
                        : 0;
                    UI::Dummy(vec2(0, advance));
                } else {
                    if (tightBottom) UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(UI::GetStyleVarVec2(UI::StyleVar::ItemSpacing).x, 0));
                    DrawMessage(msg, tightTop, tightBottom);
                    if (tightBottom) UI::PopStyleVar();

                    float postY = UI::GetCursorPos().y;
                    msg.cachedHeight = postY - preY;
                    msg.cachedForWidth = availW;
                    msg.cachedExpanded = msg.expanded;
                }
            }
            if (g_PendingScrollBottom) {
                UI::SetScrollHereY(1.0f);
                g_PendingScrollBottom = false;
            }
        }

        UI::EndChild();

        UI::PopStyleVar(3);
        UI::PopStyleColor();
    }

    void DrawIdlePlaceholder() {
        vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);

        UI::Dummy(vec2(0, 12));

        vec2 cardStart = UI::GetCursorPos();
        float cardX = UI::GetWindowPos().x + cardStart.x;
        float cardY = UI::GetWindowPos().y + cardStart.y - UI::GetScrollY();
        auto dl = UI::GetWindowDrawList();

        UI::Indent(14);
        UI::PushStyleColor(UI::Col::Text, vec4(0.88, 0.90, 0.93, 1.0));
        UI::PushFont(UI::Font::DefaultBold);
        UI::Text("How can I help?");
        UI::PopFont();
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 4));
        UI::PushStyleColor(UI::Col::Text, vec4(0.65, 0.70, 0.76, 1.0));
        UI::TextWrapped("Inspect the map, find items, and place blocks at the cursor.");
        UI::PopStyleColor();
        UI::Dummy(vec2(0, 12));

        // Section label with trailing hairline rule — groups the
        // examples beneath it visually without heavy chrome.
        {
            vec4 labelCol = vec4(0.40, 0.45, 0.52, 1.0);
            vec4 ruleCol = vec4(0.40, 0.45, 0.52, 0.28);
            UI::PushStyleColor(UI::Col::Text, labelCol);
            UI::Text("T R Y");
            UI::PopStyleColor();
            vec4 labelRect = UI::GetItemRect();
            auto dl2 = UI::GetWindowDrawList();
            float ruleY = labelRect.y + labelRect.w * 0.58;
            float ruleX1 = labelRect.x + labelRect.z + 10;
            float ruleX2 = UI::GetWindowPos().x + UI::GetWindowContentRegionWidth() - 4;
            if (ruleX2 > ruleX1 + 10) {
                dl2.AddLine(vec2(ruleX1, ruleY), vec2(ruleX2, ruleY), ruleCol, 1);
            }
        }
        UI::Dummy(vec2(0, 4));

        DrawExampleLine(accent, "What's on the current map?");
        DrawExampleLine(accent, "Place a start block at the cursor.");
        DrawExampleLine(accent, "Search the inventory for 'dirt'.");
        DrawExampleLine(accent, "Extend this into a classic Trackmania 01-style track.");
        string sceneryLabel = MapHasRoute()
            ? "Sample scenery around the existing route."
            : "Sample 4–8 scenery islands on this map.";
        DrawExampleLine(accent, sceneryLabel, StartupSuggestion::ComposerPrompt(MapHasRoute()));
        DrawExampleLine(accent, "Check all checkpoints for double respawnability.");
        UI::Unindent(14);

        vec2 cardEnd = UI::GetCursorPos();
        float cardH = cardEnd.y - cardStart.y;
        dl.AddRectFilled(vec4(cardX + 2, cardY, 3, cardH - 4), accent, 1);
    }

    void DrawExampleLine(const vec4 &in accent, const string &in example, const string &in fill = "") {
        UI::PushStyleColor(UI::Col::Header, vec4(accent.x, accent.y, accent.z, 0.10));
        UI::PushStyleColor(UI::Col::HeaderHovered, vec4(accent.x, accent.y, accent.z, 0.18));
        UI::PushStyleColor(UI::Col::HeaderActive, vec4(accent.x, accent.y, accent.z, 0.28));
        UI::PushStyleColor(UI::Col::Text, vec4(0.78, 0.82, 0.88, 1.0));
        string label = "  " + Icons::AngleRight + "  " + example + "##ex-" + example;
        if (UI::Selectable(label, false)) {
            g_InputText = fill.Length > 0 ? fill : example;
        }
        UI::PopStyleColor(4);
    }

    void DrawBubble(const string &in label, const vec4 &in accent, const string &in body, bool markdown = false) {
        float padX = 10;
        float padY = 8;
        float barW = 2;
        float labelGap = 2;

        vec2 cur = UI::GetCursorPos();
        float absX = UI::GetWindowPos().x + cur.x;
        float absYStart = UI::GetWindowPos().y + cur.y - UI::GetScrollY();
        float availW = UI::GetContentRegionAvail().x;
        auto dl = UI::GetWindowDrawList();

        UI::Dummy(vec2(0, padY));
        UI::Indent(padX + barW);
        float wrapX = UI::GetCursorPos().x + availW - padX * 2 - barW;
        UI::PushTextWrapPos(wrapX);

        vec4 labelCol = vec4(accent.x, accent.y, accent.z, 0.72);
        UI::PushStyleColor(UI::Col::Text, labelCol);
        UI::Text(label);
        UI::PopStyleColor();

        UI::Dummy(vec2(0, labelGap));

        if (markdown) {
            UI::Markdown(body);
        } else {
            UI::TextWrapped(body);
        }

        UI::PopTextWrapPos();
        UI::Unindent(padX + barW);
        UI::Dummy(vec2(0, padY - 4));

        vec2 curEnd = UI::GetCursorPos();
        float absYEnd = UI::GetWindowPos().y + curEnd.y - UI::GetScrollY();

        vec4 bg = vec4(accent.x, accent.y, accent.z, 0.06);
        dl.AddRectFilled(vec4(absX, absYStart, availW, absYEnd - absYStart - 4), bg, 2);
        dl.AddRectFilled(vec4(absX, absYStart, barW, absYEnd - absYStart - 4), accent, 1);
    }

    bool ToolResultLooksSuccessful(const string &in body) {
        Json::Value@ parsed = Json::Parse(body);
        return parsed !is null && IsToolResultSuccess(parsed);
    }

    void DrawMessage(Message@ msg, bool tightTop = false, bool tightBottom = false) {
        vec4 userAccent = vec4(0.55, 0.75, 1.00, 1.0);
        vec4 agentAccent = vec4(0.00, 0.82, 0.95, 1.0);
        vec4 toolCallAccent = vec4(0.78, 0.56, 1.00, 1.0);
        vec4 toolOkAccent = vec4(0.40, 0.82, 0.55, 1.0);
        vec4 toolErrAccent = vec4(0.96, 0.38, 0.34, 1.0);

        if (msg.type == MsgType::User) {
            DrawBubble("YOU", userAccent, msg.content);
        } else if (msg.type == MsgType::Assistant) {
            DrawBubble("AGENT", agentAccent, msg.content, true);
        } else if (msg.type == MsgType::Error) {
            // Provider/tool errors: distinct red bubble so failures never read
            // as normal chat output.
            DrawBubble(Icons::ExclamationTriangle + "  ERROR", toolErrAccent, msg.content, false);
        } else if (msg.type == MsgType::ToolCall) {
            // "↗ ToolName" reads as "outgoing call" at a glance.
            string label = Icons::ArrowRight + "  " + msg.toolName;
            DrawToolChip(msg, label, msg.content, toolCallAccent, false, false, tightBottom);
        } else if (msg.type == MsgType::ToolResult) {
            bool success = ToolResultLooksSuccessful(msg.content);
            vec4 accent = success ? toolOkAccent : toolErrAccent;
            // Paired result (follows same-tool call): drop the repeated
            // tool name, use a status glyph so the eye chains call→result.
            string label;
            if (tightTop) {
                label = success ? Icons::Check : Icons::Times;
            } else {
                label = (success ? Icons::Check : Icons::Times) + "  " + msg.toolName;
            }
            DrawToolChip(msg, label, msg.content, accent, tightTop, tightTop, false);
        } else if (msg.type == MsgType::System) {
            DrawColoredText(vec4(0.50, 0.54, 0.60, 1.0), msg.content);
            DrawSpacing();
        } else if (msg.type == MsgType::Interactive) {
            DrawInteractiveCard(msg);
        }
    }

    void SubmitSurvey(Interactive::Survey@ s) {
        if (s is null || s.answered) return;
        string ans = Interactive::FormatSurveyAnswer(s);
        if (ans.Length == 0) return;
        Interactive::MarkAnswered(s, ans);
        SendMessage(ans);
    }

    void DrawSurveyBody(Interactive::Survey@ s, const string &in idSuffix) {
        vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);
        UI::TextWrapped(s.question);
        UI::Dummy(vec2(0, 4));
        if (s.answered) {
            UI::TextDisabled("Answered: " + s.answerText);
            return;
        }
        for (uint i = 0; i < s.options.Length; i++) {
            string mark = s.selected[i] ? Icons::CheckSquare : Icons::SquareO;
            if (!s.multiSelect) mark = s.selected[i] ? Icons::DotCircleO : Icons::CircleO;
            string lab = mark + "  " + s.options[i] + "##opt-" + idSuffix + "-" + i;
            if (UI::Selectable(lab, s.selected[i])) {
                Interactive::ToggleOption(s, i);
            }
        }
        UI::Dummy(vec2(0, 4));
        if (UI::Button("Submit##sub-" + idSuffix)) {
            SubmitSurvey(s);
        }
        if (Interactive::WantsPopOut(s)) {
            UI::SameLine();
            if (UI::Button((s.popOutOpen ? "Dock" : "Pop out") + "##pop-" + idSuffix)) {
                s.popOutOpen = !s.popOutOpen;
            }
        }
        UI::SameLine();
        UI::TextDisabled(s.allowFreeText ? "or type a reply below" : "");
    }

    void DrawActionGroups(Interactive::Card@ card) {
        vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);
        if (card.actionsTitle.Length > 0) UI::TextWrapped(card.actionsTitle);
        for (uint i = 0; i < card.groups.Length; i++) {
            auto g = card.groups[i];
            UI::PushID("ag-" + card.id + "-" + i);
            UI::AlignTextToFramePadding();
            UI::Text(g.label);
            UI::SameLine();
            if (g.hasView) {
                if (UI::Button(Icons::Eye + " view##v")) {
                    ToolFocus::FocusOnPos(g.viewPos);
                    ToolFocus::MoveCursorToWorld(g.viewPos);
                }
                if (UI::IsItemHovered()) UI::SetTooltip("Look at this group");
                UI::SameLine();
            }
            if (g.continuePrompt.Length > 0) {
                if (UI::Button("continue##c")) {
                    if (::g_State == STATE_IDLE) {
                        SendMessage(g.continuePrompt);
                    } else {
                        g_InputText = g.continuePrompt;
                    }
                }
                if (UI::IsItemHovered()) UI::SetTooltip(g.continuePrompt);
            }
            UI::PopID();
        }
    }

    void DrawInteractiveCard(Message@ msg) {
        Interactive::Card@ card = Interactive::Find(msg.interactiveId);
        if (card is null) {
            DrawColoredText(vec4(0.50, 0.54, 0.60, 1.0), msg.content);
            DrawSpacing();
            return;
        }
        vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);
        UI::Dummy(vec2(0, 4));
        if (card.kind == "survey" && card.survey !is null) {
            DrawSurveyBody(card.survey, card.id);
        } else {
            DrawActionGroups(card);
        }
        DrawSpacing();
    }

    void DrawInteractivePopouts() {
        for (uint i = 0; i < Interactive::g_Cards.Length; i++) {
            auto card = Interactive::g_Cards[i];
            if (card.kind != "survey" || card.survey is null || !card.survey.popOutOpen) continue;
            UI::SetNextWindowSize(420, 360, UI::Cond::FirstUseEver);
            if (UI::Begin(Icons::QuestionCircle + "  " + card.survey.question, card.survey.popOutOpen)) {
                DrawSurveyBody(card.survey, card.id + "-pop");
            }
            UI::End();
        }
    }

    // Compact chip for tool-call / tool-result rows. Uses UI::Dummy as
    // the layout hit-area then checks IsItemHovered/IsItemClicked after
    // — click detection works on any UI element in Openplanet ImGui, so
    // we don't need InvisibleButton or a styled Button here. Chrome is
    // drawn entirely via drawlist (accent dot, icon, label, dim peek).
    void DrawToolChip(Message@ msg, const string &in label, const string &in body, const vec4 &in accent, bool tightTop = false, bool compact = false, bool tightBottom = false) {
        UI::Dummy(vec2(0, tightTop ? 0 : 2));
        float availW = UI::GetContentRegionAvail().x;
        vec2 cur = UI::GetCursorPos();
        float absX = UI::GetWindowPos().x + cur.x;
        float absY = UI::GetWindowPos().y + cur.y - UI::GetScrollY();
        auto dl = UI::GetWindowDrawList();

        float padX = 10;
        float rowH = UI::GetFrameHeight();

        // Labels (function names) and peeks (first line of JSON) are data,
        // not prose — render in mono so they scan like a code listing.
        UI::PushFont(UI::Font::DefaultMono);

        // Peek is truncated to available row width — recompute only when
        // the width changes, not every frame.
        float peekMaxW = availW - padX * 2 - UI::MeasureString(label).x - 34;
        if (msg.peekForWidth != availW) {
            int nl = body.IndexOf("\n");
            string firstLine = nl >= 0 ? body.SubStr(0, nl) : body;
            string peekBody = firstLine;
            int oi = peekBody.IndexOf("\"output\":");
            if (oi >= 0) {
                peekBody = peekBody.SubStr(oi + 9);
                if (peekBody.StartsWith(" ")) peekBody = peekBody.SubStr(1);
                if (peekBody.StartsWith("{")) peekBody = peekBody.SubStr(1);
                int siblingCut = peekBody.IndexOf("},\"input\":");
                if (siblingCut >= 0) peekBody = peekBody.SubStr(0, siblingCut);
                int successCut = peekBody.IndexOf("},\"success\":");
                if (successCut >= 0) peekBody = peekBody.SubStr(0, successCut);
            }
            msg.cachedPeek = TruncateToWidth(peekBody, peekMaxW);
            msg.peekForWidth = availW;
        }
        string peek = msg.cachedPeek;

        // Dummy reserves the row in the layout; IsItemHovered/Clicked
        // report native interaction state afterwards.
        UI::Dummy(vec2(availW, rowH));
        bool hovered = UI::IsItemHovered();
        float rowMidY = absY + rowH * 0.5;
        // (PlaceBlock/PlaceItem/FocusCamera/...): clicking animates the
        // editor camera there. ToolHasFocusTarget is a cheap name check;
        // position parsing only happens on click.
        bool eyeClicked = false;
        bool hasEye = msg.type == MsgType::ToolCall && ToolFocus::ToolHasFocusTarget(msg.toolName);
        vec4 eyeRect = vec4(0);
        if (hasEye) {
            vec2 eyeSize = UI::MeasureString(Icons::Eye);
            eyeRect = vec4(
                absX + availW - eyeSize.x - 14,
                rowMidY - (eyeSize.y + 4) * 0.5,
                eyeSize.x + 10,
                eyeSize.y + 4
            );
            vec2 mouse = UI::GetMousePos();
            bool eyeHover = mouse.x >= eyeRect.x && mouse.x <= eyeRect.x + eyeRect.z
                && mouse.y >= eyeRect.y && mouse.y <= eyeRect.y + eyeRect.w;
            if (eyeHover) {
                dl.AddRectFilled(eyeRect, vec4(accent.x, accent.y, accent.z, 0.16), 3);
                if (UI::IsMouseClicked(UI::MouseButton::Left)) eyeClicked = true;
            }
            dl.AddText(vec2(eyeRect.x + 5, eyeRect.y + 2), eyeHover ? vec4(accent.x, accent.y, accent.z, 1.0) : vec4(0.55, 0.60, 0.68, 0.9), Icons::Eye);
        }

        if (eyeClicked) {
            string focusErr = ToolFocus::FocusOnToolCall(msg.toolName, msg.content);
            if (focusErr.Length > 0) {
                // Log-before-UI, same as every other chat mutation.
                SessionLog::WriteRecord("system", "view: " + focusErr);
                AddMessage(MsgType::System, "view: " + focusErr);
            }
        } else if (hovered && UI::IsMouseClicked(UI::MouseButton::Left)) {
            msg.expanded = !msg.expanded;
            msg.InvalidateLayout();
        }

        float bgA = hovered ? 0.14 : 0.05;
        vec4 bg = vec4(accent.x, accent.y, accent.z, bgA);
        dl.AddRectFilled(vec4(absX, absY, availW, rowH), bg, 3);
        // Left accent bar ties the row into the bubble family.
        dl.AddRectFilled(vec4(absX, absY, 2, rowH), accent, 1);
        float midY = rowMidY;

        // The label starts with a status glyph (→ / ✓ / ✗) followed by
        // whitespace and optional tool name. Split the label so the
        // glyph renders in accent color while the name stays neutral.
        int sepIx = label.IndexOf("  ");
        string glyph = sepIx >= 0 ? label.SubStr(0, sepIx) : label;
        string labelTail = sepIx >= 0 ? label.SubStr(sepIx + 2) : "";
        float tx = absX + padX;
        vec2 gSize = UI::MeasureString(glyph);
        vec4 glyphCol = vec4(accent.x, accent.y, accent.z, 1.0);
        dl.AddText(vec2(tx, midY - gSize.y * 0.5), glyphCol, glyph);
        tx += gSize.x;
        vec4 labelCol = vec4(0.88, 0.90, 0.93, 1.0);
        if (labelTail.Length > 0) {
            tx += 8;
            vec2 tSize = UI::MeasureString(labelTail);
            dl.AddText(vec2(tx, midY - tSize.y * 0.5), labelCol, labelTail);
            tx += tSize.x;
        }
        tx += 10;

        // Peek is redundant when the full body is rendered below — only
        // show the inline preview on collapsed chips.
        if (!msg.expanded) {
            vec4 peekCol = vec4(0.55, 0.60, 0.68, 0.90);
            vec2 pSize = UI::MeasureString(peek);
            dl.AddText(vec2(tx, midY - pSize.y * 0.5), peekCol, peek);

            // Collapsed screenshot chip: still show the image — a thumbnail
            // (70% width) below the header row; hovering it pops a large
            // preview overlay. Falls back to nothing when no texture.
            if (msg.imagePath.Length > 0) {
                ToolImages::Entry@ img = ToolImages::FindEntry(msg.imagePath);
                if (img !is null && img.texture !is null) {
                    float maxW = UI::GetContentRegionAvail().x * 0.70;
                    float scale = maxW / float(img.w);
                    vec2 sz = vec2(float(img.w) * scale, float(img.h) * scale);
                    // Layout: thumbnail starts below the header row.
                    vec2 tp = UI::GetCursorPos();
                    UI::Dummy(sz + vec2(0, 4));
                    vec2 tabs = UI::GetWindowPos() + tp - vec2(UI::GetScrollX(), UI::GetScrollY());
                    dl.AddImage(img.texture, tabs, sz);
                    vec4 thumbRect = vec4(tabs, sz);
                    dl.AddRect(thumbRect, vec4(accent.x, accent.y, accent.z, 0.45), 4, 6);
                    bool thumbHover = UI::IsItemHovered();
                    if (thumbHover) {
                        UI::SetTooltip("click to expand the full result");
                        // Large preview overlay centered on the window.
                        float bigMaxW = UI::GetWindowSize().x - 40;
                        float bigScale = Math::Min(bigMaxW / float(img.w), 520.0 / float(img.h));
                        vec2 big = vec2(float(img.w) * bigScale, float(img.h) * bigScale);
                        vec2 wp = UI::GetWindowPos() + (UI::GetWindowSize() - big) * 0.5;
                        // Draw AFTER the window so it overlays the chat.
                        auto fdl = UI::GetForegroundDrawList();
                        fdl.AddImage(img.texture, wp, big);
                        fdl.AddRect(vec4(wp, big), vec4(0, 0, 0, 0.8), 6, 8);
                    }
                }
            }
        }

        UI::PopFont();

        if (msg.expanded) {
            // Prettify once per message — Json::Parse+Write per frame was
            // a measurable chunk of the draw cost on long chats.
            if (!msg.prettyComputed) {
                msg.cachedPretty = body;
                auto parsed = Json::Parse(body);
                if (parsed !is null && parsed.GetType() != Json::Type::Null) {
                    msg.cachedPretty = Json::Write(parsed, true);
                }
                msg.prettyComputed = true;
            }

            UI::Indent(padX + 10);
            UI::PushFont(UI::Font::DefaultMono);
            UI::PushStyleColor(UI::Col::Text, vec4(0.72, 0.76, 0.82, 1.0));
            UI::TextWrapped(msg.cachedPretty);
            UI::PopStyleColor();
            UI::PopFont();
            UI::Unindent(padX + 10);

            // Screenshot: draw the captured image below the JSON body.
            // Aspect-correct, capped height; rounded rect border ties it to
            // the chip family. Falls back to a note when the texture is
            // missing (capped cache / load failure).
            if (msg.imagePath.Length > 0) {
                UI::Indent(padX + 10);
                ToolImages::Entry@ img = ToolImages::FindEntry(msg.imagePath);
                if (img !is null && img.texture !is null) {
                    float maxH = 320.0;
                    float maxW = UI::GetContentRegionAvail().x;
                    float scale = Math::Min(maxW / float(img.w), maxH / float(img.h));
                    vec2 sz = vec2(float(img.w) * scale, float(img.h) * scale);
                    vec2 p = UI::GetCursorPos();
                    UI::Dummy(sz + vec2(0, 2));
                    vec2 abs = UI::GetWindowPos() + p - vec2(UI::GetScrollX(), UI::GetScrollY());
                    dl.AddImage(img.texture, abs, sz);
                    dl.AddRect(vec4(abs, sz), vec4(accent.x, accent.y, accent.z, 0.45), 4, 6);
                } else {
                    UI::TextDisabled("image: " + msg.imagePath);
                }
                UI::Unindent(padX + 10);
            }

            vec2 expEnd = UI::GetCursorPos();
            float expEndY = UI::GetWindowPos().y + expEnd.y - UI::GetScrollY();
            // Continuing accent bar flows from the chip's bar into the body
            // — no separate tinted panel, so the expanded content reads as
            // indented text attached to the chip rather than a second card.
            float barTop = absY + rowH;
            vec4 barCol = vec4(accent.x, accent.y, accent.z, 0.65);
            dl.AddRectFilled(vec4(absX, barTop, 2, expEndY - barTop), barCol, 1);
        }

        UI::Dummy(vec2(0, tightBottom ? 0 : 2));
    }

    const UI::InputTextFlags _WordWrap = UI::InputTextFlags(1 << 24);

    void DrawInput() {
        UI::Dummy(vec2(0, 6));

        float inputHeight = 84;
        float inputWidth = UI::GetWindowContentRegionWidth() - 84;

        vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);
        bool preActive = g_InputText.Length > 0;
        UI::PushStyleColor(UI::Col::Border, vec4(accent.x, accent.y, accent.z, preActive ? 0.55 : 0.18));
        UI::PushStyleVar(UI::StyleVar::FrameBorderSize, 1);
        g_InputText = UI::InputTextMultiline("##input", g_InputText, vec2(inputWidth, inputHeight), UI::InputTextFlags(UI::InputTextFlags::CtrlEnterForNewLine | _WordWrap));
        bool focused = UI::IsItemActive() || UI::IsItemFocused();
        UI::PopStyleVar();
        UI::PopStyleColor();

        bool inputEmpty = g_InputText.Length == 0;
        if (inputEmpty && !focused) {
            vec4 inRect = UI::GetItemRect();
            auto dl2 = UI::GetWindowDrawList();
            dl2.AddText(vec2(inRect.x + 10, inRect.y + 8), vec4(0.40, 0.44, 0.50, 1.0), "Ask about the map, place blocks, find items\xE2\x80\xA6");
        }
        if (focused) {
            vec4 inRect = UI::GetItemRect();
            auto dl3 = UI::GetWindowDrawList();
            float pulse = BreathPulse(2.5);
            vec4 glow = vec4(accent.x, accent.y, accent.z, 0.25 + 0.20 * pulse);
            dl3.AddRect(vec4(inRect.x - 1, inRect.y - 1, inRect.z + 2, inRect.w + 2), glow, 2, 1);
            // Subtle shortcut hint in bottom-right of the textarea.
            UI::PushFont(UI::Font::DefaultMono);
            string hint = "Ctrl + Enter";
            vec2 hSize = UI::MeasureString(hint);
            vec4 hintCol = vec4(accent.x, accent.y, accent.z, 0.55);
            dl3.AddText(vec2(inRect.x + inRect.z - hSize.x - 8, inRect.y + inRect.w - hSize.y - 6), hintCol, hint);
            UI::PopFont();
        }

        // Ctrl+Enter submits while the multiline input is focused. Plain
        // Enter still inserts a newline (the default multiline behaviour).
        bool ctrlDown = UI::IsKeyDown(UI::Key::LeftCtrl) || UI::IsKeyDown(UI::Key::RightCtrl);
        bool enterPressed = UI::IsKeyPressed(UI::Key::Enter);
        if (focused && ctrlDown && enterPressed) {
            trace("Ctrl+Enter pressed");
            string trimmed = g_InputText.Trim();
            if (trimmed.Length > 0) {
                if (SendMessage(trimmed)) g_InputText = "";
            }
        }

        UI::SameLine();
        float fillA = inputEmpty ? 0.06 : 0.28;
        float borderA = inputEmpty ? 0.25 : 0.70;
        float textA = inputEmpty ? 0.65 : 1.0;
        PushAccentButtonStyle(accent, fillA, borderA, vec4(0.85, 0.97, 1.00, textA));
        if (UI::Button("Send", vec2(72, inputHeight))) {
            if (g_InputText.Length > 0) {
                if (SendMessage(g_InputText)) g_InputText = "";
            }
        }
        PopAccentButtonStyle();

        // UI::Text("[Debug] ctrl: " + ctrlDown + " | focused: " + focused + " | enter: " + enterPressed);
    }

    void DrawBottomToolbar() {
        UI::Dummy(vec2(0, 4));

        Json::Value@ tools = ToolAssembler::GetToolList();
        Json::Value@ stats = LlmHistory::BuildContextStats(tools, AgentSettings::S_MaxHistoryTokens);
        int usedTokens = int(stats["estimatedTotalTokens"]);
        bool showCompact = usedTokens >= AgentSettings::S_CompactButtonThreshold;

        vec4 subtleFill = vec4(0.55, 0.60, 0.68, 0.08);
        vec4 subtleHover = vec4(0.55, 0.60, 0.68, 0.18);
        vec4 subtleActive = vec4(0.55, 0.60, 0.68, 0.32);
        vec4 subtleBorder = vec4(0.55, 0.60, 0.68, 0.30);
        vec4 subtleText = vec4(0.72, 0.76, 0.82, 1.0);

        UI::PushStyleColor(UI::Col::Button, subtleFill);
        UI::PushStyleColor(UI::Col::ButtonHovered, subtleHover);
        UI::PushStyleColor(UI::Col::ButtonActive, subtleActive);
        UI::PushStyleColor(UI::Col::Border, subtleBorder);
        UI::PushStyleColor(UI::Col::Text, subtleText);
        UI::PushStyleVar(UI::StyleVar::FrameBorderSize, 1);

        if (UI::Button(Icons::PlusCircle + "  New##chat")) {
            ClearMessages();
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Start a new conversation (clears history)");

        if (showCompact) {
            UI::SameLine(0, 6);
            int pct = int(float(usedTokens) / float(AgentSettings::S_MaxHistoryTokens) * 100.0 + 0.5);
            if (UI::Button(Icons::Compress + "  Compact##ctx")) {
                LlmHistory::CompactHistory(tools, AgentSettings::S_MaxHistoryTokens);
            }
            if (UI::IsItemHovered()) UI::SetTooltip("Summarize earlier turns to free context\nCurrent: " + FormatTokenCount(usedTokens) + " tokens (" + pct + "%)");
        }

        float gearSize = UI::GetFrameHeight();
        UI::SameLine();
        UI::SetCursorPosX(UI::GetWindowSize().x - gearSize - 12);
        DrawSettingsButton("toolbar");

        UI::PopStyleVar();
        UI::PopStyleColor(5);
    }

    void DrawSectionHeader(const string &in title, const string &in icon = "") {
        vec4 sectionCol = vec4(0.00, 0.82, 0.95, 0.85);
        vec4 iconCol = vec4(0.00, 0.82, 0.95, 0.55);
        UI::Dummy(vec2(0, 2));
        UI::PushFont(UI::Font::DefaultBold);
        if (icon.Length > 0) {
            UI::PushStyleColor(UI::Col::Text, iconCol);
            UI::Text(icon);
            UI::PopStyleColor();
            UI::SameLine(0, 8);
        }
        UI::PushStyleColor(UI::Col::Text, sectionCol);
        UI::Text(title);
        UI::PopStyleColor();
        UI::PopFont();
        UI::Dummy(vec2(0, 3));
    }

    // ---- Reusable UI helpers ----

    // Horizontal rule that fades edge → mid → edge in the given accent.
    // Used to visually anchor section headings; also as a lighter
    // alternative to UI::Separator() when a row needs emphasis.
    // Push style for an accent-tinted button (Send / Close / Test Provider
    // family). Caller MUST call PopAccentButtonStyle() after the Button.
    //   fillA / borderA scale accent alpha on the body/border slots.
    //   textColor is used verbatim — callers pick whatever tone looks right
    //   against the accent (e.g. cyan-accent buttons use near-white; amber
    //   accent buttons use bright amber to stay on palette).
    void PushAccentButtonStyle(const vec4 &in accent, float fillA, float borderA, const vec4 &in textColor, float hoverFillA = 0.42, float activeFillA = 0.60) {
        UI::PushStyleColor(UI::Col::Button, vec4(accent.x, accent.y, accent.z, fillA));
        UI::PushStyleColor(UI::Col::ButtonHovered, vec4(accent.x, accent.y, accent.z, hoverFillA));
        UI::PushStyleColor(UI::Col::ButtonActive, vec4(accent.x, accent.y, accent.z, activeFillA));
        UI::PushStyleColor(UI::Col::Border, vec4(accent.x, accent.y, accent.z, borderA));
        UI::PushStyleColor(UI::Col::Text, textColor);
        UI::PushStyleVar(UI::StyleVar::FrameBorderSize, 1);
    }

    void PopAccentButtonStyle() {
        UI::PopStyleVar();
        UI::PopStyleColor(5);
    }

    // ------------------------------------------------------------------
    // Settings helpers: provider display names, model combo with catalog,
    // effort combo driven by models.dev reasoning_values.
    // ------------------------------------------------------------------

    string ProviderDisplayName(Provider p) {
        switch (p) {
            case Provider::MiniMax: return "MiniMax";
            case Provider::OpenAI: return "OpenAI";
            case Provider::CustomOpenAI: return "Custom (OpenAI-compatible)";
            case Provider::CustomAnthropic: return "Custom (Anthropic-compatible)";
        }
        return "Unknown";
    }

    // Catalog id for the active provider (used by ModelCatalog state).
    string CatalogIdFor(Provider p) {
        switch (p) {
            case Provider::OpenAI: return "openai";
            case Provider::CustomOpenAI: return "custom-openai";
            case Provider::CustomAnthropic: return "custom-anthropic";
        }
        return "";
    }

    // Auto-fetch-on-open helper: if the provider supports listing and no
    // catalog is resident yet, kick one fetch (button-free UX).
    void MaybeAutoFetchCatalog() {
        string catalogId = CatalogIdFor(AgentSettings::S_Provider);
        if (catalogId.Length == 0) return;
        if (ModelCatalog::GetCatalog(catalogId) !is null) return;
        if (ModelCatalog::IsFetching()) return;
        string apiKey = AgentSettings::CurrentApiKey();
        if (apiKey.Length == 0) return;
        if (AgentSettings::S_Provider == Provider::OpenAI) {
            ModelCatalog::StartFetchCatalog(catalogId, false, apiKey, "https://api.openai.com/v1");
        } else if (AgentSettings::S_Provider == Provider::CustomOpenAI) {
            if (AgentSettings::S_CustomOpenAIBaseUrl.Length == 0) return;
            ModelCatalog::StartFetchCatalog(catalogId, false, apiKey, AgentSettings::S_CustomOpenAIBaseUrl);
        } else if (AgentSettings::S_Provider == Provider::CustomAnthropic) {
            if (AgentSettings::S_CustomAnthropicBaseUrl.Length == 0) return;
            ModelCatalog::StartFetchCatalog(catalogId, true, apiKey, AgentSettings::S_CustomAnthropicBaseUrl);
        }
    }

    // Model row: text input + (optional) dropdown fed by the provider's
    // /models listing. Writes the selection into ModelCatalog::
    // _pendingModelSelection when a catalog entry is chosen; otherwise the
    // caller's current value flows through unchanged.
    void DrawModelRow(const string &in label, const string &in current, array<string>@ catalog, const string &in fallbackHint) {
        // Free-text entry first — for exotic/custom ids the listing may not
        // include. A combo selection below overwrites the same-frame value,
        // so ordering (input, then combo) keeps both paths working.
        string edited = UI::InputText(label + " (custom)", current);
        ModelCatalog::_pendingModelSelection = edited;
        if (catalog !is null && catalog.Length > 0) {
            // Dropdown fed by the provider's /models listing; selection
            // auto-populates limits/effort from models.dev metadata.
            if (UI::BeginCombo(label, current)) {
                for (uint i = 0; i < catalog.Length; i++) {
                    if (UI::Selectable(catalog[i], catalog[i] == current)) {
                        ModelCatalog::_pendingModelSelection = catalog[i];
                        ModelCatalog::ApplyModelMetaToSettings();
                    }
                }
                UI::EndCombo();
            }
            if (UI::IsItemHovered()) {
                UI::SetTooltip(catalog.Length + " models listed" + (ModelCatalog::IsFetching() ? "; refreshing…" : ""));
            }
        }
    }

    // Effort combo fed by models.dev reasoning_values when known.
    void DrawEffortCombo(const string &in label, const string &in current, const string &in providerKey) {
        array<string> efforts = ModelCatalog::EffortChoicesFor(providerKey);
        if (UI::BeginCombo(label, current)) {
            for (uint i = 0; i < efforts.Length; i++) {
                if (UI::Selectable(efforts[i], efforts[i] == current)) {
                    if (providerKey == "openai") {
                        AgentSettings::S_OpenAIReasoningEffort = efforts[i];
                    } else if (providerKey == "custom-openai") {
                        AgentSettings::S_CustomOpenAIReasoningEffort = efforts[i];
                    }
                }
            }
            UI::EndCombo();
        }
    }

    // One-line summary of models.dev metadata for the active model:
    // context/output limits, reasoning support. Kicks the weekly
    // models.dev refresh from a dedicated coroutine.
    void DrawModelMetaLine() {
        UI::Dummy(vec2(0, 2));
        ModelCatalog::ModelMeta@ meta = ModelCatalog::CurrentModelMeta();
        string line;
        if (meta.known) {
            line = Icons::Info + " " + meta.model + ": "
                + (meta.contextTokens > 0 ? "" + meta.contextTokens + " ctx" : "ctx ?")
                + " / " + (meta.outputTokens > 0 ? "" + meta.outputTokens + " out" : "out ?")
                + (meta.reasoning ? " · reasoning" : "");
        } else {
            line = Icons::Info + " " + meta.model + ": no models.dev metadata (cache "
                + (AiApi::ModelsDevCacheIsFresh() ? "fresh" : "stale/missing") + ")";
        }
        UI::Text(line);
        if (UI::IsItemHovered()) {
            UI::SetTooltip("models.dev metadata, cached for 7 days. Context auto-populates Max History Tokens.");
        }
        if (!AiApi::ModelsDevCacheIsFresh() && !AiApi::ModelsDevFetchInFlight()) {
            startnew(ModelsDevRefreshCoro);
        }
    }

    void ModelsDevRefreshCoro() {
        AiApi::ModelsDevRefreshIfNeeded();
    }

    void RenderSettingsWindow() {
        PushTheme();
        UI::SetNextWindowSize(420, 0, UI::Cond::FirstUseEver);
        UI::SetNextWindowSizeConstraints(360, 200, 800, 1200);
        int sFlags = UI::WindowFlags::NoCollapse | UI::WindowFlags::AlwaysAutoResize;
        if (UI::Begin(Icons::Cog + "  TM Agent Settings", g_ShowSettings, sFlags)) {
            g_SettingsPos = UI::GetWindowPos();
            g_SettingsSize = UI::GetWindowSize();
            DrawAmberTitleAccent();
            int keyFlags = UI::InputTextFlags::Password;

            DrawSectionHeader("PROVIDER", Icons::Plug);
            MaybeAutoFetchCatalog();
            string currentProvider = ProviderDisplayName(AgentSettings::S_Provider);
            if (UI::BeginCombo("Provider", currentProvider)) {
                if (UI::Selectable("MiniMax", AgentSettings::S_Provider == Provider::MiniMax)) {
                    AgentSettings::S_Provider = Provider::MiniMax;
                }
                if (UI::Selectable("OpenAI", AgentSettings::S_Provider == Provider::OpenAI)) {
                    AgentSettings::S_Provider = Provider::OpenAI;
                }
                if (UI::Selectable("Custom (OpenAI-compatible)", AgentSettings::S_Provider == Provider::CustomOpenAI)) {
                    AgentSettings::S_Provider = Provider::CustomOpenAI;
                }
                if (UI::Selectable("Custom (Anthropic-compatible)", AgentSettings::S_Provider == Provider::CustomAnthropic)) {
                    AgentSettings::S_Provider = Provider::CustomAnthropic;
                }
                UI::EndCombo();
            }

            if (AgentSettings::S_Provider == Provider::MiniMax) {
                DrawSectionHeader("MINIMAX", Icons::Key);
                AgentSettings::S_MiniMaxApiKey = UI::InputText("API Key", AgentSettings::S_MiniMaxApiKey, keyFlags);
                DrawModelRow("Model", AgentSettings::S_MiniMaxModel, null, "minimax");
                AgentSettings::S_MiniMaxModel = ModelCatalog::_pendingModelSelection;
            } else if (AgentSettings::S_Provider == Provider::OpenAI) {
                DrawSectionHeader("OPENAI", Icons::Key);
                AgentSettings::S_OpenAIApiKey = UI::InputText("API Key", AgentSettings::S_OpenAIApiKey, keyFlags);
                DrawModelRow("Model", AgentSettings::S_OpenAIModel, ModelCatalog::GetCatalog("openai"), "openai");
                AgentSettings::S_OpenAIModel = ModelCatalog::_pendingModelSelection;
                DrawEffortCombo("Reasoning Effort", AgentSettings::S_OpenAIReasoningEffort, "openai");
            } else if (AgentSettings::S_Provider == Provider::CustomOpenAI) {
                DrawSectionHeader("CUSTOM OPENAI-COMPATIBLE", Icons::Key);
                AgentSettings::S_CustomOpenAIBaseUrl = UI::InputText("Base URL", AgentSettings::S_CustomOpenAIBaseUrl);
                if (UI::IsItemHovered()) UI::SetTooltip("e.g. https://openrouter.ai/api/v1 — /chat/completions is appended.");
                AgentSettings::S_CustomOpenAIApiKey = UI::InputText("API Key", AgentSettings::S_CustomOpenAIApiKey, keyFlags);
                DrawModelRow("Model", AgentSettings::S_CustomOpenAIModel, ModelCatalog::GetCatalog("custom-openai"), "custom-openai");
                AgentSettings::S_CustomOpenAIModel = ModelCatalog::_pendingModelSelection;
                DrawEffortCombo("Reasoning Effort", AgentSettings::S_CustomOpenAIReasoningEffort, "custom-openai");
            } else {
                DrawSectionHeader("CUSTOM ANTHROPIC-COMPATIBLE", Icons::Key);
                AgentSettings::S_CustomAnthropicBaseUrl = UI::InputText("Base URL", AgentSettings::S_CustomAnthropicBaseUrl);
                if (UI::IsItemHovered()) UI::SetTooltip("e.g. https://api.anthropic.com — /v1/messages is appended.");
                AgentSettings::S_CustomAnthropicApiKey = UI::InputText("API Key", AgentSettings::S_CustomAnthropicApiKey, keyFlags);
                DrawModelRow("Model", AgentSettings::S_CustomAnthropicModel, ModelCatalog::GetCatalog("custom-anthropic"), "custom-anthropic");
                AgentSettings::S_CustomAnthropicModel = ModelCatalog::_pendingModelSelection;
            }

            // models.dev metadata line for the current model, if known.
            DrawModelMetaLine();

            // Provider Test — sends a single "ping" request to confirm the
            // key+model combo is actually reachable. Status renders inline.
            UI::Dummy(vec2(0, 2));
            UI::BeginDisabled(g_TestRunning);
            vec4 amber = vec4(0.95, 0.65, 0.15, 1.0);
            PushAccentButtonStyle(amber, 0.14, 0.55, vec4(1.00, 0.88, 0.52, 1.0), 0.28, 0.42);
            if (UI::Button(Icons::Bolt + "  Test Provider##providertest")) {
                StartProviderTest();
            }
            PopAccentButtonStyle();
            UI::EndDisabled();
            if (g_TestResult.Length > 0) {
                UI::SameLine(0, 10);
                UI::AlignTextToFramePadding();
                vec4 testColor = g_TestColor;
                UI::PushStyleColor(UI::Col::Text, testColor);
                UI::Text(g_TestResult);
                UI::PopStyleColor();
            }

            DrawSectionHeader("CONTEXT", Icons::Database);
            AgentSettings::S_MaxHistoryTokens = UI::SliderInt(
                "Max History Tokens", AgentSettings::S_MaxHistoryTokens, 16000, 1000000, "%d tok"
            );
            if (UI::IsItemHovered()) UI::SetTooltip("Hard ceiling — older messages get compacted above this.");

            AgentSettings::S_CompactButtonThreshold = UI::SliderInt(
                "Compact Button At", AgentSettings::S_CompactButtonThreshold, 4000, 1000000, "%d tok"
            );
            if (UI::IsItemHovered()) UI::SetTooltip("Compact button appears in the toolbar once used context crosses this.");

            UI::Dummy(vec2(0, 6));
            UI::Separator();
            UI::Dummy(vec2(0, 4));

            // Right-align the close button so it anchors the window corner.
            float closeW = UI::MeasureString(Icons::Times + "  Close").x + 20;
            UI::SetCursorPosX(UI::GetWindowSize().x - closeW - 12);
            vec4 accent = vec4(0.00, 0.82, 0.95, 1.0);
            PushAccentButtonStyle(accent, 0.12, 0.50, vec4(0.85, 0.97, 1.00, 1.0), 0.28, 0.42);
            if (UI::Button(Icons::Times + "  Close", vec2(closeW, UI::GetFrameHeight()))) {
                g_ShowSettings = false;
            }
            PopAccentButtonStyle();
        }
        UI::End();
        PopTheme();
    }

    bool SendMessage(const string &in text) {
        if (::g_State != STATE_IDLE) return false;

        // Log-before-UI: the user turn is persisted before the bubble or
        // any history state exists, so a crash can't lose the prompt.
        SessionLog::LogUserMessage(text);
        Interactive::OnUserFreeText(text);
        AddMessage(MsgType::User, text);
        g_CurrentTurn++;
        g_StepCount = 1;
        g_Status.Set(StatusKind::Running);
        AgentStats::RecordUserMessage();

        // Claim the global run state synchronously. Deferring this call to a
        // coroutine leaves a frame where a second submission can also pass the
        // idle check, render in the UI, and then be rejected by AgentLoop.
        ::SendMessage(text);
        return true;
    }

    void IncrementStep() {
        g_StepCount++;
        AgentStats::RecordStep();
    }


    void AddInteractive(const string &in id, const string &in title) {
        auto msg = Message(MsgType::Interactive, title);
        msg.interactiveId = id;
        g_Messages.InsertLast(msg);
        g_PendingScrollBottom = true;
    }

    void AddMessage(MsgType t, const string &in content) {
        g_Messages.InsertLast(Message(t, content));
        g_PendingScrollBottom = true;
    }

    void AddToolCall(const string &in toolName, const string &in inputJson) {
        auto msg = Message(MsgType::ToolCall, inputJson);
        msg.toolName = toolName;
        g_Messages.InsertLast(msg);
        g_PendingScrollBottom = true;
    }

    void AddToolResult(const string &in toolName, const string &in result) {
        auto msg = Message(MsgType::ToolResult, result);
        msg.toolName = toolName;
        g_Messages.InsertLast(msg);
        g_PendingScrollBottom = true;
    }

    // Screenshot attach: the most recent ToolResult chip renders the image.
    // (Called right after AddToolResult by the screenshot post-processing.)
    void AttachImageToLastToolResult(const string &in path) {
        for (int i = int(g_Messages.Length) - 1; i >= 0; i--) {
            if (g_Messages[i].type == MsgType::ToolResult) {
                g_Messages[i].imagePath = path;
                g_Messages[i].InvalidateLayout();
                return;
            }
        }
    }

    // Callers pass StatusKind + optional description. The one overload that
    // takes a free string (wire format) is reserved for the file-IPC driver.
    void SetStatus(StatusKind kind, const string &in description = "") {
        g_Status.Set(kind, description);
    }

    void ClearMessages() {
        ::CancelCurrentRun();
        LlmHistory::ClearHistory();
        g_Messages.RemoveRange(0, g_Messages.Length);
        StartupSuggestion::g_Dismissed = false;
        g_CurrentTurn = 0;
        g_StepCount = 0;
        g_Status.Set(StatusKind::Idle);
        g_LastInputTokens = 0;
        g_LastCachedReadTokens = 0;
        g_LastCacheWriteTokens = 0;
        g_LastOutputTokens = 0;
        g_LastTotalTokens = 0;
        g_RunningOutputTokens = 0;
        // Rotate the on-disk session: the cleared conversation's transcript
        // stays browsable, and the next message starts a fresh file.
        SessionLog::StartNewSession();
    }

    void UpdateTokenStats(int inputTokens, int outputTokens, int totalTokens, int cachedReadTokens = 0, int cacheWriteTokens = 0) {
        g_LastInputTokens = inputTokens;
        g_LastOutputTokens = outputTokens;
        g_LastTotalTokens = totalTokens;
        g_LastCachedReadTokens = cachedReadTokens;
        g_LastCacheWriteTokens = cacheWriteTokens;
        g_RunningOutputTokens += outputTokens;
        AgentStats::RecordTokens(inputTokens, outputTokens, cachedReadTokens, cacheWriteTokens);
    }

    void RenderMenu() {
        if (UI::MenuItem("TM Agent", "", AgentSettings::S_ShowWindow)) {
            AgentSettings::S_ShowWindow = !AgentSettings::S_ShowWindow;
        }
    }
}
