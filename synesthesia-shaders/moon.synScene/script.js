var punchState = {
	amount: 0.0,
	color: [1.0, 1.0, 1.0],
	pressed: false
};

var bassPeak = 0.0;
var midPeak = 0.0;
var highPeak = 0.0;
var peakDecayRate = 0.92;

var dustState = {
	charge: 0.0,
	release: 0.0,
	releaseProgress: 1.0,
	cooldown: 0.0,
	mode: 0,
	lastAutoBeat: -1
};

var meteorState = {
	active: false,
	pos: [0.0, 0.0],
	dir: [1.0, -0.3],
	speed: 0.0,
	length: 0.0,
	strength: 0.0,
	life: 0.0,
	cooldown: 0.0,
	triggerPressed: false,
	lastBeatSlot: -1
};

var driftState = {
	x: 0.0,
	y: 0.0,
	phase: 0.0
};

var wobbleState = {
	drive: 0.0,
	levelSmooth: 0.0,
	hitSmooth: 0.0
};

function clamp01(v)
{
	return Math.max(0.0, Math.min(1.0, v));
}

function clamp(v, lo, hi)
{
	return Math.max(lo, Math.min(hi, v));
}

function expSmoothing(current, target, speed, dt)
{
	var t = 1.0 - Math.exp(-speed * dt);
	return current + (target - current) * t;
}

function expSmoothingAsymmetric(current, target, riseSpeed, fallSpeed, dt)
{
	var speed = target > current ? riseSpeed : fallSpeed;
	var t = 1.0 - Math.exp(-speed * dt);
	return current + (target - current) * t;
}

