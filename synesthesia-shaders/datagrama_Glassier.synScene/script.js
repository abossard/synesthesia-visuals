function SmoothCounter () {
  this.oldCount = 0.0;
  this.isGoing = 0.0;
  this.currentValue = 0.0;
}

SmoothCounter.prototype.update = function(dt, newCount, speed) {
  this.currentValue = this.currentValue+(newCount-this.currentValue)*speed;
}

var glowTear = new SmoothCounter();

var decimator = 0;
var t = 0;

function update(dt) {

  try {
    glowTear.update(dt, inputs.glow_rip, 0.023);
    uniforms.glow_tear_scr = glowTear.currentValue;
  }  
  catch (e){
    print(e);
  }

  // timevar.updateTime(inputs.rate_in, 0.1+inputs.syn_Level+inputs.syn_HighLevel+inputs.syn_Hits*0.5, dt);
  // uniforms.script_time = timevar.time;
  // downrot.update(dt, inputs.down_rot, 0.1);
  // rightrot.update(dt, inputs.right_rot, 0.1);

  // uniforms.down_rot_scr = downrot.currentValue;
  // uniforms.right_rot_scr = rightrot.currentValue;
  // decimator++;
  // if (decimator%10==0){
  //   print(glowTear.currentValue);
  // }

}