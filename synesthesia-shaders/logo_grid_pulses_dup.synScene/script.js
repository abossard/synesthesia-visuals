var pulse_transition_meter = 0.;
var grid_transition_meter = 0.;
var last_grid_type = 0.;
var last_pulse_type = 0.;
var last_x = 0.;
var last_y = 0.;
function setup() {
    setUniform("scriptTime", 0.0);
    
}

function update(dt) {
    setUniform("scriptTime", syn_CurvedTime*speed*0.1 + syn_BassTime*speed*0.125 + syn_Time*speed*0.1);

    if (squarize_grid>0.5){
        setControl("grid_size", [inputs.grid_size.x, inputs.grid_size.x])
    }

    //Reset params if grid_mode or pulse_mode changed since last frame
    if (last_grid_type !== inputs.grid_mode){
        last_grid_type = inputs.grid_mode;
        setControl("grid_param_a", 0.0);
        setControl("grid_param_b", 0.5);
        setControl("no_grid", 0.0);

    }
    if (last_pulse_type !== inputs.pulse_mode){
        last_pulse_type = inputs.pulse_mode;
        setControl("pulse_param_a", 1.0);
        setControl("pulse_param_b", 0.0);
    }
    // if (last_x !== inputs.grid_mode){

    // }


    pulse_transition_meter += pulse_auto_transition * 0.5 * (syn_Level + syn_BassHits + syn_Hits) / 60.0;
    grid_transition_meter += grid_auto_transition * 0.5 * (syn_Level + syn_MidHighHits + syn_Hits) / 60.0;
    if (pulse_transition_meter > 5.) {
        setControlNormalized('pulse_mode', Math.random())
        pulse_transition_meter = 0.;
    }
    if (grid_transition_meter > 5.) {
        setControlNormalized('grid_mode', Math.random())   
        grid_transition_meter = 0.;
    }
}