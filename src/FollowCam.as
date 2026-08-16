// FollowCam.as — follow camera for the working agent.
//
// While the agent works, every positional tool activity (PlaceBlock,
// PlaceItem, …) retargets the editor camera so the user can watch the agent
// build. The editor's orbital camera IS the sphere model: the camera sits on
// a sphere of radius `CameraToTargetDistance` around `CameraTargetPosition`
// at (h, v) angles — choosing angles + distance implies the position.
//
// Modes:
//   off        — never move the camera (manual control stays with the user).
//   steps      — one E++ animated hop (QuadOut, ~350 ms) per retarget; the
//                same primitive as the eye button, paced by a deadband so
//                nearby work doesn't spam hops.
//   swing      — smooth per-frame follow: position eases toward the target
//                while the camera orbits on a sine (H) + slower sine (V)
//                so reversals ease through zero velocity; height/angle
//                wander instead of parking. Never fully static.
//   cinematic  — like swing but lazier constants, wider orbit, and slight
//                distance breathing; made for watching from afar.
//
// Smooth modes write the public engine camera members directly (same members
// SetEditorCamera writes; identical pattern to CameraFocus.as) rather than
// going through MCP per frame — a 60 fps tool-call channel would flood the
// log and the socket server.
//
// The feature is only active while the agent is busy (a run in flight);
// between runs the user keeps full manual camera control. Steps mode uses
// the MCP path (pack FocusCamera/SetCamGoTo), so E++ animation works there
// without any per-frame writes.

namespace FollowCam {

    enum FollowMode {
        Off = 0,
        Steps = 1,
        Swing = 2,
        Cinematic = 3
    }

    // Persisted selection (see Settings S_FollowCamMode). Swing is the
    // default: it satisfies "automatically on" while staying pleasant.
    FollowMode g_Mode = FollowMode::Swing;

    bool g_AgentBusy = false;

    // Stats/verification.
    int g_FollowCount = 0;
    int g_DeferredCount = 0;
    string g_LastError = "";

    // Deadband: activities within this radius of the current follow target
    // don't retarget (avoids hop-spam while the agent works one area).
    const float DEADBAND_METERS = 96.0;

    // Swing-mode orbit shape (radians). Phase orbit stays inside these.
    const float SWING_V_MIN = 0.25;
    const float SWING_V_MAX = 0.75;
    const float SWING_H_AMP = 0.85;
    const float SWING_V_CENTER = 0.50;
    const float SWING_V_AMP = 0.18;
    const float SWING_PHASE_RATE = 0.22;      // rad/s (~28s full H cycle)
    const float CINE_PHASE_RATE  = 0.10;
    const float SWING_V_PHASE_K  = 0.63;      // incommensurate so the path doesn't close
    const float SWING_V_PHASE_OFF = 1.1;
    const float SWING_PHASE_WRAP = 628.31854; // 100 * 2*pi; 100 H = 63 V cycles

    // Per-frame smoothing constants.
    const float SWING_LERP = 4.0;        // target-position ease (per second)
    const float CINE_LERP  = 1.6;
    const float SWING_DIST = 140.0;
    const float CINE_DIST  = 260.0;

    // Runtime follow state (smooth modes).
    ToolFocus::FocusPos@ g_PendingTarget = null;
    vec3 g_FollowPos = vec3(0);
    bool g_HasFollowPos = false;
    float g_CurrentH = 0.4;
    float g_CurrentV = 0.45;
    float g_CurrentDist = SWING_DIST;
    float g_OrbitPhase = 0.0;
    float g_OrbitBaseH = 0.0;

    // Start the orbit on the current heading so enabling swing doesn't
    // yank yaw toward 0. Phase 0 => H = base (sin 0); velocity follows cos.
    void SeedOrbitFromCurrent() {
        g_OrbitBaseH = g_CurrentH;
        g_OrbitPhase = 0.0;
    }

    // ------------------------------------------------------------------
    // Mode plumbing
    // ------------------------------------------------------------------

    string ModeToString(FollowMode m) {
        switch (m) {
            case FollowMode::Off: return "off";
            case FollowMode::Steps: return "steps";
            case FollowMode::Swing: return "swing";
            case FollowMode::Cinematic: return "cinematic";
        }
        return "off";
    }

