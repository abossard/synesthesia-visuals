var time = 0.;

var lastModeChange = 0.;

function handleAutoCam() {

    if(syn_BassHits > .9 && auto_cam >= 1.05) {
        var cy =  (Math.random()-.5)*2.;
        setControl("cam_lookat", cy*2.);
    } else if(auto_cam < 1. && auto_cam > 0.1) {
        setControl("cam_lookat", 4.*Math.sin(0.5*speed)*auto_cam);
    }   
}

function randomizeMode() {
    var mode =  (Math.random()*6.)-1.;
    var kaleidoscope = Math.random() <= .5 ? 0. : 1.;
    var twist = Math.random() <= .5 ? 0. : 1.;
    setControl("mode", mode);
    setControl("kaleidoscope", kaleidoscope);
    setControl("twist", twist);
    
    lastModeChange = speed;
}

function handleAutoMode() {
    
    var h =  Math.random()

    if(syn_BassHits > .8  &&  auto_pilote > .5 && (speed - lastModeChange) >= 1./(syn_BPM/60.)) {
        randomizeMode();
    }

}

function handleRecenter() {
    setControl("cam_lookat", 0.); 
}

function setup() {
    time = 0.;
    
    onOffToOn("bang_mode", "randomizeMode");
    onOnToOff("auto_cam", "handleRecenter");
}


function update(dt) {
 
    
    if(auto_cam > 0.5) {
        handleAutoCam();
    } 
    if(auto_pilote > 0.0) {
        handleAutoMode();
    }

}
