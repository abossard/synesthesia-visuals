// Chimera's Breath - Fluid Simulation
// Original by nimitz 2018 (twitter: @stormoid)
// https://www.shadertoy.com/view/4tGfDW
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// Ported to Synesthesia SSF with audio reactivity

// Base Simulation: 2011 paper "Simple and fast fluids"
// (Martin Guay, Fabrice Colin, Richard Egli)
// https://hal.inria.fr/inria-00596050/document

#define dt 0.15

// Helper functions
float mag2(vec2 p) { return dot(p,p); }
float length2(vec2 p) { return dot(p,p); }

mat2 mm2(in float a) {
    float c = cos(a), s = sin(a);
    return mat2(c,s,-s,c);
}

// Animated force points (replacing mouse-only mode)
vec2 point1(float t) {
    t *= 0.62;
    return vec2(0.12, 0.5 + sin(t)*0.2);
}

vec2 point2(float t) {
    t *= 0.62;
    return vec2(0.88, 0.5 + cos(t + 1.5708)*0.2);
}

// Palette functions for coloring
vec3 getPalette(float x, vec3 c1, vec3 c2, vec3 p1, vec3 p2) {
    float x2 = fract(x/2.0);
    x = fract(x);   
    mat3 m = mat3(c1, p1, c2);
    mat3 m2 = mat3(c2, p2, c1);
    float omx = 1.0-x;
    vec3 pws = vec3(omx*omx, 2.0*omx*x, x*x);
    return clamp(mix(m*pws, m2*pws, step(x2,0.5)), 0., 1.);
}

vec4 pal(float x) {
    vec3 pal = getPalette(-x, vec3(0.2, 0.5, .7), vec3(.9, 0.4, 0.1), vec3(1., 1.2, .5), vec3(1., -0.4, -.0));
    return vec4(pal, 1.);
}

vec4 pal2(float x) {
    vec3 pal = getPalette(-x, vec3(0.4, 0.3, .5), vec3(.9, 0.75, 0.4), vec3(.1, .8, 1.3), vec3(1.25, -0.1, .1));
    return vec4(pal, 1.);
}

// Core fluid simulation solver
vec4 solveFluid(sampler2D smp, vec2 uv, vec2 w, float time) {
    float K = pressure_k;
    float v = viscosity;
    
    vec4 data = texture(smp, uv);
    vec4 tr = texture(smp, uv + vec2(w.x, 0));
    vec4 tl = texture(smp, uv - vec2(w.x, 0));
    vec4 tu = texture(smp, uv + vec2(0, w.y));
    vec4 td = texture(smp, uv - vec2(0, w.y));
    
    vec3 dx = (tr.xyz - tl.xyz)*0.5;
    vec3 dy = (tu.xyz - td.xyz)*0.5;
    vec2 densDif = vec2(dx.z, dy.z);
    
    // Density update
    data.z -= dt*dot(vec3(densDif, dx.x + dy.y), data.xyz);
    
    // Viscosity force
    vec2 laplacian = tu.xy + td.xy + tr.xy + tl.xy - 4.0*data.xy;
    vec2 viscForce = vec2(v)*laplacian;
    
    // Advection
    data.xyw = texture(smp, uv - dt*data.xy*w).xyw;
    
    // Procedural forces (animated points)
    vec2 newForce = vec2(0);
    newForce.xy += 0.75*vec2(.0003, 0.00015)/(mag2(uv - point1(time)) + 0.0001);
    newForce.xy -= 0.75*vec2(.0003, 0.00015)/(mag2(uv - point2(time)) + 0.0001);
    
    // Audio-reactive forces (reduced to prevent oversaturation)
    float bassForce = syn_BassLevel * bass_emphasis * audio_reactivity;
    float highForce = syn_HighLevel * high_emphasis * audio_reactivity;
    
    // Add bass hits as impulse forces (much gentler)
    if (syn_BassHits > 0.5) {
        newForce.xy += bassForce * 0.0003 * vec2(sin(time*2.3), cos(time*1.7));
    }
    
    // Continuous audio modulation (subtle)
    newForce *= (1.0 + bassForce * 0.1);
    
    // Update velocity
    data.xy += dt*(viscForce.xy - K/dt*densDif + newForce);
    
    // Linear velocity decay
    data.xy = max(vec2(0), abs(data.xy) - 1e-4)*sign(data.xy);
    
    // Vorticity confinement (curl stored in alpha)
    data.w = (tr.y - tl.y - tu.x + td.x);
    vec2 vort = vec2(abs(tu.w) - abs(td.w), abs(tl.w) - abs(tr.w));
    vort *= vorticity_amount/length(vort + 1e-9)*data.w;
    data.xy += vort;
    
    // Boundaries
    data.y *= smoothstep(.5, .48, abs(uv.y - 0.5));
    
    data = clamp(data, vec4(vec2(-10), 0.5, -10.), vec4(vec2(10), 3.0, 10.));
    
    return data;
}

// Main render function with pass switching
vec4 renderMain(void) {
    vec2 uv = _uv;
    vec2 w = 1.0 / RENDERSIZE.xy;
    
    // Pass 0, 1, 2: Fluid simulation (triple buffering for speed)
    if (PASSINDEX == 0) {
        // Buffer A
        vec4 data = solveFluid(bufferC, uv, w, TIME);
        
        if (FRAMECOUNT < 20) {
            data = vec4(0.5, 0, 0, 0);
        }
        
        return data;
    }
    else if (PASSINDEX == 1) {
        // Buffer B
        vec4 data = solveFluid(bufferA, uv, w, TIME);
        
        if (FRAMECOUNT < 20) {
            data = vec4(0.5, 0, 0, 0);
        }
        
        return data;
    }
    else if (PASSINDEX == 2) {
        // Buffer C
        vec4 data = solveFluid(bufferB, uv, w, TIME);
        
        if (FRAMECOUNT < 20) {
            data = vec4(0.5, 0, 0, 0);
        }
        
        return data;
    }
    else if (PASSINDEX == 3) {
        // Buffer D: Color advection and injection
        vec2 velo = texture(bufferA, uv).xy;
        vec4 col = texture(bufferD, uv - dt*velo*w*3.); // advection
        
        // Color injection at force points
        col += .0025/(0.0005 + pow(length(uv - point1(TIME)), 1.75))*dt*0.12*pal(TIME*0.05 - .0);
        col += .0025/(0.0005 + pow(length(uv - point2(TIME)), 1.75))*dt*0.12*pal2(TIME*0.05 + 0.675);
        
        // Audio-reactive color flashes (gentle)
        float highFlash = syn_HighHits * high_emphasis * audio_reactivity;
        col += clamp(highFlash * 0.0005, 0.0, 0.05) * pal2(-TIME*0.7);
        
        // Audio-modulated palette (subtle)
        float audioMod = mix(1.0, 1.0 + syn_BassPresence*0.05, audio_reactivity);
        col.rgb *= audioMod;
        
        if (FRAMECOUNT < 20) {
            col = vec4(0.);
        }
        
        col = clamp(col, 0., 2.5);  // Lower max to prevent runaway brightness
        col = max(col - (0.0002 + col*0.008), 0.); // Faster decay to recover from oversaturation
        
        return col;
    }
    else {
        // Final output (PASSINDEX 4)
        vec4 col = texture(bufferD, uv);
        
        // Boundary fade
        if (uv.y < 0.01 || uv.y >= 0.99) {
            col = vec4(0);
        }
        
        return col;
    }
}
