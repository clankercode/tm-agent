void Main() {
    // No-op; render callbacks are hooked directly below.
}

void RenderMenu() {
    AgentUI::RenderMenu();
}

void Render() {
    AgentUI::Render();
}

#if DEV
void Update(float dt) {
    AgentDriver::Poll();
}
#endif

void OnDestroyed() {
    CancelCurrentRun();
}

void OnDisabled() {
    OnDestroyed();
}
