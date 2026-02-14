var state = {
    beatCount: 0,
    lastOnBeat: 0.0,
    energy: 0.0,
    pulse: 0.0,
    fatigue: 0.0,
    activity: 0.0,
    themeA: 1.0,
    themeB: 2.0,
    blend: 0.0,
    randomLatch: 0.5,
    lastThemeControl: -999.0
};

function clamp(v, lo, hi)
{
    return Math.max(lo, Math.min(hi, v));
}

function smooth(current, target, speed, dt)
{
    var k = 1.0 - Math.exp(-speed * dt);
    return current + (target - current) * k;
}

function edgeRise(value, prev)
{
    return value > 0.5 && prev <= 0.5;
}

function update(dt)
{
    if (!dt || dt <= 0.0) dt = 0.016;
    dt = Math.min(dt, 0.05);

    var onBeat = inputs.syn_OnBeat || 0.0;
    var beatTriggered = edgeRise(onBeat, state.lastOnBeat);
    state.lastOnBeat = onBeat;

    var intensity = inputs.syn_Intensity || 0.0;
    var presence = inputs.syn_Presence || 0.0;
    var bassHits = inputs.syn_BassHits || 0.0;
    var highHits = inputs.syn_HighHits || 0.0;
    var bassLevel = inputs.syn_BassLevel || 0.0;
    var highLevel = inputs.syn_HighLevel || 0.0;
    var level = inputs.syn_Level || 0.0;

    // Ignore noise floor so idle input does not keep the scene twitching.
    var signal = Math.max(
        intensity * 0.9,
        presence * 0.75,
        bassLevel * 0.8,
        highLevel * 0.7,
        level * 0.85,
        bassHits * 0.8,
        highHits * 0.7
    );
    var activityTarget = clamp((signal - 0.14) / 0.30, 0.0, 1.0);
    state.activity = smooth(state.activity, activityTarget, 1.8, dt);
    var quietGate = state.activity;

    // Ignore BPM clock when the input signal is effectively silent.
    var beatActive = state.activity > 0.10;
    if (beatTriggered && beatActive) {
        state.beatCount += 1;
        state.randomLatch = inputs.syn_RandomOnBeat || Math.random();
    }

    // Long-term activity damper to prevent run-away intensity over long sections.
    var musicalLoad = clamp(intensity * 0.6 + presence * 0.4, 0.0, 1.0);
    var fatigueTarget = clamp((musicalLoad - 0.35) / 0.65, 0.0, 1.0);
    state.fatigue = smooth(state.fatigue, fatigueTarget, 0.55, dt);
    var calm = (1.0 - 0.45 * state.fatigue) * quietGate;

    var hitEnergy = (bassHits * 0.45 + highHits * 0.25) * calm;
    var targetEnergy = clamp((intensity * 0.45 + presence * 0.18 + hitEnergy * 0.22) * calm, 0.0, 1.1);
    state.energy = smooth(state.energy, targetEnergy, 2.0, dt);

    state.pulse = Math.max(0.0, state.pulse - dt * 1.6);
    state.pulse = Math.max(state.pulse, hitEnergy * 0.38 + (onBeat > 0.5 ? 0.10 * state.activity : 0.0));

    var autoStory = (inputs.story_auto || 0.0) > 0.5;
    var manualTheme = clamp(inputs.theme_mode || 1.0, 0.0, 4.0);

    if (autoStory) {
        var cycleBeats = Math.max(8.0, inputs.story_cycle_beats || 32.0);
        var transition = clamp(inputs.story_transition || 0.25, 0.05, 0.49);
        var variation = clamp(inputs.story_variation || 0.35, 0.0, 1.0);
        var hardCuts = (inputs.story_hardcuts || 0.0) > 0.5;

        var chapterFloat = state.beatCount / cycleBeats;
        var chapter = Math.floor(chapterFloat) % 5;
        var local = chapterFloat - Math.floor(chapterFloat);

        // Small chance to skip ahead on high-energy beats for less predictable storytelling.
        if (beatTriggered && state.energy > 0.9) {
            if (Math.random() < 0.008 * variation) {
                chapter = (chapter + 1 + Math.floor(state.randomLatch * 2.99)) % 5;
            }
        }

        var nextChapter = (chapter + 1) % 5;
        var blendStart = 1.0 - transition;
        var blend = clamp((local - blendStart) / transition, 0.0, 1.0);
        if (hardCuts) {
            blend = blend >= 1.0 ? 1.0 : 0.0;
        }

        state.themeA = chapter;
        state.themeB = nextChapter;
        state.blend = blend;

        // Keep UI dropdown in sync with autopilot chapter progression.
        var uiTheme = hardCuts ? chapter : (chapter + blend);
        if (Math.abs(uiTheme - state.lastThemeControl) > 0.002) {
            setControl("theme_mode", uiTheme);
            state.lastThemeControl = uiTheme;
        }
    } else {
        state.themeA = Math.floor(manualTheme);
        state.themeB = Math.min(4.0, state.themeA + 1.0);
        state.blend = manualTheme - state.themeA;
        state.lastThemeControl = manualTheme;
    }

    uniforms.story_theme_a = state.themeA;
    uniforms.story_theme_b = state.themeB;
    uniforms.story_theme_blend = state.blend;
    uniforms.story_energy = state.energy;
    uniforms.story_pulse = state.pulse;
    uniforms.story_damp = calm;
    uniforms.story_activity = state.activity;
    uniforms.story_beats = state.beatCount;
}