    FollowMode ParseMode(const string &in s) {
        string t = s.ToLower();
        if (t == "steps") return FollowMode::Steps;
        if (t == "swing") return FollowMode::Swing;
        if (t == "cinematic") return FollowMode::Cinematic;
        return FollowMode::Off;
    }

    void SetMode(FollowMode m) {
        if (m == g_Mode) return;
        g_Mode = m;
        g_HasFollowPos = false;
        g_LastError = "";
        // Re-seed from the engine camera so a newly-enabled smooth mode
        // starts from where the user's camera actually is.
        if (m == FollowMode::Swing || m == FollowMode::Cinematic) {
            ReadEngineCamera();
            SeedOrbitFromCurrent();
        }
    }

    void SetAgentBusy(bool busy) {
        g_AgentBusy = busy;
    }

    bool IsActive() {
        return g_Mode != FollowMode::Off && g_AgentBusy;
    }

    // ------------------------------------------------------------------
    // Engine camera access (public members; same writes as
    // SetEditorCamera / CameraFocus.as — no per-frame MCP calls)
    // ------------------------------------------------------------------

    bool GetEditorCamera(CGameCtnEditorFree@ &out editor) {
        @editor = cast<CGameCtnEditorFree>(GetApp().Editor);
        return editor !is null && editor.PluginMapType !is null;
    }

    void ReadEngineCamera() {
        CGameCtnEditorFree@ editor;
        if (!GetEditorCamera(editor)) return;
        g_CurrentH = editor.PluginMapType.CameraHAngle;
        g_CurrentV = editor.PluginMapType.CameraVAngle;
        g_CurrentDist = editor.PluginMapType.CameraToTargetDistance;
        g_FollowPos = editor.PluginMapType.CameraTargetPosition;
        g_HasFollowPos = true;
    }

    void WriteEngineCamera(CGameCtnEditorFree@ editor, const vec3 &in pos, float h, float v, float dist) {
        auto pmt = editor.PluginMapType;
        pmt.CameraTargetPosition = pos;
        pmt.CameraToTargetDistance = dist;
        pmt.CameraHAngle = h;
        pmt.CameraVAngle = v;
        if (editor.OrbitalCameraControl !is null) {
            editor.OrbitalCameraControl.m_TargetedPosition = pos;
            editor.OrbitalCameraControl.m_CameraToTargetDistance = dist;
        }
    }

    // ------------------------------------------------------------------
    // Activity intake
    // ------------------------------------------------------------------

    // Called for every executed agent tool call. Non-positional tools are
    // ignored cheaply. Returns true when this activity retargeted the camera.
    bool OnAgentActivity(const string &in toolName, Json::Value@ input) {
        if (g_Mode == FollowMode::Off) return false;

        ToolFocus::FocusPos@ fp = ToolFocus::ExtractFocusPos(toolName, input);
        if (fp is null || !fp.valid) return false;

        return Retarget(fp.pos);
    }

    // Position-query results (GetBlockLocation etc.) arrive with an explicit
    // world position — same retarget path as tool inputs.
    bool OnQueryResultPos(const vec3 &in target) {
        if (g_Mode == FollowMode::Off) return false;
        return Retarget(target);
    }

    bool Retarget(const vec3 &in target) {

        // First activity after enable: prime the goal WITHOUT a discrete
        // move — smooth modes start easing from wherever the user's camera
        // is; steps waits for the next real displacement. Avoids a jarring
        // jump the instant a run starts.
        if (g_PendingTarget is null || !g_PendingTarget.valid) {
            SetPendingTarget(target);
            if (g_Mode != FollowMode::Steps) {
                ReadEngineCamera();
                SeedOrbitFromCurrent();
            }
            g_DeferredCount++;
            return false;
        }

        // Deadband: skip retarget if we're already following this area
        // (measured against the current goal, not the easing position).
        float d = (target - g_PendingTarget.pos).Length();
        if (d < DEADBAND_METERS) {
            g_DeferredCount++;
            // Smooth modes refine the goal inside the deadband so fine
            // work stays centered without a visible retarget.
            if (g_Mode != FollowMode::Steps) g_PendingTarget.pos = target;
            return false;
        }

        if (g_Mode == FollowMode::Steps) {
            // One animated hop through the MCP surface (same primitive as
            // the eye button; E++ QuadOut ~350 ms when the pack is present).
            string err = ToolFocus::FocusOnPos(target, StepsDistance());
            if (err.Length > 0) {
                g_LastError = err;
                return false;
            }
        }

        SetPendingTarget(target);
        g_FollowCount++;
        return true;
    }

