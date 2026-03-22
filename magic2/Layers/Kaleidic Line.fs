/*{
    "DESCRIPTION": "Kaleidoscopic Bloom - A pulsating kaleidoscope effect",
    "INPUTS": [
        {"NAME": "rotationSpeed", "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0},
        {"NAME": "patternComplexity", "TYPE": "float", "DEFAULT": 1.5, "MIN": 1.0, "MAX": 3.0},
        {"NAME": "speed", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.1, "MAX": 2.0}
    ]
}*/

#define PI 3.1415926538
#define TAU 6.2831855

vec3 palette(float t) {
    vec3 a = vec3(0.5);
    vec3 b = vec3(0.5);
    vec3 c = vec3(1.0);
    vec3 d = vec3(abs(0.2 * sin(TIME * 0.1)), abs(sin(TIME * 0.1)), 0.5);
    return a + b * cos(TAU * (c * t + d));
}

void main() {
    vec2 uv = (gl_FragCoord.xy * 2.0 - RENDERSIZE.xy) / RENDERSIZE.y;
    uv *= mat2(cos(TIME * rotationSpeed), sin(TIME * rotationSpeed), -sin(TIME * rotationSpeed), cos(TIME * rotationSpeed));
    
    vec3 color = vec3(0.0);
    float globalDist = length(uv);
    
    for (float i = 0.0; i < 4.0; i++) {
        uv = fract(uv * patternComplexity) - 0.5;
        float dist = length(uv) * exp(-globalDist);
        dist = sin(dist * 8.0 + TIME * speed * 2.0);
        dist = abs(dist);
        dist = 0.01 / dist;
        dist = pow(dist, 1.2);
        color += dist;
    }

    gl_FragColor = vec4(color, 1.0);
}
