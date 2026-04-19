namespace CameraFocus {
    // Block dims (TM2020 standard): 32m x 8m x 32m. baseHeightOffset = 64m.
    vec3 BlockCoordToMidpoint(int x, int y, int z) {
        return vec3(
            float(x) * 32.0 + 16.0,
            (float(y) - 8.0) * 8.0 + 4.0,
            float(z) * 32.0 + 16.0
        );
    }

    void SetTarget(const vec3 &in pos) {
        auto app = cast<CGameManiaPlanet>(GetApp());
        if (app is null) return;
        auto editor = cast<CGameCtnEditorFree>(app.Editor);
        if (editor is null) return;
        // Set PluginMapType first (engine clamps it); then OrbitalCameraControl so camera actually updates.
        editor.PluginMapType.CameraTargetPosition = pos;
        if (editor.OrbitalCameraControl !is null) {
            editor.OrbitalCameraControl.m_TargetedPosition = pos;
        }
    }

    void FocusOnBlockCoord(int x, int y, int z) {
        SetTarget(BlockCoordToMidpoint(x, y, z));
    }

    void FocusOnWorldPos(float x, float y, float z) {
        SetTarget(vec3(x, y, z));
    }

    bool TryFocusFromJsonCoord(const Json::Value@ obj) {
        if (obj is null || obj.GetType() != Json::Type::Object) return false;
        if (obj.HasKey("coord")) {
            const Json::Value@ coord = obj["coord"];
            if (coord.GetType() == Json::Type::Array && coord.Length >= 3) {
                FocusOnBlockCoord(int(coord[0]), int(coord[1]), int(coord[2]));
                return true;
            }
        }
        if (obj.HasKey("position")) {
            const Json::Value@ pos = obj["position"];
            if (pos.GetType() == Json::Type::Array && pos.Length >= 3) {
                FocusOnWorldPos(float(pos[0]), float(pos[1]), float(pos[2]));
                return true;
            }
        }
        if (obj.HasKey("x") && obj.HasKey("y") && obj.HasKey("z")) {
            FocusOnBlockCoord(int(obj["x"]), int(obj["y"]), int(obj["z"]));
            return true;
        }
        return false;
    }

    void TryFocusFromResult(const Json::Value@ result, const Json::Value@ input = null) {
        if (result !is null && result.GetType() == Json::Type::Object && result.HasKey("output")) {
            const Json::Value@ output = result["output"];
            if (TryFocusFromJsonCoord(output)) return;
        }
        TryFocusFromJsonCoord(input);
    }
}
