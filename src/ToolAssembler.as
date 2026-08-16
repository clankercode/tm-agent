// In-process tool bridge to tm-control-mcp (module TmMcp).
//
// Tools are dispatched by name through TmMcp::CallTool / DispatchAsync —
// the same registry the socket server uses. The tool list (names,
// descriptions, input schemas) is forwarded from TmMcp::GetToolList so
// tm-agent and tm-control-mcp never drift.
//
// The TmMcp::* import declarations are provided by TmMcp_Export.as, which
// Openplanet compiles into this plugin via the tm-control-mcp dependency
// (exports = ["TmMcp_Export.as"]). Do NOT redeclare them here.

namespace ToolAssembler {
    // Tools that must run inside a coroutine (they yield/sleep). The socket
    // server runs every request inside its client coroutine; in-process
    // callers route these through DispatchAsync so they run on their own
    // coroutine instead of the caller's.
    const string[] ASYNC_TOOLS = {
        "ControlValidation",
        "SaveMapAs",
        "CreateMapViaMenu",
        "EditNewMap",
        "OpenMapInEditor",
        "BackToMainMenu",
        "SetMenuPage",
        "WaitUntil",
        "RunManialinkScript"
    };

    bool IsAsyncTool(const string &in name) {
        for (uint i = 0; i < ASYNC_TOOLS.Length; i++) {
            if (ASYNC_TOOLS[i] == name) return true;
        }
        return false;
    }

    Json::Value@ GetToolList() {
        // Forward TmMcp's registry (already in Anthropic tool format:
        // {name, description, input_schema}).
        return TmMcp::GetToolList();
    }

    void AddTool(Json::Value@ tools, const string &in name, const string &in desc, const string &in inputSchemaJson) {
        Json::Value tool = Json::Object();
        tool["name"] = name;
        tool["description"] = desc;
        tool["input_schema"] = Json::Parse(inputSchemaJson);
        tools.Add(tool);
    }

    // ai-api normalizes both Anthropic and OpenAI responses into a flat shape:
    //   { text, tool_calls: [{id, name, input}], usage }
    // where `input` is an already-parsed JSON object. Read that directly.
    array<Json::Value@> ParseToolCalls(const Json::Value &in response) {
        array<Json::Value@> toolCalls;
        if (!response.HasKey("tool_calls")) return toolCalls;
        const Json::Value@ tcs = response["tool_calls"];
        if (tcs is null || tcs.GetType() != Json::Type::Array) return toolCalls;

        for (uint i = 0; i < tcs.Length; i++) {
            const Json::Value@ tc = tcs[i];
            // Preserve every provider call so AgentLoop can persist a matching
            // error result even when the call shape itself is malformed.
            Json::Value@ item = Json::Object();
            item["name"] = tc !is null && tc.GetType() == Json::Type::Object
                ? JsonX::Lookup_StringOrDefault(tc, "name", "") : "";
            item["id"] = tc !is null && tc.GetType() == Json::Type::Object
                ? JsonX::Lookup_StringOrDefault(tc, "id", "call_" + i) : "call_" + i;
            if (tc !is null && tc.GetType() == Json::Type::Object && tc.HasKey("input")) {
                item["input"] = tc["input"];
            } else {
                item["input"] = Json::Object();
            }
            toolCalls.Resize(toolCalls.Length + 1);
            @toolCalls[toolCalls.Length - 1] = item;
        }
        return toolCalls;
    }

    // Legacy: names that used to trigger the old snap-focus. Retained for
    // reference; camera-follow is now owned by FollowCam (AgentLoop pings it
    // for every executed tool call).
    bool IsFocusableTool(const string &in name) {
        return name == "PlaceBlock"
            || name == "RemoveBlock"
            || name == "GetBlockAt"
            || name == "PlaceBlockViaEditorPlusPlus"
            || name == "PlaceItemViaEditorPlusPlus";
    }

    Json::Value@ ExecuteToolCall(Json::Value@ toolCall) {
        string name = string(toolCall["name"]);
        Json::Value@ input = toolCall["input"];
        if (input is null) @input = Json::Object();

        if (!TmMcp::IsToolName(name)) {
            Json::Value err = Json::Object();
            err["success"] = false;
            err["error"] = "unknown tool: " + name;
            return err;
        }

        Json::Value@ result;
        if (IsAsyncTool(name)) {
            // Non-blocking dispatch: returns {request_id, status:"pending"};
            // AgentLoop polls TmMcp::GetResult until done/error.
            try {
                @result = TmMcp::DispatchAsync(name, input);
            } catch {
                Json::Value err = Json::Object();
                err["success"] = false;
                err["error"] = "tool " + name + " dispatch failed: " + getExceptionInfo();
                return err;
            }
        } else {
            try {
                @result = TmMcp::CallTool(name, input);
            } catch {
                Json::Value err = Json::Object();
                err["success"] = false;
                err["error"] = "tool " + name + " threw: " + getExceptionInfo();
                return err;
            }
            if (result is null) @result = Json::Object();
        }

        return result;
    }

