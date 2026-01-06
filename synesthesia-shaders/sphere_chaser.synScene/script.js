function Timer () {

  this.time = 0.0;

}

Timer.prototype.updateTime = function(rate, val, dt) {

  this.time = this.time+rate*dt*val;

}

var constTimevar = new Timer();
var bassTimevar = new Timer();
var midTimevar = new Timer();
var midHighTimevar = new Timer();
var fade = 0.0;

function update(dt) {

    bassTimevar.updateTime(inputs.audio_speed*0.5, (inputs.syn_BassLevel*2.0+inputs.syn_BassPresence+inputs.syn_BassHits*2.0)*2.5, dt);
    constTimevar.updateTime(inputs.const_speed*0.5, (inputs.syn_BassLevel*2.0+inputs.syn_BassPresence+inputs.syn_BassHits*2.0)*2.5, dt);
    

    uniforms.bass_time = bassTimevar.time;
    uniforms.const_time = constTimevar.time;
    uniforms.sinBTime = Math.sin(bassTimevar.time);
    uniforms.cosBTime = Math.cos(bassTimevar.time*2.0);

    midTimevar.updateTime(inputs.audio_speed, (inputs.syn_MidLevel*2.0+inputs.syn_MidPresence+inputs.syn_MidHits*2.0)*2.5, dt);
    midHighTimevar.updateTime(inputs.audio_speed, (inputs.syn_MidHighLevel*2.0+inputs.syn_MidHighPresence+inputs.syn_MidHighHits*2.0)*2.5, dt);

    uniforms.mid_time = midTimevar.time;
    uniforms.midHigh_time = midHighTimevar.time;


    uniforms._sphere_space = inputs.syn_BassPresence*inputs.syn_BassPresence;
    fade = (inputs.bass_fade > 0.5 ? (1.0 - inputs.syn_BassPresence)*0.05 : inputs.fb_fade);
    uniforms.traceMix = (1.0 - fade) + 0.07*fade; 

    uniforms.gooey = inputs.bass_goo > 0.5 && syn_Presence > 0.5 ? syn_MidLevel*20.0 : inputs._gooey;

}