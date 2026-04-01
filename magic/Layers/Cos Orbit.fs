/*{
    "DESCRIPTION": "Converted ISF version of wave and point shader with custom controls.",
    "CATEGORIES": [ "Generator" ],
    "INPUTS": [
        {
            "NAME": "phase",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "lineThickness",
            "TYPE": "float",
            "DEFAULT": 0.1,
            "MIN": 0.01,
            "MAX": 1.0
        },
        {
            "NAME": "pointThickness",
            "TYPE": "float",
            "DEFAULT": 0.3,
            "MIN": 0.01,
            "MAX": 1.0
        },
        {
            "NAME": "pitch",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "yaw",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "glow",
            "TYPE": "float",
            "DEFAULT": 0.45,
            "MIN": 0.1,
            "MAX": 0.5
        },
               
         {
            "NAME": "waveScale",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 1.0,
            "MAX": 5.0
        }

    ]
}*/


// slightly modded and parametirized (is that a word?) version of
// https://www.shadertoy.com/view/XfXGz4 by the great ChunderFPV


#define A(v) mat2(cos(m.v + radians(vec4(0.0, -90.0, 90.0, 0.0))))  // rotate
#define W(v) length(vec3(p.yz - v(p.x + vec2(0.0, pi_2) + t), 0.0)) - lineThickness  // wave
#define P(v) length(p - vec3(0.0, v(t), v(t + pi_2))) - pointThickness  // point

void main() {
    float pi = 3.1416;
    float pi2 = pi * 2.0;
    float pi_2 = pi / 2.0;
    float t = pi * phase * 2.;
    float s = 1.0, d = 0.0, i = d;
    
    vec2 R = RENDERSIZE.xy;
    vec2 m = vec2(pitch * pi * 2., yaw * pi * 2.);
    
    vec3 o = vec3(0.0, 0.0, -7.0); // cam
    vec3 u = normalize(vec3((gl_FragCoord.xy - 0.5 * R) / R.y, 1.0));
    vec3 c = vec3(0.0), k = c, p;
    
    // Set rotation matrices for pitch and yaw
    mat2 v = A(y);
    mat2 h = A(x);
    
    // Raymarch 25
    for (float i = 0.; i < 35.0; i++) {
        p = o + u * d;
        p.yz *= v;
        p.xz *= h;
        //p.x -= 13.0; // Slide objects to the right a bit
        
        // Reflect into negative y
        //if (p.y < -1.5) p.y = 2.0 / p.y;
        
        // Calculate wave and point distances
        k.x = min(max(p.x * 1. + lineThickness, W(sin)), P(sin))   * waveScale; // Sine wave
        k.y = min(max(p.x * 1. + lineThickness, W(cos)), P(cos))  * waveScale; // Cosine wave
        s = min(s, min(k.x, k.y)); // Blend
        
        // Break condition for raymarching
        if (s < 0.001 || d > 100.0) break;
        d += s * 0.5;
    }
    
    // Add and color the scene
    c = max(cos(d * pi2) -  s * sqrt(d * (0.6 - glow) ) - k, 0.0);
    c.gb += 0.01;
    c = c * 0.2 + c.brg * 0.9 + c * c;
    gl_FragColor = vec4(c * c, 1.0);
}
