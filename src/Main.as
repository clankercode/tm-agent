import "AgentUI" as UI;

void Main() {
    startnew(OnLoop, 0);
}

void OnLoop() {
    while (true) {
        UI::RenderMenu();
        UI::Render();
        yield();
    }
}

void OnDestroyed() {
    AgentUI::ClearMessages();
}

void OnDisabled() {
    OnDestroyed();
}