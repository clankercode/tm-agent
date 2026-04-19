void Main() {
    // No-op; render callbacks are hooked directly below.
}

void RenderMenu() {
    AgentUI::RenderMenu();
}

void Render() {
    AgentUI::Render();
}

void OnDestroyed() {
    AgentUI::ClearMessages();
}

void OnDisabled() {
    OnDestroyed();
}
