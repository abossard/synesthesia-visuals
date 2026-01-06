function expDec(x, k, m) {
  return Math.min(1., Math.pow(2.0, - k * x * m)*m);
}

function expImpulse(x, k, m) {
    var h = k*x;
    return h*Math.exp(1.0-h);
}

function mix(x, y, a) {
    return x * (1 - a) + y * a;
}

function BeatCounter() {
  this.count = 0;
  this.countLast = 0;


  this.beat8x = 0;
  this.beat16x = 0;


  this.updateBeat = function(dt) {

    var beat = syn_BPMTwitcher;
    
 
    if(beat % 8 == 0. ) {
      this.beat8x = 0.;
    }
    if(beat % 16 == 0. ) {
      this.beat16x = 0.;
    }


    this.beat8x += dt;
    this.beat16x += dt;

    setUniform("syn_Beat8", this.beat8x/8.*syn_BPM/60.);
    setUniform("syn_Beat16", this.beat16x/16.*syn_BPM/60.);

  }
}

var beatCounter = new BeatCounter();
var state = {};

function toggleOn(param) {
    setUniform(param, 1.);
}

function toggleOff(param) {
    setUniform(param, 0.);
}

function onExplodeOrb(value, prev) {
    setControl('object_circle', 1.);
}

function onBangExplode(value, prev) {
    setControl('exploding_orb', 1.);
}

function onMandala(value, prev) {
    setControl('glow_intensity', .5);
}

function onColorMod(value, prev) {
    setControl('color_range', .1);
}

function onTimeFreeze(value, prev) {
    
    if(state.timeFrozen) {
        console.log("time frozen, unfreeze time. lastSpeed = ", state.lastSpeed);
        state.timeFrozen = false;
        state.dirtyFlag = false;
        setControl('speed', state.lastSpeed);
    } else {
        console.log("time running, freeze time. speed = ", state.lastSpeed);
        state.timeFrozen = true;
        
        state.dirtyFlag = true;
        state.lastSpeed = speed;
        setControl('speed', 0);
    }
}

function onSpeedChange(value, prev) {
    if(state.timeFrozen && !state.dirtyFlag) {
        state.timeFrozen = false;
    } 
}

function resetBeatControls() {
    toggleOff('beat_glow');
    toggleOff('beat_size');
    toggleOff('beat_rings');
    toggleOff('beat_twist');
    toggleOff('beat_object_size');
    toggleOff('beat_explode');
    toggleOff('beat_fold');
    toggleOff('beat_duplicate');
    toggleOff('beat_cam');
    toggleOff('beat_mandala');
    toggleOff('beat_toggle_lines');
    toggleOff('beat_erode');
    toggleOff('beat_wobble');
}

function inBetween(v, a, b) {
    return (v >= a && v < b);
}

function setBeatControls() {
    resetBeatControls();
    
    if(audio_reactivity > 0. && audio_reactivity < 0.25) {
        toggleOn('beat_glow');
        toggleOn('beat_twist');
        toggleOn('beat_wobble');

    } else if(audio_reactivity >= .25 && audio_reactivity < 0.5) {
        toggleOn('beat_twist');
        toggleOn('beat_rings');
        toggleOn('beat_glow');
        toggleOn('beat_object_size');
    
    } else if(audio_reactivity >= .5 && audio_reactivity < 0.75) {
        toggleOn('beat_twist');
        toggleOn('beat_rings');
        toggleOn('beat_glow');
        toggleOn('beat_object_size');
        toggleOn('beat_fold');
        toggleOn('beat_erode');
    } else if(audio_reactivity >= .75) { 
        toggleOn('beat_twist');
        toggleOn('beat_rings');
        toggleOn('beat_glow');
        toggleOn('beat_duplicate');
        toggleOn('beat_object_size');
        toggleOn('beat_cam');
        toggleOn('beat_mandala');
        toggleOn('beat_toggle_lines');
        toggleOn('beat_erode');
    }
    if(audio_reactivity >= .9) { 
        toggleOn('beat_twist');
        toggleOn('beat_rings');
        toggleOn('beat_glow');
        toggleOn('beat_fold');
        toggleOn('beat_object_size');
        toggleOn('beat_explode');
        toggleOn('beat_erode');
    }
}

function resetEnergyControls() {
    toggleOff('glow_orb');
    toggleOff('energy_lines');
    toggleOff('energy_pentagon');
    toggleOff('show_planet_rings');
}

function setEnergyControls() {
    
    resetEnergyControls();
    
    if(inBetween(energy_mode, 1, 2 )) {
        toggleOn('glow_orb');
    } else if(inBetween(energy_mode, 2, 3 )) {
        toggleOn('show_planet_rings');
    } else if(inBetween(energy_mode, 3, 4 )) {
        toggleOn('energy_lines');
    } else if(inBetween(energy_mode, 4, 5 )) {
        toggleOn('show_planet_rings');
        toggleOn('glow_orb');
    } else if(inBetween(energy_mode, 5, 6 )) {
        toggleOn('energy_lines');
        toggleOn('glow_orb');
    } else if(inBetween(energy_mode, 6, 7 )) {
        toggleOn('energy_lines');
        toggleOn('glow_orb');
    } else if(inBetween(energy_mode, 7, 8 )) {
        toggleOn('energy_lines');
        toggleOn('energy_pentagon');
        toggleOn('glow_orb');
    } else if(inBetween(energy_mode, 8, 9 )) {
        toggleOn('energy_lines');
        toggleOn('show_planet_rings');
        toggleOn('glow_orb');
    } else if(inBetween(energy_mode, 9, 11 )) {
        toggleOn('energy_lines');
        toggleOn('show_planet_rings');
        toggleOn('glow_orb');
        toggleOn('energy_pentagon');
    }
}


function setup() {
    resetBeatControls();
    resetEnergyControls();
    
    state.timeFrozen = 0.;
    
    state.time = 0;
    setUniform('time', 0);
    
    onOffToOn('mandala', 'onMandala');
    
    onOffToOn('alternate_color', 'onColorMod');
    onOffToOn('time_freeze', 'onTimeFreeze');
    
    onChange('speed', 'onSpeedChange');
}


function update(dt) {
    beatCounter.updateBeat(dt);
    
    state.time += speed*dt;
    
    setUniform('time', state.time);
    
    setBeatControls();
    setEnergyControls();
    
    if(bang_explode > 0.) setUniform('particle_size', .2);
    // quality setControl

}
