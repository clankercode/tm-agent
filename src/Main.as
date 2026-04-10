void Main() {
    startnew(OnLoop, 0);
}

void OnLoop() {
    while (true) {
        AgentUI::RenderMenu();
        AgentUI::Render();
        yield();
    }
}

void OnDestroyed() {
    AgentUI::ClearMessages();
}

void OnDisabled() {
    OnDestroyed();
}