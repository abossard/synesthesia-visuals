function BPMCounter () {

    this.time = 0.0;

    this.timer = 0.0;

    this.timerLength = 0.0;

    this.count = 0.0;

    this.timeWithinBeat = 0.0;

    this.didIncrement = 0.0;

  }

  

  BPMCounter.prototype.updateTime = function(bpm, dt) {

    this.didIncrement = 0.0;

    var amountToStepThroughBeat = bpm*dt/60.0;

    this.time = this.time+amountToStepThroughBeat;

    if(this.count != Math.floor(this.time)){

      this.count = Math.floor(this.time);

      this.didIncrement = 1.0;

    };

    this.timeWithinBeat = this.time-this.count;

  }



function Timer() {

    this.timer = 0.0;

    this.normalizedTimer = 0.0;

    this.timerLength = 1.0;

}





  Timer.prototype.setTimer = function(duration) {

    this.timer = duration;

    this.timerLength = duration;

  }



  Timer.prototype.updateTimer = function() {

    this.timer -= inputs.syn_OnBeat;

    this.normalizedTimer = this.timer / this.timerLength;





    if(this.timer < 1.) {

        this.resetTimer()

    }

  }

  

  Timer.prototype.resetTimer = function(dt) {

    this.timer = 0.0;

    this.normalizedTimer = 0.0;

    this.timerLength = 0.0;

}



  

  Timer.prototype.pingPongCounter = function() {

      

  }

  

  var bpmcount = new BPMCounter();

  var decimator = 0;

  var tAtLast0 = 0;

  var bpmTime = 0;

  var bassT = 0.0;

  var trebleT = 0.0;

  var intesityPulser = 0.0;

  var particlesTimer = new Timer();

  var circlesTimer = new Timer();

  var jumpersTimer = new Timer();

  var mediaTimer = new Timer();

  

  function update(dt) {

    var bpm = inputs.syn_BPM/4.0;

    bpmcount.updateTime(bpm, dt);

  

    uniforms.script_time = bpmcount.time;

    bassT = bassT + Math.pow(inputs.syn_BassLevel*0.5,2.0)*0.5 + 1.5*(Math.pow(inputs.syn_BassHits*0.5,2.0) + Math.pow(inputs.syn_BassPresence*0.5, 2.0)*0.75);

    uniforms.script_bass_time = bassT;

  

    trebleT = trebleT + Math.pow(inputs.syn_HighLevel*0.5,2.0)*0.5 + Math.pow(inputs.syn_HighHits*0.5,2.0)*0.5;

    uniforms.script_high_time = trebleT;

    

    uniforms.scriptParticlePulse = particlesTimer.normalizedTimer;

    uniforms.scriptCirclesPulse = circlesTimer.normalizedTimer;

    uniforms.scriptJumpersPulse = jumpersTimer.normalizedTimer;

    uniforms.scriptMediaPulse = mediaTimer.normalizedTimer;





        // bpmcount.setTimer(4); 

    if(inputs.pulse_particles > 0.9) {

     particlesTimer.setTimer(16);   

    }

    if(inputs.pulse_circles > 0.9) {

     circlesTimer.setTimer(16);   

    }

    if(inputs.pulse_jumpers > 0.9) {

     jumpersTimer.setTimer(16);   

    }

    if(inputs.pulse_media > 0.9) {

     mediaTimer.setTimer(16);   

    }





    particlesTimer.updateTimer();

    circlesTimer.updateTimer();

    jumpersTimer.updateTimer();

    mediaTimer.updateTimer();



    intesityPulser = intesityPulser + Math.pow(inputs.syn_Hits*0.5, 2.0)*0.3*inputs.syn_Intensity;

    intesityPulser = intesityPulser - dt;

    intesityPulser = Math.min(intesityPulser, 1.0);

    intesityPulser = Math.max(intesityPulser, 0.0);

    uniforms.script_intensity_pulser = intesityPulser;





    decimator++;

    if (decimator%200==0){

    }

  }

  

  