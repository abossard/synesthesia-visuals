var scriptTime = 0;

function update(dt) {
    scriptTime = scriptTime + dt*0.25 + Math.pow(syn_Presence*0.75, 2.0)*0.1*reactivetime;
    
    setUniform("script_reactive_time", scriptTime);
}