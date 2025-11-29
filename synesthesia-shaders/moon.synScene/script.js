var punchState = {
	amount: 0.0,
	color: [1.0, 1.0, 1.0],
	pressed: false
};

// Peak tracker for sustained crater depth
var bassPeak = 0.0;
var midPeak = 0.0;
var highPeak = 0.0;
var peakDecayRate = 0.92; // Slower decay for sustained effect

function randomColor()
{
	var h = Math.random();
	var s = 0.5 + Math.random() * 0.5;
	var v = 0.8 + Math.random() * 0.2;
	var i = Math.floor(h * 6.0);
	var f = h * 6.0 - i;
	var p = v * (1.0 - s);
	var q = v * (1.0 - f * s);
	var t = v * (1.0 - (1.0 - f) * s);
	switch (i % 6) {
		case 0: return [v, t, p];
		case 1: return [q, v, p];
		case 2: return [p, v, t];
		case 3: return [p, q, v];
		case 4: return [t, p, v];
		default: return [v, p, q];
	}
}

function update(dt)
{
	if (!dt) dt = 0.016;
	
	// Punch button logic
	var pressed = inputs.punch_button > 0.5;
	if (pressed && !punchState.pressed)
	{
		punchState.amount = 1.0;
		punchState.color = randomColor();
	}
	punchState.pressed = pressed;
	var decay = 2.5;
	punchState.amount *= Math.exp(-decay * dt);
	uniforms.burstColorR = punchState.color[0];
	uniforms.burstColorG = punchState.color[1];
	uniforms.burstColorB = punchState.color[2];
	uniforms.burstIntensity = punchState.amount;
	
	// Peak tracking for sustained audio effects
	var currentBass = inputs.syn_BassLevel || 0.0;
	var currentMid = inputs.syn_MidLevel || 0.0;
	var currentHigh = inputs.syn_HighLevel || 0.0;
	
	// Update peaks (instant attack, slow decay)
	bassPeak = Math.max(currentBass, bassPeak * peakDecayRate);
	midPeak = Math.max(currentMid, midPeak * peakDecayRate);
	highPeak = Math.max(currentHigh, highPeak * peakDecayRate);
	
	// Expose to shader as smoothed values
	uniforms.bass_peak = bassPeak;
	uniforms.mid_peak = midPeak;
	uniforms.high_peak = highPeak;
	uniforms.audio_peak = (bassPeak * 0.5 + midPeak * 0.3 + highPeak * 0.2);
}
