/*{
    "CREDIT": "",
    "DESCRIPTION": "",
    "CATEGORIES": [ "generator" ],
    "INPUTS": [
        {
            "NAME": "noiseIntensity",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 10.0,
            "DEFAULT": 6.0
        },
        {
            "NAME": "noiseScaleX",
            "TYPE": "float",
            "MIN": 1.0,
            "MAX": 10.0,
            "DEFAULT": 5.5
        },
        {
            "NAME": "noiseScaleY",
            "TYPE": "float",
            "MIN": 1.0,
            "MAX": 10.0,
            "DEFAULT": 3.5
        },
        {
            "NAME": "redPhaseShift",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.1
        },
        {
            "NAME": "greenPhaseShift",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.3
        },
        {
            "NAME": "bluePhaseShift",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.6
        }
    ]
}*/

#define PI 3.1415926535
#define TWO_PI (PI * 2.0)
#define NUM_NOISE_OCTAVES 3

float map(float x, float in_min, float in_max, float out_min, float out_max) {
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

float ease(float p, float g) {
    return p < 0.5 ? 0.5 * pow(2.0 * p, g) : 1.0 - 0.5 * pow(2.0 * (1.0 - p), g);
}

// Optimized hash function by Inigo Quilez
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.13);
    p3 += dot(p3, p3.yzx + 3.333);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D gradient noise by Inigo Quilez
float noise(vec2 x) {
    vec2 i = floor(x), f = fract(x), u = f * f * (3.0 - 2.0 * f);
    return mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x) +
           (hash(i + vec2(0.0, 1.0)) - hash(i)) * u.y * (1.0 - u.x) +
           (hash(i + vec2(1.0, 1.0)) - hash(i + vec2(1.0, 0.0))) * u.x * u.y;
}

float fbm(vec2 x) {
    float v = 0.0, a = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    for (int i = 0; i < NUM_NOISE_OCTAVES; ++i) {
        v += a * noise(x);
        x = rot * x * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

float distFromCenter(vec2 uv) {
    vec2 p = uv - 0.5;
    p.x *= RENDERSIZE.x / RENDERSIZE.y;
    return length(p);
}

float upwelling(vec2 uv, float t, float noiseIntensity, vec2 noiseScale, float phase) {
    float uvNoise = fbm(uv * noiseScale * fbm(uv * noiseScale + t * 0.3)) * noiseIntensity;
    float noiseOffset = uvNoise * smoothstep(0.32, 0.22, distFromCenter(uv));
    float waveOffset = smoothstep(0.8, 0.001, distFromCenter(uv)) * 18.0;
    return map(sin(TWO_PI * (t + noiseOffset + waveOffset + phase)), -1.0, 1.0, 0.0, 1.0);
}

vec4 fullscreenMelt(vec2 uv, float t) {
    float phaseShift = smoothstep(0.5, 1.0, 1.0 - distFromCenter(uv));
    float upwellRed = upwelling(uv, t, noiseIntensity, vec2(noiseScaleX, noiseScaleY), redPhaseShift * phaseShift);
    float upwellGreen = upwelling(uv, t, noiseIntensity, vec2(noiseScaleX, noiseScaleY), greenPhaseShift * phaseShift);
    float upwellBlue = upwelling(uv, t, noiseIntensity, vec2(noiseScaleX, noiseScaleY), bluePhaseShift * phaseShift);
    return vec4(upwellRed, upwellGreen, upwellBlue, 1.0);
}

void main() {
    vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
    float fadeFromCenter = 1.0 - min(ease(distFromCenter(uv) + 0.2, 20.0), 1.0);
    vec4 vignette = vec4(vec3(fadeFromCenter), 1.0);
    gl_FragColor = fullscreenMelt(uv, TIME) * vignette;
}