function randomColor()
{
	var h = Math.random();
	var s = 0.4 + Math.random() * 0.35;
	var v = 0.82 + Math.random() * 0.18;
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

function beginDustRelease(strength, releaseSize)
{
	var scaled = clamp(strength, 0.0, 1.4);
	dustState.release = Math.max(dustState.release, 0.4 + scaled * (0.95 + releaseSize * 0.8));
	dustState.releaseProgress = 0.0;
	dustState.charge *= 0.2;
	dustState.cooldown = 1.4 + (1.0 - releaseSize) * 1.2;
	dustState.mode = 2;
}

function beginMeteor(force)
{
	var startX = (Math.random() * 2.4) - 1.2;
	var startY = 0.45 + Math.random() * 0.65;

	var dirX = (Math.random() * 1.6) - 0.8;
	var dirY = -(0.35 + Math.random() * 0.5);
	var mag = Math.sqrt(dirX * dirX + dirY * dirY);
	if (mag < 1e-4) mag = 1.0;
	dirX /= mag;
	dirY /= mag;

	meteorState.active = true;
	meteorState.pos[0] = startX;
	meteorState.pos[1] = startY;
	meteorState.dir[0] = dirX;
	meteorState.dir[1] = dirY;
	meteorState.speed = 0.14 + force * 0.34;
	meteorState.length = 0.55 + force * 0.95;
	meteorState.strength = 0.65 + force * 1.45;
	meteorState.life = 0.0;
	meteorState.cooldown = 0.9 + Math.random() * 1.9;
}

function update(dt)
{
	if (!dt || dt <= 0.0) dt = 0.016;
	dt = Math.min(dt, 0.05);

	var bass = inputs.syn_BassLevel || 0.0;
	var mid = inputs.syn_MidLevel || 0.0;
	var high = inputs.syn_HighLevel || 0.0;
	var bassHits = inputs.syn_BassHits || 0.0;
	var highHits = inputs.syn_HighHits || 0.0;
	var midHighHits = inputs.syn_MidHighHits || 0.0;
	var intensity = inputs.syn_Intensity || 0.0;
	var onBeat = inputs.syn_OnBeat || 0.0;
	var beatTime = inputs.syn_BeatTime || 0.0;
	var synTime = inputs.syn_Time || 0.0;
	var bassTime = inputs.syn_BassTime || 0.0;
	var midHighTime = inputs.syn_MidHighTime || 0.0;
	var randomOnBeat = inputs.syn_RandomOnBeat || 0.5;
	var beatSlot = Math.floor(beatTime * 2.0);

	var starfieldSpeed = clamp(inputs.starfield_speed || 0.25, 0.0, 1.0);
	var meteorChance = clamp(inputs.meteor_chance || 0.35, 0.0, 1.0);
	var meteorPeakThreshold = clamp(inputs.meteor_peak_threshold || 0.82, 0.35, 1.0);
	var meteorIntensity = clamp(inputs.meteor_intensity || 0.4, 0.0, 1.0);
	var chargeRate = Math.max(0.0, inputs.dust_charge_rate || 0.55);
	var releaseThreshold = clamp(inputs.dust_release_threshold || 0.9, 0.2, 1.0);
	var releaseSize = clamp(inputs.dust_release_size || 0.58, 0.0, 1.0);
	var calmLock = (inputs.calm_lock || 0.0) > 0.5;

	// Manual trigger handling via punch button and release bang.
	var punchPressed = (inputs.punch_button || 0.0) > 0.5;
	var releaseBang = (inputs.release_trigger || 0.0) > 0.2;
	var releasePressed = releaseBang || punchPressed;
	if (releasePressed && !punchState.pressed) {
		punchState.amount = 1.0;
		punchState.color = randomColor();
		beginDustRelease(1.0, releaseSize);
	}
	punchState.pressed = releasePressed;
	punchState.amount *= Math.exp(-2.5 * dt);

	// Smooth wobble drive so geometry reacts like a liquid body, not a transient spike.
	wobbleState.levelSmooth = expSmoothing(wobbleState.levelSmooth, bass, 5.2, dt);
	wobbleState.hitSmooth = expSmoothingAsymmetric(
		wobbleState.hitSmooth,
		clamp01(bassHits),
		11.0,
		2.8,
		dt
	);
	var wobbleTarget = clamp(
		wobbleState.levelSmooth * 0.78 + wobbleState.hitSmooth * 0.28 + intensity * 0.05,
		0.0,
		1.25
	);
	wobbleState.drive = expSmoothingAsymmetric(wobbleState.drive, wobbleTarget, 6.2, 1.9, dt);

	// Peak tracking with slow decay for sustained behavior.
	bassPeak = Math.max(bass, bassPeak * peakDecayRate);
	midPeak = Math.max(mid, midPeak * peakDecayRate);
	highPeak = Math.max(high, highPeak * peakDecayRate);

	// Dust build-up + release state machine.
	var highEnergy = high * 0.55 + mid * 0.2 + highHits * 0.8 + midHighHits * 0.45;
	var chargeIn = highEnergy * (0.22 + 0.55 * chargeRate) + intensity * 0.08;
	var chargeOut = 0.24 + (1.0 - high) * 0.28;
	dustState.charge += (chargeIn - chargeOut) * dt;
	dustState.charge = clamp(dustState.charge, 0.0, 1.35);

	var peakGate = Math.max(highHits, midHighHits * 0.85);
	var strongPeak = peakGate > (0.18 + (1.0 - releaseThreshold) * 0.2)
		&& highPeak > releaseThreshold * 0.82;
	var autoReleaseReady = !calmLock
		&& dustState.cooldown <= 0.0
		&& dustState.charge >= releaseThreshold
		&& strongPeak
		&& beatSlot != dustState.lastAutoBeat;
	if (autoReleaseReady) {
		var relStrength = clamp(dustState.charge * 0.8 + highPeak * 0.5 + highHits * 0.8, 0.0, 1.3);
		beginDustRelease(relStrength, releaseSize);
		dustState.lastAutoBeat = beatSlot;
	}

	if (dustState.release > 0.001) {
		var releaseDecay = 2.0 + (1.0 - releaseSize) * 1.4;
		dustState.release *= Math.exp(-releaseDecay * dt);
		dustState.releaseProgress += dt * (0.55 + releaseSize * 1.25);
		dustState.mode = 2;
	} else {
		dustState.release = 0.0;
		dustState.releaseProgress = 1.0;
		if (dustState.cooldown > 0.0) {
			dustState.mode = 3;
		} else if (dustState.charge > 0.25) {
			dustState.mode = 1;
		} else {
			dustState.mode = 0;
		}
	}
	dustState.cooldown = Math.max(0.0, dustState.cooldown - dt);

	// Occasional meteors on very high peaks.
	meteorState.cooldown = Math.max(0.0, meteorState.cooldown - dt);
	var meteorTriggerPressed = (inputs.meteor_trigger || 0.0) > 0.2;
	if (meteorTriggerPressed && !meteorState.triggerPressed) {
		beginMeteor(0.9 + highPeak * 0.5);
	}
	meteorState.triggerPressed = meteorTriggerPressed;

	if (beatSlot !== meteorState.lastBeatSlot) {
		meteorState.lastBeatSlot = beatSlot;
		var canSpawnMeteor = !meteorState.active
			&& meteorState.cooldown <= 0.0
			&& !calmLock
			&& highPeak >= meteorPeakThreshold
			&& highHits > 0.06;
		if (canSpawnMeteor) {
			var chance = meteorChance * (0.35 + 0.65 * clamp01(highPeak));
			if (Math.random() < chance) {
				beginMeteor(clamp(highPeak * 0.9 + highHits * 0.8, 0.0, 1.2));
			}
		}
	}

	if (meteorState.active) {
		meteorState.life += dt;
		meteorState.pos[0] += meteorState.dir[0] * meteorState.speed * dt;
		meteorState.pos[1] += meteorState.dir[1] * meteorState.speed * dt;
		meteorState.strength *= Math.exp(-0.95 * dt);

		var offScreen = meteorState.pos[0] < -1.6 || meteorState.pos[0] > 1.6
			|| meteorState.pos[1] < -1.2 || meteorState.pos[1] > 1.4;
		if (meteorState.life > 2.6 || meteorState.strength < 0.02 || offScreen) {
			meteorState.active = false;
		}
	}

	// Slow drift to make starfield + grid feel like camera movement.
	driftState.phase += dt * (0.08 + 0.1 * starfieldSpeed + 0.05 * bass);
	var targetDriftX = Math.sin(driftState.phase * 0.73 + bassTime * 0.04) * 0.3;
	targetDriftX += Math.sin(synTime * 0.035) * 0.16;
	targetDriftX += (randomOnBeat - 0.5) * onBeat * 0.24;

	var targetDriftY = Math.cos(driftState.phase * 0.52 + midHighTime * 0.05) * 0.22;
	targetDriftY += Math.sin(synTime * 0.022) * 0.1;
	targetDriftY += (bassHits - 0.1) * 0.06;

	driftState.x = expSmoothing(driftState.x, targetDriftX, 2.3, dt);
	driftState.y = expSmoothing(driftState.y, targetDriftY, 2.0, dt);

	var backgroundMotion = clamp01(intensity * 0.55 + highPeak * 0.3 + bassPeak * 0.2);

	// Existing burst uniforms.
	uniforms.burstColorR = punchState.color[0];
	uniforms.burstColorG = punchState.color[1];
	uniforms.burstColorB = punchState.color[2];
	uniforms.burstIntensity = punchState.amount;

	// Audio peaks.
	uniforms.bass_peak = bassPeak;
	uniforms.mid_peak = midPeak;
	uniforms.high_peak = highPeak;
	uniforms.audio_peak = (bassPeak * 0.5 + midPeak * 0.3 + highPeak * 0.2);
	uniforms.wobble_drive = wobbleState.drive;
	uniforms.wobble_hit = wobbleState.hitSmooth;

	// Dust build/release uniforms.
	uniforms.dust_charge = clamp01(dustState.charge / 1.2);
	uniforms.dust_release = dustState.release;
	uniforms.dust_ring = clamp01(dustState.releaseProgress);
	uniforms.dust_mode = dustState.mode;
	uniforms.dust_cooldown = dustState.cooldown;

	// Background drift uniforms.
	uniforms.bg_drift_x = driftState.x;
	uniforms.bg_drift_y = driftState.y;
	uniforms.bg_motion = backgroundMotion;

	// Meteor uniforms.
	uniforms.meteor_active = meteorState.active ? 1.0 : 0.0;
	uniforms.meteor_pos_x = meteorState.pos[0];
	uniforms.meteor_pos_y = meteorState.pos[1];
	uniforms.meteor_dir_x = meteorState.dir[0];
	uniforms.meteor_dir_y = meteorState.dir[1];
	uniforms.meteor_length = meteorState.length;
	uniforms.meteor_strength = meteorState.strength * (0.75 + meteorIntensity * 2.2);
}
