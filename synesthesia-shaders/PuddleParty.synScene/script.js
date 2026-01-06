function Timer () {

  this.time = 0.0;

}

Timer.prototype.updateTime = function(rate, val, dt) {

  this.time = this.time+rate*dt*val;

}

function Counter () {

  this.count = 0.0;

}

Counter.prototype.updateCount = function(val) {

  this.count += val*15.0;

}

function makeBeatRandom(initialVal) {
  var value = (typeof initialVal === 'number') ? initialVal : Math.random();
  var wait = 0.0;
  return function(dt, trigger, rate) {
    var r = Math.max(0.0001, rate || 2.0);
    if (wait > 0.0) { wait -= dt; return value; }
    if (trigger) { value = Math.random(); wait = 1.0 / r; }
    return value;
  };
}

function makeBeatOne(initialVal) {
  var value = 0.0;
  var wait = 0.0;
  return function(dt, trigger, rate) {
    var r = Math.max(0.0001, rate || 2.0);
    if (wait > 0.0) { wait -= dt; return value; }
    if (trigger) { value = 1.0; wait = 1.0 / r; }
    return value;
  };
}

function setAutoTiltON() {
  setControl("auto_tilt", 1.0);
}

function setAutoZoomON() {
  setControl("auto_zoom", 1.0);
}

function setBeatTiltOFF() {
  setControl("beat_tilt", 0.0);
}

function setBeatZoomOFF() {
  setControl("beat_zoom", 0.0);
}

// Usage:
var getAngle = makeBeatRandom();
var randB = makeBeatRandom();
var oneB = makeBeatOne();


var bassCount = new Counter();
var timevar = new Timer();
var camTimevar = new Timer();
var layerTimevar = new Timer();
var morphTimevar = new Timer();

var nRateMid = new Timer();
var fade = 0.0;
var teet = 0.0;
var edge = 0.0;

function setup() {
    onOffToOn("beat_tilt", "setAutoTiltON");
    onOffToOn("beat_zoom", "setAutoZoomON");
    onOnToOff("auto_tilt", "setBeatTiltOFF");
    onOnToOff("auto_zoom", "setBeatZoomOFF");

}

function update(dt) {

  var beat_trigger = syn_MidLevel;;
    _beat_delay = auto_beat_rise > 0.5 ? 0.0625+4.0*syn_Presence*syn_BassLevel : beat_delay;

    camTimevar.updateTime(0.45, 2.0, dt);
    timevar.updateTime(1.0 + (beat_boost > 0.5 ? syn_BassHits*ripple_rate : 0.0), ripple_rate, dt);

    layerTimevar.updateTime(syn_BassHits+0.5, travel_rate*25.0, dt);
    morphTimevar.updateTime(syn_BassHits+ 1.0, morph_rate*25.0, dt);

    bassCount.updateCount(syn_BassHits*0.0075);



    setUniform("dynamic_time", timevar.time);
    setUniform("cam_time", camTimevar.time*0.0625);
    setUniform("layer_time", layerTimevar.time);
    setUniform("morph_time", morphTimevar.time);
    setUniform("bass_count", bassCount.count);


    setUniform("rand_angle", getAngle(dt, beat_trigger > 0.9, _beat_delay)*Math.PI*2.0);
    setUniform("rand_beat_num", randB(dt, beat_trigger > 0.9, _beat_delay));
    setUniform("rand_beat_num_a", randB(dt, beat_trigger > 0.9, _beat_delay));
    setUniform("rand_beat_num_b", randB(dt, beat_trigger > 0.9, _beat_delay));
    

}