    string GetToolResultJson(const Json::Value &in result) {
        return Json::Write(result);
    }

    // Editor-state snapshot cache. The chat UI rebuilds context stats every
    // frame; without a TTL this fires 4 MCP tool calls per frame (~240/s),
    // flooding the log. UI stats tolerate a stale snapshot; real requests
    // invalidate first via InvalidateEditorStateCache().
    string g_EditorStateCache = "";
    uint g_EditorStateCacheAt = 0;
    const uint EDITOR_STATE_TTL_MS = 5000;

    void InvalidateEditorStateCache() {
        g_EditorStateCacheAt = 0;
    }

    string GetEditorStateSnapshot() {
        uint now = Time::Now;
        if (g_EditorStateCacheAt > 0 && now - g_EditorStateCacheAt < EDITOR_STATE_TTL_MS) {
            return g_EditorStateCache;
        }
        g_EditorStateCache = BuildEditorStateSnapshot();
        g_EditorStateCacheAt = now;
        return g_EditorStateCache;
    }

    string BuildEditorStateSnapshot() {
        string state = "EDITOR STATE:\n";

        Json::Value@ empty = Json::Object();

        // Map info (TmMcp MapSummary: name, nbBlocks, nbItems, ...)
        Json::Value@ mapInfo = TmMcp::CallTool("GetMapInfo", empty);
        if (mapInfo !is null && mapInfo.HasKey("output")) {
            Json::Value@ mapOut = mapInfo["output"];
            string mapName = JsonX::Lookup_StringOrDefault(mapOut, "name", "unknown");
            string nbBlocks = JsonX::Lookup_StringOrDefault(mapOut, "nbBlocks", "?");
            string nbItems = JsonX::Lookup_StringOrDefault(mapOut, "nbItems", "?");
            state += "- Map: " + mapName + " (" + nbBlocks + " blocks, " + nbItems + " items)\n";
        }

        // Cursor (TmMcp GetCursor: coord, dir, blockName/blockIdName)
        Json::Value@ cursor = TmMcp::CallTool("GetCursor", empty);
        if (cursor !is null && cursor.HasKey("output")) {
            Json::Value@ curOut = cursor["output"];
            string coord = curOut.HasKey("coord") ? Json::Write(curOut["coord"]) : "[?]";
            string dir = JsonX::Lookup_StringOrDefault(curOut, "dir", "?");
            string blockName = JsonX::Lookup_StringOrDefault(curOut, "blockName", "!");
            state += "- Cursor: " + coord + " dir=" + dir + " block=" + blockName + "\n";
        }

        // Edit/placement mode (ControlEditMode status: editModeName, placeModeName)
        Json::Value@ em = TmMcp::CallTool("ControlEditMode", empty);
        if (em !is null && em.HasKey("output")) {
            Json::Value@ emOut = em["output"];
            string editMode = JsonX::Lookup_StringOrDefault(emOut, "editModeName", "");
            string placeMode = JsonX::Lookup_StringOrDefault(emOut, "placeModeName", "");
            if (editMode.Length > 0) {
                state += "- Modes: edit=" + editMode + " place=" + placeMode + "\n";
            }
        }

        // Inventory (TmMcp InventorySummary: nbBlocks, nbItems, nbMacroblocks, loadingStatusShort)
        Json::Value@ inv = TmMcp::CallTool("GetInventorySummary", empty);
        if (inv !is null && inv.HasKey("output")) {
            Json::Value@ invOut = inv["output"];
            string invStatus = JsonX::Lookup_StringOrDefault(invOut, "loadingStatusShort", "unknown");
            string nbBlocks = JsonX::Lookup_StringOrDefault(invOut, "nbBlocks", "?");
            string nbItems = JsonX::Lookup_StringOrDefault(invOut, "nbItems", "?");
            string nbMbs = JsonX::Lookup_StringOrDefault(invOut, "nbMacroblocks", "?");
            state += "- Inventory: " + invStatus + " (" + nbBlocks + " blocks, " + nbItems + " items, " + nbMbs + " macroblocks)\n";
        }

        return state.Trim();
    }
}
