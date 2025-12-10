function ApproachRandomSpot () {
  this.goal = 0.0;
  this.currentSpot = 0.0;
}

ApproachRandomSpot.prototype.update = function(amt) {
  this.currentSpot = this.currentSpot + (this.goal-this.currentSpot)*amt;
}

var mover = new ApproachRandomSpot();

var decimator = 0;
var time = 0;

function update(dt) {

  if (inputs.syn_OnBeat > 0.9){
    mover.goal = Math.random();
  }
  // mover.goal = 0.5+0.5*Math.sin(inputs.TIME);
  mover.update(0.02);
  uniforms.random_spot = mover.currentSpot;

  time = time+Math.pow(inputs.syn_BassLevel,2.0)*0.1*inputs.reverse*inputs.zoom_speed;

  uniforms.script_bass_time = time;

  // decimator++;
  // if (decimator%10==0){
  //   print(t);
  // }
}

function transition() {
  //log(5);
}
