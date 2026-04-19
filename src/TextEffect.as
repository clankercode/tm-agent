namespace TextEffect {
    // ---- math helpers ----------------------------------------------------

    vec4 LerpColor(const vec4 &in a, const vec4 &in b, float t) {
        return vec4(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.z + (b.z - a.z) * t,
            a.w + (b.w - a.w) * t
        );
    }

    float CosEase(float t) {
        return 0.5 - 0.5 * Math::Cos(Math::Clamp(t, 0.0, 1.0) * Math::PI);
    }

    // Weight as a function of absolute distance from wave center, in "chars".
    // 1.0 at center, 0.0 outside halfWidth. `peakWidth` (0..1) keeps weight = 1.0
    // for the inner fraction — gives a hotter plateau before the cos rolloff.
    float WaveWeight(float dist, float halfWidth, float peakWidth = 0.25) {
        if (dist >= halfWidth) return 0.0;
        float plateau = halfWidth * peakWidth;
        if (dist <= plateau) return 1.0;
        float rolloff = (dist - plateau) / (halfWidth - plateau);
        return CosEase(1.0 - rolloff);
    }

    // Current wave center position in char-space for a single wave.
    //   direction: signed speed multiplier. +1 = left-to-right, -1 = right-to-left.
    //              Magnitude scales speed (e.g. -2.0 = right-to-left at 2x).
    //   phaseOffsetChars: shifts this wave's cycle by N chars (use with DoubleWave).
    float ComputeWavePos(
        float tSec,
        int n,
        float halfWidth,
        float speedCharsPerSec,
        float direction,
        float pauseFrac,
        float phaseOffsetChars
    ) {
        float effSpeed = Math::Abs(direction) * speedCharsPerSec;
        float travel = float(n - 1) + halfWidth * 2.0;
        float cycle = travel * (1.0 + pauseFrac);
        float phase = (tSec * effSpeed + phaseOffsetChars) % cycle;
        if (phase < 0.0) phase += cycle;
        if (direction >= 0.0) {
            return -halfWidth + phase;
        }
        return float(n - 1) + halfWidth - phase;
    }

    // ---- core render -----------------------------------------------------

    // Render `label` char-by-char with up to 2 waves blending additively onto `normalCol`.
    // Each wave contributes `(highlight_i - normalCol) * weight_i`. Overlapping waves
    // brighten further (clamped at 1.0). Per-char glow is scaled by the strongest wave.
    void RenderTwoWaves(
        const string &in label,
        const vec4 &in normalCol,
        const vec4 &in hlA, float posA, float halfA, float peakA,
        bool useB,
        const vec4 &in hlB, float posB, float halfB, float peakB
    ) {
        int n = label.Length;
        if (n == 0) return;

        vec2 winPos = UI::GetWindowPos();
        vec2 cur = UI::GetCursorPos();
        float x = winPos.x + cur.x;
        float y = winPos.y + cur.y - UI::GetScrollY();

        auto dl = UI::GetWindowDrawList();
        float totalW = 0;

        for (int i = 0; i < n; i++) {
            string ch = label.SubStr(i, 1);
            vec2 sz = UI::MeasureString(ch);

            float wA = WaveWeight(Math::Abs(float(i) - posA), halfA, peakA);
            float wB = useB ? WaveWeight(Math::Abs(float(i) - posB), halfB, peakB) : 0.0;

            // Additive-delta blend: each wave pushes the color toward its highlight.
            vec4 col = vec4(
                Math::Clamp(normalCol.x + (hlA.x - normalCol.x) * wA + (hlB.x - normalCol.x) * wB, 0.0, 1.0),
                Math::Clamp(normalCol.y + (hlA.y - normalCol.y) * wA + (hlB.y - normalCol.y) * wB, 0.0, 1.0),
                Math::Clamp(normalCol.z + (hlA.z - normalCol.z) * wA + (hlB.z - normalCol.z) * wB, 0.0, 1.0),
                normalCol.w
            );

            vec2 at = vec2(x + totalW, y);
            float wMax = Math::Max(wA, wB);
            if (wMax > 0.25) {
                // Pick the glow color from whichever wave is hotter at this char.
                vec4 glowSrc = (wA >= wB) ? hlA : hlB;
                vec4 glow = vec4(glowSrc.x, glowSrc.y, glowSrc.z, (wMax - 0.25) * 0.55);
                dl.AddText(at + vec2(1, 0), glow, ch);
                dl.AddText(at - vec2(1, 0), glow, ch);
            }
            dl.AddText(at, col, ch);
            totalW += sz.x;
        }

        UI::Dummy(vec2(totalW, UI::GetTextLineHeight()));
    }

    // ---- public API ------------------------------------------------------

    // Single wave. `tSec = -1.0` uses Time::Now; pass any value to drive the phase manually.
    void Wave(
        const string &in label,
        float tSec = -1.0,
        const vec4 &in normalCol = vec4(0.78, 0.82, 0.88, 1.0),
        const vec4 &in highlightCol = vec4(1.00, 0.88, 0.45, 1.0),
        float waveWidthChars = 7.0,
        float speedCharsPerSec = 6.0,
        float pauseFrac = 0.5,
        float direction = 1.0,
        float peakWidth = 0.25
    ) {
        int n = label.Length;
        if (n == 0) return;
        if (tSec < 0.0) tSec = float(Time::Now) / 1000.0;

        float half = waveWidthChars * 0.5;
        float pos = ComputeWavePos(tSec, n, half, speedCharsPerSec, direction, pauseFrac, 0.0);
        RenderTwoWaves(label, normalCol, highlightCol, pos, half, peakWidth, false, highlightCol, 0.0, half, peakWidth);
    }

    void WaveCentered(
        const string &in label,
        float tSec = -1.0,
        const vec4 &in normalCol = vec4(0.78, 0.82, 0.88, 1.0),
        const vec4 &in highlightCol = vec4(1.00, 0.88, 0.45, 1.0),
        float waveWidthChars = 7.0,
        float speedCharsPerSec = 6.0,
        float pauseFrac = 0.5,
        float direction = 1.0,
        float peakWidth = 0.25
    ) {
        float textW = UI::MeasureString(label).x;
        UI::SetCursorPosX((UI::GetWindowSize().x - textW) * 0.5);
        Wave(label, tSec, normalCol, highlightCol, waveWidthChars, speedCharsPerSec, pauseFrac, direction, peakWidth);
    }

    // Two waves with independent direction/speed multipliers and a phase offset between them.
    //   directionA/B: signed speed multipliers. e.g. (1, -1) = one each way at base speed;
    //                 (1, 2) = both LTR, second one twice as fast.
    //   offsetChars:  wave B's phase is shifted by this many chars relative to wave A.
    //                 Useful for creating a "chase" or counter-phase effect.
    //   highlightColA/B: peak color for each wave. Where they overlap, deltas add.
    void DoubleWave(
        const string &in label,
        float tSec = -1.0,
        const vec4 &in normalCol = vec4(0.78, 0.82, 0.88, 1.0),
        const vec4 &in highlightColA = vec4(1.00, 0.88, 0.45, 1.0),
        const vec4 &in highlightColB = vec4(0.20, 0.90, 1.00, 1.0),
        float directionA = 1.0,
        float directionB = -1.0,
        float offsetChars = 0.0,
        float waveWidthChars = 7.0,
        float speedCharsPerSec = 6.0,
        float pauseFrac = 0.5,
        float peakWidth = 0.25
    ) {
        int n = label.Length;
        if (n == 0) return;
        if (tSec < 0.0) tSec = float(Time::Now) / 1000.0;

        float half = waveWidthChars * 0.5;
        float posA = ComputeWavePos(tSec, n, half, speedCharsPerSec, directionA, pauseFrac, 0.0);
        float posB = ComputeWavePos(tSec, n, half, speedCharsPerSec, directionB, pauseFrac, offsetChars);

        RenderTwoWaves(
            label,
            normalCol,
            highlightColA, posA, half, peakWidth,
            true,
            highlightColB, posB, half, peakWidth
        );
    }

    void DoubleWaveCentered(
        const string &in label,
        float tSec = -1.0,
        const vec4 &in normalCol = vec4(0.78, 0.82, 0.88, 1.0),
        const vec4 &in highlightColA = vec4(1.00, 0.88, 0.45, 1.0),
        const vec4 &in highlightColB = vec4(0.20, 0.90, 1.00, 1.0),
        float directionA = 1.0,
        float directionB = -1.0,
        float offsetChars = 0.0,
        float waveWidthChars = 7.0,
        float speedCharsPerSec = 6.0,
        float pauseFrac = 0.5,
        float peakWidth = 0.25
    ) {
        float textW = UI::MeasureString(label).x;
        UI::SetCursorPosX((UI::GetWindowSize().x - textW) * 0.5);
        DoubleWave(
            label, tSec, normalCol,
            highlightColA, highlightColB,
            directionA, directionB, offsetChars,
            waveWidthChars, speedCharsPerSec, pauseFrac, peakWidth
        );
    }
}