    void SetPendingTarget(const vec3 &in target) {
        if (g_PendingTarget is null) @g_PendingTarget = ToolFocus::FocusPos();
        g_PendingTarget.pos = target;
        g_PendingTarget.worldCoords = true;
        g_PendingTarget.valid = true;
    }

    float StepsDistance() {
        // Watch from reasonably afar: a few blocks' distance.
        return 120.0;
    }

    // ------------------------------------------------------------------
    // Per-frame update (smooth modes)
    // ------------------------------------------------------------------

    // Test-visible angle generators. Phase advances monotonically; H/V are
    // sines of that phase so velocity goes to zero at extrema (no snap reverse)
    // and V wanders instead of parking at the midpoint.
    float PhaseRate() {
        return g_Mode == FollowMode::Cinematic ? CINE_PHASE_RATE : SWING_PHASE_RATE;
    }

    float NextSwingH() {
        g_OrbitPhase += PhaseRate() * FrameDt();
        if (g_OrbitPhase > SWING_PHASE_WRAP) g_OrbitPhase -= SWING_PHASE_WRAP;
        g_CurrentH = g_OrbitBaseH + SWING_H_AMP * Math::Sin(g_OrbitPhase);
        return g_CurrentH;
    }

    float NextSwingV() {
        float pv = g_OrbitPhase * SWING_V_PHASE_K + SWING_V_PHASE_OFF;
        g_CurrentV = SWING_V_CENTER + SWING_V_AMP * Math::Sin(pv);
        g_CurrentV = Math::Clamp(g_CurrentV, SWING_V_MIN, SWING_V_MAX);
        return g_CurrentV;
    }

    vec3 LerpVec3(const vec3 &in a, const vec3 &in b, float t) {
        return a + (b - a) * t;
    }

    float FrameDt() {
        // Fixed step keeps motion stable and unit-testable.
        return 1.0 / 60.0;
    }

    // Called every frame from Main.as Update (all builds; cheap no-op when
    // off/steps/idle).
    void Update() {
        if (g_Mode == FollowMode::Off || g_Mode == FollowMode::Steps) return;
        if (!g_AgentBusy) return;

        CGameCtnEditorFree@ editor;
        if (!GetEditorCamera(editor)) return;

        bool cine = (g_Mode == FollowMode::Cinematic);
        float lerpK = Math::Min(1.0, (cine ? CINE_LERP : SWING_LERP) * FrameDt());
        float dist = cine ? CINE_DIST : SWING_DIST;

        if (g_PendingTarget !is null && g_PendingTarget.valid) {
            g_FollowPos = LerpVec3(g_FollowPos, g_PendingTarget.pos, lerpK);
        }

        float h = NextSwingH();
        float v = NextSwingV();

        // Cinematic distance breathing (±8%).
        if (cine) {
            float t = float(Time::Now % 9000) / 9000.0;
            dist = dist * (1.0 + 0.08 * Math::Sin(t * (Math::PI * 2.0)));
        }

        WriteEngineCamera(editor, g_FollowPos, h, v, dist);
        g_CurrentDist = dist;
    }

#if UNITTEST
    void ResetForTest() {
        g_FollowCount = 0;
        g_DeferredCount = 0;
        g_LastError = "";
        g_AgentBusy = false;
        @g_PendingTarget = null;
        g_HasFollowPos = false;
        g_Mode = FollowMode::Swing;
        g_CurrentH = 0.4;
        g_CurrentV = 0.45;
        g_OrbitPhase = 0.0;
        SeedOrbitFromCurrent();
    }
#endif
}
