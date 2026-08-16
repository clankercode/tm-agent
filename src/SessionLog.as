// Session persistence: append-only JSONL transcripts of every user/assistant
// message, tool call/result, and LLM exchange metadata. One file per
// conversation (rotated on New/clear), stored under
// PluginStorage/tm-agent/sessions/ so past sessions can be browsed offline
// (similar to Claude Code / coding-CLI session files).
//
// Invariants:
//  - Every record is a single JSON object on one line (JSONL).
//  - Records are appended in causal order at the moment the event is
//    committed (log-before-UI: the session log is written before the UI
//    state mutates, so a crash cannot lose what the agent sent/received).
//  - The logger never throws into callers: I/O failures are traced once
//    and the session continues.
namespace SessionLog {

    string g_Dir = "";
    string g_Path = "";
    bool g_Enabled = true;
    bool g_WarnedIoFailure = false;
    bool g_PendingMeta = false;
    uint g_RecordCount = 0;

    const string VERSION = "1";

    bool EnsureDir() {
        if (g_Dir.Length == 0) {
#if UNITTEST
            // Unit tests write many sessions in the same second; keep them
            // out of the user's real sessions folder.
            g_Dir = IO::FromStorageFolder("sessions-unittest");
#else
            g_Dir = IO::FromStorageFolder("sessions");
#endif
        }
        if (!IO::FolderExists(g_Dir)) {
            IO::CreateFolder(g_Dir);
        }
        return IO::FolderExists(g_Dir);
    }

    // Starts a fresh session file. Called on first use and on conversation
    // reset (New button / ClearMessages / driver "new").
    string StartNewSession() {
        g_RecordCount = 0;
        g_WarnedIoFailure = false;
        if (!EnsureDir()) {
            g_Path = "";
            g_PendingMeta = false;
            return "";
        }
        string stamp = Time::FormatString("%Y-%m-%d_%H-%M-%S");
        g_Path = g_Dir + "/session-" + stamp + ".jsonl";
        // Guard against same-second rotation collisions (unit tests, driver
        // loops): append a counter until the path is unused.
        uint uniquifier = 1;
        while (IO::FileExists(g_Path) && uniquifier < 100) {
            g_Path = g_Dir + "/session-" + stamp + "-" + uniquifier + ".jsonl";
            uniquifier++;
        }
        // Every session file starts with a session_meta header record; it is
        // written by the next AppendLine so a rotation with no follow-up
        // writes nothing to disk at all.
        g_PendingMeta = true;
        return g_Path;
    }

    void WriteSessionMetaHeader() {
        Json::Value meta = Json::Object();
        meta["provider"] = AgentSettings::CurrentProviderLabel();
        meta["model"] = AgentSettings::CurrentModel();
        DoAppendLine(BuildRecordLine("session_meta", "", meta));
    }

    string BuildRecordLine(const string &in type, const string &in content, Json::Value@ data) {
        Json::Value rec = Json::Object();
        rec["v"] = VERSION;
        rec["ts"] = Time::FormatString("%Y-%m-%dT%H:%M:%S");
        rec["type"] = type;
        rec["content"] = content;
        if (data !is null && data.GetType() == Json::Type::Object) {
            Json::Value@ keys = data.GetKeys();
            for (uint i = 0; i < keys.Length; i++) {
                string key = keys[i];
                rec[key] = data[key];
            }
        }
        return Json::Write(rec);
    }

    void DoAppendLine(const string &in line) {
        try {
            IO::File f(g_Path, IO::FileMode::Append);
            f.WriteLine(line);
            f.Close();
            g_RecordCount++;
        } catch {
            if (!g_WarnedIoFailure) {
                print("[tm-agent] session log write failed: " + getExceptionInfo());
                g_WarnedIoFailure = true;
            }
            // One-sided failure mode: logging must never break the agent.
        }
    }

    void AppendLine(const string &in line) {
        if (!g_Enabled) return;
        if (g_Path.Length == 0) {
            StartNewSession();
            if (g_Path.Length == 0) return;
        }
        if (g_PendingMeta) {
            g_PendingMeta = false;
            WriteSessionMetaHeader();
        }
        DoAppendLine(line);
    }

    // Core record writer. Reserved fields (v/ts/type/content) are written
    // first; any same-named key in `data` overwrites them (caller wins).
    void WriteRecord(const string &in type, const string &in content, Json::Value@ data = null) {
        AppendLine(BuildRecordLine(type, content, data));
    }

    void LogUserMessage(const string &in content) {
        WriteRecord("user", content);
    }

    void LogAssistantMessage(const string &in content) {
        WriteRecord("assistant", content);
    }

    void LogToolCall(const string &in toolName, const string &in inputJson) {
        Json::Value data = Json::Object();
        data["tool"] = toolName;
        WriteRecord("tool_call", inputJson, data);
    }

    void LogToolResult(const string &in toolName, const string &in resultJson) {
        Json::Value data = Json::Object();
        data["tool"] = toolName;
        WriteRecord("tool_result", resultJson, data);
    }

    // LLM exchange metadata: parsed usage + the raw provider response.
    // Written when a response arrives — before the UI consumes it.
    // Provider/model ride on every exchange because they can change
    // mid-session; session_meta alone only reflects the session start.
    void LogLlmExchange(int inputTokens, int outputTokens, int totalTokens, const string &in rawResp) {
        Json::Value usage = Json::Object();
        usage["input_tokens"] = inputTokens;
        usage["output_tokens"] = outputTokens;
        usage["total_tokens"] = totalTokens;
        Json::Value data = Json::Object();
        data["usage"] = usage;
        data["raw_response"] = rawResp;
        data["provider"] = AgentSettings::CurrentProviderLabel();
        data["model"] = AgentSettings::CurrentModel();
        WriteRecord("llm_exchange", "", data);
    }

    void LogError(const string &in message) {
        WriteRecord("error", message);
    }

    void LogSystem(const string &in message) {
        WriteRecord("system", message);
    }

    void SetEnabled(bool enabled) { g_Enabled = enabled; }
    bool Enabled() { return g_Enabled; }
    string Path() { return g_Path; }
    uint RecordCount() { return g_RecordCount; }

    // ---- Test support ----
#if UNITTEST
    void ResetForTest() {
        g_Dir = "";
        g_Path = "";
        g_RecordCount = 0;
        g_WarnedIoFailure = false;
        g_PendingMeta = false;
        g_Enabled = true;
    }

    string ReadSessionFileForTest() {
        if (g_Path.Length == 0 || !IO::FileExists(g_Path)) return "";
        IO::File f(g_Path, IO::FileMode::Read);
        string raw = f.ReadToEnd();
        f.Close();
        return raw;
    }
#endif
}
