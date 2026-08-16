void Main() {
    AgentPack::Register();
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
    FollowCam::SetMode(FollowCam::ParseMode(AgentSettings::S_FollowCamMode));
    AgentPack::Register();
}

void OnEnabled() {
    AgentPack::Register();
}

void OnDestroyed() {
    AgentPack::Unregister();
    CancelCurrentRun();
}

void OnDisabled() {
    OnDestroyed();
}
