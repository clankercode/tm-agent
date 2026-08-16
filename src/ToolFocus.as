// ToolFocus.as — "view" (eye) affordance on tool-call chips: smoothly moves
// the editor camera to the position a tool call acted on.
//
// The pleasant animated move itself is E++ (SetCamAnimationGoTo, QuadOut
// easing), exposed as the tm-mcp-pack-epp.FocusCamera MCP tool. tm-agent
// stays a pure consumer: it never imports Editor directly — everything goes
// through TmMcp::CallTool, so the dependency chain for camera control is
// tm-agent -> tm-mcp-pack-epp -> Editor (E++). If the pack is missing, the
// core SetEditorCamera tool is used as a non-animated fallback.

namespace ToolFocus {

    // Parsed focus target. Grid coords are block-grid (x,y,z in block units)
    // and get converted to map meters; world coords are map meters already.
    class FocusPos {
        bool valid = false;
        vec3 pos = vec3(0);
        bool worldCoords = false;
    }

    // Block-grid -> map-meters. Mirrors E++ CoordToPos (Editor/Math.as):
    // x/z cells are 32m wide, y cells 8m tall, ground offset 64m (=8 blocks).
    vec3 GridToWorld(int gx, int gy, int gz) {
        return vec3(
            float(gx) * 32.0,
            (float(gy) - 8.0) * 8.0,
            float(gz) * 32.0
        );
    }

    float ReadNum(const Json::Value &in obj, const string &in key) {
        return float(obj[key]);
    }

    bool HasXYZ(const Json::Value &in obj) {
        return obj.HasKey("x") && obj.HasKey("y") && obj.HasKey("z");
    }

    // World-space x/y/z straight off the input object (PlaceItem-style).
    // Also accepts a pos:[x,y,z] array (driver/demo payload form), treated
    // with the same convention as the tool itself.
    FocusPos@ FromWorldXYZ(const Json::Value &in obj) {
        auto fp = FocusPos();
        if (obj is null) return fp;
        if (HasXYZ(obj)) {
            fp.pos = vec3(ReadNum(obj, "x"), ReadNum(obj, "y"), ReadNum(obj, "z"));
        } else if (obj.HasKey("pos")) {
            auto pos = obj.Get("pos");
            if (pos.GetType() == Json::Type::Array && pos.Length >= 3) {
                fp.pos = vec3(float(pos[0]), float(pos[1]), float(pos[2]));
            } else if (pos.GetType() == Json::Type::Object
                && pos.HasKey("x") && pos.HasKey("y") && pos.HasKey("z")) {
                // Pack tools emit pos as {x,y,z} objects.
                fp.pos = vec3(float(pos["x"]), float(pos["y"]), float(pos["z"]));
            } else {
                return fp;
            }
        } else {
            return fp;
        }
        fp.worldCoords = true;
        fp.valid = true;
        return fp;
    }

    // Block-grid x/y/z (core PlaceBlock-style) converted to meters; also
    // accepts pos:[x,y,z] in grid units.
    FocusPos@ FromGridXYZ(const Json::Value &in obj) {
        auto fp = FocusPos();
        if (obj is null) return fp;
        int gx, gy, gz;
        if (HasXYZ(obj)) {
            gx = int(ReadNum(obj, "x"));
            gy = int(ReadNum(obj, "y"));
            gz = int(ReadNum(obj, "z"));
        } else if (obj.HasKey("pos")) {
            auto arr = obj.Get("pos");
            if (arr is null || arr.GetType() != Json::Type::Array || arr.Length < 3) return fp;
            gx = int(float(arr[0]));
            gy = int(float(arr[1]));
            gz = int(float(arr[2]));
        } else {
            return fp;
        }
        fp.pos = GridToWorld(gx, gy, gz);
        fp.worldCoords = false;
        fp.valid = true;
        return fp;
    }

    // Which tools the eye button makes sense for, and how their inputs map to
    // positions. Pack tools are namespaced ("tm-mcp-pack-epp.PlaceBlock") —
    // compare the local part after the last '.'.
    string LocalToolName(const string &in fullName) {
        int dot = fullName.LastIndexOf(".");
        return dot < 0 ? fullName : fullName.SubStr(uint(dot) + 1);
    }

    // Tools whose call payloads name a position. The eye button shows for
    // these (a malformed payload just yields a benign error message on
    // click — the LLM-generated payloads always carry coordinates).
    bool ToolHasFocusTarget(const string &in toolName) {
        string local = LocalToolName(toolName);
        return local == "PlaceBlock"
            || local == "RemoveBlock"
            || local == "CanPlaceBlock"
            || local == "GetBlockAt"
            || local == "PlaceItem"
            || local == "FocusCamera"
            || local == "SetCamGoTo"
            || local == "PlaceNamedMacroblock"
            || local == "GetBlocks"
            || local == "GetItems"
            || local == "GetBlockLocation"
            || local == "GetItemLocation";
    }

    // Position-query tools: the agent is LOOKING at an area, not acting on a
    // single spot. GetBlocks/GetItems take an optional center x/y/z (world
    // meters) + radius; GetBlock/ItemLocation take a block index. These feed
    // the follow camera (see FollowCam::OnAgentActivity) so the user sees
    // where the agent is inspecting.
    bool IsPositionQueryTool(const string &in toolName) {
        string local = LocalToolName(toolName);
        return local == "GetBlocks"
            || local == "GetItems"
            || local == "GetBlockLocation"
            || local == "GetItemLocation";
    }

