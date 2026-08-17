// DEV-only session fixture loader: replays a SessionLog JSONL transcript
// back into the live chat (AgentUI message list + LlmHistory) so render/perf
// behaviour can be exercised against a real, well-populated conversation
// without re-running the agent.
//
// The load is INCREMENTAL: records are applied in small per-frame batches
// from a coroutine (StartLoad → run with startnew). A synchronous replay of
// a 200-message session wedged the game for ~8s in a single frame (message
// layout + markdown + screenshot texture decode all at once); batching keeps
// each frame's added work to a few ms so the game stays responsive while the
// conversation streams in.
//
// Reconstruction notes:
//  - UI messages are appended in original causal order, so the call→result
//    chip pairing (tightTop/tightBottom) is preserved exactly.
//  - The log's `assistant` records do not carry their tool_calls array; the
//    immediately-following `tool_call` records share the same content, so
//    they are buffered and folded into ONE AddAssistantToolCalls call —
//    keeping LLM history structurally valid (assistant tool_calls → matching
//    tool results) rather than a flattened text log.
//  - `llm_exchange` records feed the token-usage readouts (In/Cache/Out and
//    lifetime stats) so the header matches the replayed session.
//  - `session_meta` and `system` records do not enter LLM history (system
//    text was never an LLM message; meta is file chrome).
#if DEV
namespace SessionReplay {

    // Tuning: how many transcript records to apply per frame. Records are
    // cheap individually; the cost is the downstream layout of newly-added
    // messages, which scales with how many land in one frame.
    const int BATCH_PER_FRAME = 12;

    // Progress state (read by the driver "get_state"/"load_session_status").
    bool g_Loading = false;
    int g_Applied = 0;
    int g_Total = 0;
    string g_Error = "";

    // Per-record parsed lines, split out up front (parse is cheap; layout is
    // not) so the frame loop only does the state-mutation part.
    array<string> g_Lines;

    class LoadReport {
        int userMsgs = 0;
        int assistantMsgs = 0;
        int toolCalls = 0;
        int toolResults = 0;
        int systemMsgs = 0;
        int llmExchanges = 0;
        int skipped = 0;
        string error = "";
    }
    LoadReport g_Rep;

    // Buffered assistant text + tool calls for the current assistant group
    // (see header comment on tool_calls reconstruction).
    string g_PendingAssistantText = "";
    array<Json::Value@> g_PendingToolCalls;
    int g_LlmSeq = 0;

    void _FlushPendingAssistant() {
        if (g_PendingToolCalls.Length == 0) return;
        LlmHistory::AddAssistantToolCalls(g_PendingAssistantText, g_PendingToolCalls);
        g_PendingToolCalls.Resize(0);
        g_PendingAssistantText = "";
    }

