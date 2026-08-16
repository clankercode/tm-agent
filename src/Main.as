void Main() {
    // No-op; render callbacks are hooked directly below.
}

void RenderMenu() {
    AgentUI::RenderMenu();
}

void RenderInterface() {
    AgentUI::Render();
}

void Update(float dt) {
    FollowCam::Update();
#if DEV
    AgentDriver::Poll();
#endif
}

void OnSettingsLoadFailed() {}

void OnInit() {
    // Follow-cam mode persists via settings; S_FollowCamMode is loaded by
    // the time OnInit runs.
    FollowCam::SetMode(FollowCam::ParseMode(AgentSettings::S_FollowCamMode));
}

void OnDestroyed() {
    CancelCurrentRun();
}

void OnDisabled() {
    OnDestroyed();
}
