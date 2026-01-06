var osscilatorKnob = 0;

//cameras
var cameraPosX = 0;
var cameraPosY = 0
var acceleratorX = 0;
var acceleratorY = 0;
var velocityX = 0;
var velocityY = 0;


//timers
var scriptBassTime = 0;
var scriptBassBeatTime = 0;
var sliderTime = 0;


function setup() {
    onOffToOn("set_bottom_layer", "setBottomLayer");
    onOffToOn("set_middle_layer", "setMiddleLayer");
    onOffToOn("set_top_layer", "setTopLayer");
    whileOn("depth_auto_pilot", "updateDepthTarget");
}

function setTopLayer() {
    setControl("depth", 0.82);
    depthDelta = 0;
    depthTarget = 0.82;
}


function setMiddleLayer() {
    setControl("depth", 0.42);
    depthDelta = 0;
    depthTarget = 0.42;
}

function setBottomLayer() {
    setControl("depth", 0.0);
    depthDelta = 0;
    depthTarget = 0.0;
}

var decimator = 0;
function update(dt) {
    osscilatorKnob = osscilatorKnob + (Math.pow(syn_Hits*0.5, 2.0)*0.5 + Math.pow(syn_BassHits*0.5, 1.5)*0.25 + Math.pow(syn_MidHits*0.5, 1.5)*0.25 + Math.pow(syn_HighHits*0.5, 1.5)*0.25)*0.25;
    var bassTimerVal = Math.pow(syn_BassPresence*0.9, 1.5)*0.3 + Math.pow(syn_BassHits*0.75, 2.0)*0.75 + Math.pow(syn_BassLevel*0.66, 1.33)*0.8;
    scriptBassTime = scriptBassTime + (bassTimerVal*0.25);
    scriptBassBeatTime = scriptBassBeatTime + bassTimerVal*(syn_BPMTwitcher % 1)*0.1*syn_BPMConfidence;
    sliderTime = sliderTime + slide_rows*slide_rows*(Math.pow(syn_Level*0.5, 2.0)*syn_Presence*0.25 + Math.pow(syn_Hits*0.66, 3.0)*syn_Presence*0.5)*0.33;
    
    updateBeatTimer();
    updateCameraPosition();
    
    setUniform("script_bass_time", scriptBassTime);
    setUniform("script_bass_beat_time", scriptBassBeatTime);
    setUniform("script_knob_time", osscilatorKnob);
    setUniform("script_slider_time", sliderTime);

    if(decimator % 200 == 0) {
        // print(cameraPosX);
    }
}

var beatTimer = 3;
var beatTimer2 = 3;
var beatTimerShouldUpdate = 0;
function updateBeatTimer() {
    if(syn_BPMConfidence < 0.25) return;

    if(beatTimer <= 0) {
        beatTimer = 8;
        beatTimerShouldUpdate = 1;
    } else {
        beatTimerShouldUpdate = 0;
        beatTimer -= syn_OnBeat;
    }
    
    if(beatTimer2 <= 0) {
        beatTimer2 = 16;
    } else {
        beatTimer2 -= syn_OnBeat;
    }
}

function step(edge, x) {
    return (x < edge) ? 0.0 : 1.0;
}

var clickAndHoldSensitivity = 0;
var isFirstFrame = true;
function updateCameraPosition() {
    if(isFirstFrame) {
        isFirstFrame = false;
        setUniform("script_drift", [0, 0]);
        return;
    }
    
    var camX = drift.x;
    var camY = drift.y;
    
    var rand1 = Math.random();
    var rand2 = Math.random();
    
    var accelYDelta = (syn_RandomOnBeat + rand1 - 1.)*beatTimerShouldUpdate*cam_auto_pilot*(0.2 + 0.8*auto_pilot_sensitivity*auto_pilot_sensitivity);
    var accelXDelta = ((1.0 - syn_RandomOnBeat) + rand2 - 1.)*beatTimerShouldUpdate*cam_auto_pilot*(0.2 + 0.8*auto_pilot_sensitivity*auto_pilot_sensitivity);
    acceleratorY = acceleratorY*0.977 + accelYDelta*step(0.5, syn_BPMConfidence);
    acceleratorX = acceleratorX*0.977 + accelXDelta*step(0.5, syn_BPMConfidence);
    
    clickAndHoldSensitivity = clickAndHoldSensitivity * 0.91 + _click.x*0.01;
    
    cameraPosX = cameraPosX  + acceleratorX*0.1 + (_muvc.x)*clickAndHoldSensitivity*0.5;
    cameraPosY = cameraPosY  + acceleratorY*0.1 + (_muvc.y)*clickAndHoldSensitivity*0.2;
    var camThreshold = 10;
    if(Math.abs(cameraPosX) > camThreshold) {
        acceleratorX = acceleratorX*0.978;
        cameraPosX = checkThreshold(cameraPosX, camThreshold);
    }
    
    if(Math.abs(cameraPosX) > camThreshold) {
        acceleratorY = acceleratorY*0.978;
        cameraPosY = checkThreshold(cameraPosY, camThreshold);
    }
    
    
    setUniform("script_drift", [cameraPosX + camX, cameraPosY + camY]);
}

var depthTarget = 0;
var depthDelta = 0;
var depthCurrentPos = 0;

function updateDepthTarget() {
    if(beatTimer2 % 16  == 0 && syn_BPMConfidence > 0.25) {
        randomizeControl("depth");
        
    }
    
}
var rightClickAndHoldSensitivity = 0;

function checkThreshold(number, threshold) {
  if (number > threshold) {
    return threshold;
  } else if (number < -threshold) {
    return -threshold;
  } else {
    return number;
  }
}