    void _ApplyLine(const string &in lineRaw) {
        string line = lineRaw.Trim();
        if (line.Length == 0) return;
        Json::Value@ rec = Json::Parse(line);
        if (rec is null || rec.GetType() != Json::Type::Object || !rec.HasKey("type")) {
            g_Rep.skipped++;
            return;
        }
        string type = string(rec["type"]);
        string content = rec.HasKey("content") && rec["content"].GetType() == Json::Type::String
            ? string(rec["content"]) : "";
        string tool = rec.HasKey("tool") && rec["tool"].GetType() == Json::Type::String
            ? string(rec["tool"]) : "";

        if (type == "assistant") {
            _FlushPendingAssistant();
            g_PendingAssistantText = content;
            AgentUI::AddMessage(AgentUI::MsgType::Assistant, content);
            g_Rep.assistantMsgs++;
        } else if (type == "tool_call") {
            Json::Value call = Json::Object();
            call["id"] = "replay_" + (g_LlmSeq++);
            call["name"] = tool;
            Json::Value@ input = Json::Parse(content);
            call["input"] = input !is null ? input : Json::Object();
            g_PendingToolCalls.InsertLast(call);
            AgentUI::AddToolCall(tool, content);
            g_Rep.toolCalls++;
        } else if (type == "tool_result") {
            _FlushPendingAssistant();
            LlmHistory::AddToolResult("replay_result_" + g_Applied, tool, content);
            AgentUI::AddToolResult(tool, content);
            g_Rep.toolResults++;
        } else if (type == "user") {
            _FlushPendingAssistant();
            LlmHistory::AddUserMessage(content);
            AgentUI::AddMessage(AgentUI::MsgType::User, content);
            g_Rep.userMsgs++;
        } else if (type == "llm_exchange") {
            g_Rep.llmExchanges++;
            if (rec.HasKey("usage") && rec["usage"].GetType() == Json::Type::Object) {
                Json::Value@ u = rec["usage"];
                int inTok = u.HasKey("input_tokens") ? int(u["input_tokens"]) : 0;
                int outTok = u.HasKey("output_tokens") ? int(u["output_tokens"]) : 0;
                int totTok = u.HasKey("total_tokens") ? int(u["total_tokens"]) : inTok + outTok;
                int crTok = u.HasKey("cached_read_tokens") ? int(u["cached_read_tokens"]) : 0;
                int cwTok = u.HasKey("cache_write_tokens") ? int(u["cache_write_tokens"]) : 0;
                AgentUI::UpdateTokenStats(inTok, outTok, totTok, crTok, cwTok);
            }
        } else if (type == "system") {
            AgentUI::AddMessage(AgentUI::MsgType::System, content);
            g_Rep.systemMsgs++;
        } else {
            // session_meta + anything else: file chrome, not chat data.
            g_Rep.skipped++;
        }
    }

    // Begin an incremental load. Returns false (and sets g_Error) on a hard
    // failure (missing file). The actual replay runs in the returned
    // coroutine — the caller must startnew it.
    bool BeginLoad(const string &in path) {
        g_Error = "";
        g_Loading = false;
        g_Applied = 0;
        g_Total = 0;
        // Replay is a fixture, not real usage: freeze lifetime stats for the
        // whole load so llm_exchange token feeds and any incidental Record*
        // calls never touch the user's persisted counters. Suspended here
        // (even before the early-return) and released in RunLoad — a failed
        // load still releases via its caller path below.
        AgentStats::SuspendRecording();
        if (path.Length == 0 || !IO::FileExists(path)) {
            AgentStats::ResumeRecording();
            g_Error = "file not found: " + path;
            return false;
        }
        string raw;
        {
            IO::File f(path, IO::FileMode::Read);
            raw = f.ReadToEnd();
            f.Close();
        }
        g_Lines = raw.Split("\n");
        g_Total = int(g_Lines.Length);

        // Reset current conversation WITHOUT rotating the on-disk log
        // (StartNewSession would leave an orphan empty file; replay is a
        // fixture load, not a user New).
        ::CancelCurrentRun();
        LlmHistory::ClearHistory();
        AgentUI::g_Messages.RemoveRange(0, AgentUI::g_Messages.Length);
        g_PendingToolCalls.Resize(0);
        g_PendingAssistantText = "";
        g_LlmSeq = 0;
        g_Rep = LoadReport();
        g_Loading = true;
        return true;
    }

    // Coroutine body: apply records in per-frame batches until done.
    void RunLoad() {
        while (g_Applied < g_Total) {
            int batchEnd = g_Applied + BATCH_PER_FRAME;
            if (batchEnd > g_Total) batchEnd = g_Total;
            for (int i = g_Applied; i < batchEnd; i++) {
                _ApplyLine(g_Lines[uint(i)]);
            }
            g_Applied = batchEnd;
            yield();
        }
        _FlushPendingAssistant();
        AgentUI::g_Status.Set(AgentUI::StatusKind::Idle);
        AgentUI::g_PendingScrollBottom = true;
        g_Loading = false;
        g_Lines.Resize(0);
        AgentStats::ResumeRecording();
        trace("[tm-agent] session replay complete: " + g_Applied + " records, "
            + AgentUI::g_Messages.Length + " ui messages, "
            + LlmHistory::g_Messages.Length + " history messages");
    }
}
#endif
