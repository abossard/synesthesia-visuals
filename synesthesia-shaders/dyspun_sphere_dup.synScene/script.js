function Timer () {
  this.time = 0.0;
}

Timer.prototype.updateTime = function(rate, val, dt) {
  this.time = this.time+rate*dt*val;
}

function getRandomInt(currentInt, totalOptions) {
  randomInt = 0;
  do {
        randomInt = Math.floor(Math.random() * totalOptions); // Generates a random integer from 0 to totalOptions
    }
  while (randomInt == currentInt);
  
  return randomInt;
}

function randomShape() {
    upperBound = 17;
    if (inputs.FPS_Boost > 0.5) upperBound = 4; // Set a high performance mode
    setControl("Shape_Type", getRandomInt(inputs.Shape_Type, upperBound/*4*//*12*//*17*/)); // value 0-16 to represent each of the 17 choices
}

function randomShape2() {
    upperBound = 4;
    if (inputs.FPS_Boost > 0.5) upperBound = 3; // Set a high performance mode
    setControl("Sphere_Type", getRandomInt(inputs.Sphere_Type, upperBound/*3*//*4*/)); // value 0-3 to represent each of the 4 choices
}

function randomColor() {
    setControl("Color_Palette", getRandomInt(inputs.Color_Palette, 8)); // value 0-7 to represent each of the 8 choices
}

function randomOnBassHit() {
    beatCount4 ++/*, print(beatCount4)*/;
    if (beatCount4 > 1) {
        setUniform("randomBassHit", Math.random());
        beatCount4 = 0;
    }
}

function randomPan() {
    setUniform("randomPan", Math.random());
}

function randomPan2() {
    setUniform("randomPan2", Math.random());
}

function randomPan3() {
    setUniform("randomPan3", Math.random());
}

function autoShape() {
    if (Auto_Shape > 0.5) beatCount ++/*, print(beatCount)*/;
    if (beatCount > 3) {
    randomShape();
    beatCount = 0;
    }
}

function autoShape2() {
    if (Auto_Sphere_Shape > 0.5) beatCount2 ++/*, print(beatCount2)*/;
    if (beatCount2 > 7) {
    randomShape2();
    beatCount2 = 0;
    }
}

function autoColor() {
    if (Auto_Color > 0.5) beatCount3 ++/*, print(beatCount3)*/;
    if (beatCount3 > 3) {
    randomColor();
    beatCount3 = 0;
    }
}

function enableMediaColor() {
    setControl("Media_Color", 1.);
}

function blackFog() {
    setControl("Palette_Fog", 0.);
    setControl("Hypno_Fog", 0.);
    setControl("Fog_Color", [0., 0., 0.]);
}

function setup() {
    rateTime = new Timer();
    setUniform('script_time', 0);
    setUniform('script_time_spin', 0);
    setUniform('script_time_camera', 0);
    setUniform('randomPan', 0);
    setUniform('randomPan2', 0);
    setUniform('randomPan3', 0);
    setUniform('randomBassHit', 0);
    beatCount = 0;
    beatCount2 = 0;
    beatCount3 = 0;
    beatCount4 = 0;
    onOffToOn("Random_Shape", "randomShape")
    onOffToOn("Random_Sphere_Shape", "randomShape2")
    onOffToOn("Random_Color_Palette", "randomColor")
    onOffToOn("syn_BassHits", "autoShape")
    onOffToOn("syn_MidHits", "autoColor")
    onOffToOn("syn_OnBeat", "randomPan")
    onOffToOn("syn_OnBeat", "randomPan2")
    onOffToOn("syn_OnBeat", "randomPan3")
    onOffToOn("syn_BassHits", "autoShape2")
    onOffToOn("Black_Fog", "blackFog")
    onOffToOn("syn_BassHits", "randomOnBassHit")
    scriptTimeSpin = 0;
    scriptTimeCam = new Timer();
    /*scriptLimit = 0;*/
}

function update(dt) {

  try {
    rateTime.updateTime(inputs.Travel_Speed, 0.5+inputs.syn_BassLevel+inputs.syn_BassHits+inputs.syn_BassPresence, dt);
  }  
  catch (e){
    print(e);
  }
  
  setUniform('script_time', rateTime.time);
  
  scriptTimeSpin += (syn_BassLevel * 0.0005 + 0.001) * Rotate_Space;
  setUniform('script_time_spin', scriptTimeSpin)
  
  /*scriptTimeCam += 2 * Rotate_Camera;*/
  try {
    scriptTimeCam.updateTime(inputs.Travel_Speed, 0.1 + ((Rotate_Camera * 0.25)  * syn_BassLevel * syn_Intensity), dt);
  }  
  catch (e){
    print(e);
  }
  setUniform('script_time_camera', scriptTimeCam.time);
  
  /*audioPres = syn_BassPresence;
  audioHits = syn_BassHits;
  if ( scriptLimit == 0){
  setControl("meta/playback_speed",((audioPres*0.45+audioHits*0.55)*(1.0-.45)+.45)*.85); // RIP audio reactive playback
  }
  if (scriptLimit == 10) scriptLimit = 0;
  scriptLimit++;*/
}
