var shape_opts = 8;

function ShapeBlender() {
    this.x = 0 // shape a (0 to shape_opts)
    this.y = 1 // shape b (0 to shape_opts)
    this.z = 0 // shape blend amt (0 to 1)
    this.zgoal = 0 // active shape (0 to 1)
}

ShapeBlender.prototype.pushnum = function(num) {
    if (typeof num != 'number') 
        num = Math.floor(Math.random()*shape_opts)
        
    if (this.zgoal==0) {
        this.y = num;
        this.zgoal=1
    } else {
        this.x = num;
        this.zgoal=0
    }
}

ShapeBlender.prototype.tick = function() {
    var zdist = this.z - this.zgoal
    this.z -= zdist * inputs.morph_speed
}

var last_beat = 0;

var shaper = new ShapeBlender;
uniforms.shaper = shaper;

function beatShaper() {
    if (
        inputs.morph_on_beat > 0.5 &&
        Math.abs(shaper.z-shaper.zgoal)<0.1 &&
        last_beat > shape_min_duration
        ) {
            shaper.pushnum()
            console.log(JSON.stringify({
                x: shaper.x,
                y: shaper.y,
                z: shaper.z,
                zgoal: shaper.zgoal,
                last_beat: last_beat
            }))
            last_beat=0
    }
}

function bangShaper() {
    console.log(Math.abs(shaper.z-shaper.zgoal))

    if (Math.abs(shaper.z-shaper.zgoal)<0.1)
        shaper.pushnum()
    // console.log(shaper.x+' '+shaper.y+' '+shaper.z)
}

function pickShape() {
    shaper.pushnum(pick_shape)
}

function setup() {
    console.log(shaper.x+' '+shaper.y)
    onOffToOn('syn_OnBeat','beatShaper')
    onOffToOn('random_shape','bangShaper')
    onChange('pick_shape','pickShape')
}

function update(dt) {
    last_beat++
    shaper.tick()
}