    // Returns a valid FocusPos for tools whose input names a position, or
    // null when the tool (or its payload) has nothing focusable. A malformed
    // payload (e.g. tool that should have x/y/z but doesn't) returns null —
    // the eye is only offered when there is something concrete to see.
    //
    // Coordinate conventions differ per tool and must NOT be guessed from the
    // local name alone: core PlaceBlock takes block-grid ints, while the
    // E++ pack's tm-mcp-pack-epp.PlaceBlock places free blocks at world
    // meters. Namespaced names are classified by their full form.
    bool IsPackTool(const string &in fullName) {
        return fullName.IndexOf(".") > 0;
    }

    FocusPos@ ExtractFocusPos(const string &in toolName, const Json::Value &in input) {
        string local = LocalToolName(toolName);
        FocusPos@ fp = null;
        if (local == "PlaceBlock") {
            // Core PlaceBlock (and any other grid-int variant): block grid.
            // Pack PlaceBlock places free blocks at world meters.
            @fp = IsPackTool(toolName) ? FromWorldXYZ(input) : FromGridXYZ(input);
        } else if (local == "RemoveBlock" || local == "CanPlaceBlock" || local == "GetBlockAt") {
            // Core grid tools.
            @fp = FromGridXYZ(input);
        } else if (local == "PlaceItem" || local == "FocusCamera" || local == "SetCamGoTo"
            || local == "PlaceNamedMacroblock") {
            @fp = FromWorldXYZ(input);
        } else if (local == "GetBlocks" || local == "GetItems") {
            // Query center is optional; no coords means "whole map" — nothing
            // to focus.
            @fp = FromWorldXYZ(input);
        } else if (local == "GetBlockLocation" || local == "GetItemLocation") {
            // Index-based lookup: no coords in the call. Focus happens on the
            // RESULT (handled by ProcessToolCallsImpl), not the request.
            return null;
        } else {
            return null;
        }
        if (fp is null || !fp.valid) return null;
        return fp;
    }

    // World position out of a GetBlockLocation / GetItemLocation RESULT
    // (output carries pos:{x,y,z} in world meters). Returns null when the
    // result has no position.
    FocusPos@ ExtractLocationResultPos(const Json::Value &in result) {
        if (result is null || !result.HasKey("pos")) return null;
        return FromWorldXYZ(result);
    }

    // Move the editor cursor to a world position (pack MoveCursorToWorld,
    // E++ SetAllCursorPos). Best-effort: silently skipped when the pack is
    // absent — the follow camera alone still shows the area.
    void MoveCursorToWorld(const vec3 &in worldPos) {
        Json::Value input = Json::Object();
        input["x"] = worldPos.x;
        input["y"] = worldPos.y;
        input["z"] = worldPos.z;
        try {
            TmMcp::CallTool("tm-mcp-pack-epp.MoveCursorToWorld", input);
        } catch {
            // Pack missing or tool unavailable — not user-facing.
        }
    }

    // --- Focus execution -----------------------------------------------------

    // Distance from which to view a single placed block/item.
    const float DEFAULT_VIEW_DISTANCE = 60.0;

    int g_FocusCount = 0;
    string g_LastFocusError = "";

    // Animated E++ camera move via the pack's FocusCamera tool. Returns an
    // error string, or "" on success.
    string FocusOnPos(vec3 worldPos, float distance = DEFAULT_VIEW_DISTANCE) {
        g_LastFocusError = "";
        Json::Value input = Json::Object();
        input["x"] = worldPos.x;
        input["y"] = worldPos.y;
        input["z"] = worldPos.z;
        input["distance"] = distance;

        // Animated E++ path first.
        Json::Value@ r1 = null;
        try { @r1 = TmMcp::CallTool("tm-mcp-pack-epp.FocusCamera", input); } catch {
            g_LastFocusError = "focus threw: " + getExceptionInfo();
        }
        if (r1 !is null && r1.HasKey("success") && bool(r1["success"])) {
            g_FocusCount++;
            return "";
        }

        // Fallback: core camera tool (no animation, but works without E++).
        Json::Value@ r2 = null;
        try { @r2 = TmMcp::CallTool("SetEditorCamera", input); } catch {
            g_LastFocusError = g_LastFocusError.Length > 0 ? g_LastFocusError : ("focus threw: " + getExceptionInfo());
        }
        if (r2 !is null && r2.HasKey("success") && bool(r2["success"])) {
            g_FocusCount++;
            return "";
        }

        if (g_LastFocusError.Length == 0) {
            g_LastFocusError = r1 !is null && r1.HasKey("error") ? string(r1["error"]) : "camera tools unavailable";
        }
        return g_LastFocusError;
    }

    // Focus on the position encoded in a tool-call payload. Returns "" on
    // success; otherwise a human-readable error for the chat.
    string FocusOnToolCall(const string &in toolName, const string &in inputJson) {
        Json::Value@ parsed = Json::Parse(inputJson);
        if (parsed is null || parsed.GetType() != Json::Type::Object) {
            return "cannot parse tool input";
        }
        FocusPos@ fp = ExtractFocusPos(toolName, parsed);
        if (fp is null) return "no focusable position in this call";
        return FocusOnPos(fp.pos);
    }

#if UNITTEST
    void ResetForTest() {
        g_FocusCount = 0;
        g_LastFocusError = "";
    }
#endif
}
