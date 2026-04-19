namespace BorderEffect {
    // Draw a 4-sided animated gradient "swirl" border around the current window.
    // The four corner colors rotate between `colorA` and `colorB` over time, creating
    // gradients on each side that appear to swirl around the frame.
    //
    // Call this AFTER UI::Begin() and inside the window's scope, so GetWindowPos/Size
    // resolve to the current window. Pair with `UI::PushStyleVar(WindowBorderSize, 0)`
    // (or set Col::Border alpha to 0) to replace ImGui's built-in border cleanly.
    //
    //   tSec:        -1.0 uses Time::Now; pass a value to drive manually.
    //   speedHz:     full corner rotations per second (default 0.2 = one every 5s)
    //   thickness:   border thickness in px (default 1.5)
    //   alpha:       overall border alpha (default 0.55)
    void Swirl(
        float tSec = -1.0,
        const vec4 &in colorA = vec4(0.95, 0.65, 0.15, 1.0),
        const vec4 &in colorB = vec4(0.00, 0.82, 0.95, 1.0),
        float speedHz = 0.2,
        float thickness = 1.5,
        float alpha = 0.55
    ) {
        if (tSec < 0.0) tSec = float(Time::Now) / 1000.0;

        vec2 winPos = UI::GetWindowPos();
        vec2 winSize = UI::GetWindowSize();
        // Snap to integer pixel boundaries so all four edges rasterize at the
        // same thickness — fractional positions anti-alias asymmetrically.
        float x0 = Math::Floor(winPos.x);
        float y0 = Math::Floor(winPos.y);
        float x1 = Math::Floor(winPos.x + winSize.x);
        float y1 = Math::Floor(winPos.y + winSize.y);
        float t = Math::Max(1.0, Math::Floor(thickness));

        // Each corner's lerp phase (0..1..0) driven by time, offset by corner index
        // to create a chase around the perimeter.
        float phase = (tSec * speedHz) % 1.0;
        if (phase < 0.0) phase += 1.0;

        // Smooth triangle wave 0..1..0 — 2|p - 0.5| then invert to get a ping-pong
        // between colorA and colorB at each corner.
        array<vec4> corners = { vec4(0,0,0,0), vec4(0,0,0,0), vec4(0,0,0,0), vec4(0,0,0,0) };
        for (int i = 0; i < 4; i++) {
            float p = (phase + float(i) * 0.25) % 1.0;
            float m = 1.0 - Math::Abs(p - 0.5) * 2.0; // triangle wave 0..1..0
            // Soften with a cos ease so the transition feels smooth, not linear.
            m = 0.5 - 0.5 * Math::Cos(m * Math::PI);
            corners[i] = vec4(
                colorA.x + (colorB.x - colorA.x) * m,
                colorA.y + (colorB.y - colorA.y) * m,
                colorA.z + (colorB.z - colorA.z) * m,
                alpha
            );
        }
        // corners: 0=TL, 1=TR, 2=BR, 3=BL

        // Use the window drawlist (not foreground) so the border respects
        // z-order and gets clipped when other windows overlap us.
        auto dl = UI::GetWindowDrawList();
        // Draw each side as a thin gradient rect. Corners match window corners so
        // adjacent sides share a color → continuous gradient around the perimeter.

        // Top bar: UL=TL, UR=TR, BL=TL-dim, BR=TR-dim (thin strip, cols near-identical vertically)
        dl.AddRectFilledMultiColor(
            vec4(x0, y0, winSize.x, t),
            corners[0], corners[1], corners[0], corners[1]
        );
        // Bottom bar
        dl.AddRectFilledMultiColor(
            vec4(x0, y1 - t, winSize.x, t),
            corners[3], corners[2], corners[3], corners[2]
        );
        // Left bar
        dl.AddRectFilledMultiColor(
            vec4(x0, y0, t, winSize.y),
            corners[0], corners[0], corners[3], corners[3]
        );
        // Right bar
        dl.AddRectFilledMultiColor(
            vec4(x1 - t, y0, t, winSize.y),
            corners[1], corners[1], corners[2], corners[2]
        );
    }

    // Plain solid border — for states where the animated swirl would be
    // too much (e.g. the "waiting for editor" placeholder). Matches Swirl's
    // pixel-snapping so both variants render at identical thickness.
    void Static(
        const vec4 &in color = vec4(0.30, 0.33, 0.38, 0.90),
        float thickness = 1.0
    ) {
        vec2 winPos = UI::GetWindowPos();
        vec2 winSize = UI::GetWindowSize();
        float x0 = Math::Floor(winPos.x);
        float y0 = Math::Floor(winPos.y);
        float x1 = Math::Floor(winPos.x + winSize.x);
        float y1 = Math::Floor(winPos.y + winSize.y);
        float t = Math::Max(1.0, Math::Floor(thickness));

        auto dl = UI::GetWindowDrawList();
        dl.AddRectFilled(vec4(x0, y0, winSize.x, t), color);
        dl.AddRectFilled(vec4(x0, y1 - t, winSize.x, t), color);
        dl.AddRectFilled(vec4(x0, y0, t, winSize.y), color);
        dl.AddRectFilled(vec4(x1 - t, y0, t, winSize.y), color);
    }
}
