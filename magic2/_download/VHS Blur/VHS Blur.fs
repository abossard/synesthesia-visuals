/*{
    "DESCRIPTION": "VHS Blur",
    "CATEGORIES": ["Color Effect"],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "amount",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.5
        },
        {
            "NAME": "tracking",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.5
        },
        {
            "NAME": "time",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 10.0,
            "DEFAULT": 0.0
        }
    ]
}*/

#define NUM_SAMPLES 5
#define RCP_NUM_SAMPLES_F (1.0 / float(NUM_SAMPLES))

float sat(float t) {
    return clamp(t, 0.0, 1.0);
}

float remap(float t, float a, float b) {
    return sat((t - a) / (b - a));
}

float linterp(float t) {
    return sat(1.0 - abs(2.0 * t - 1.0));
}

vec3 spectrum_offset(float t) {
    float t0 = 3.0 * t - 1.5;
    return clamp(vec3(-t0, 1.0 - abs(t0), t0), 0.0, 1.0);
}

float rande(vec2 n) {
    return fract(sin(dot(n.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = isf_FragNormCoord.xy;
    uv.y = uv.y;
    
    float GLITCH = amount * 0.07 * 4.0;
    float pxrnd = rande(uv);
    float ofs = 0.1 * GLITCH;
    ofs += 0.5 * pxrnd * ofs;

    vec4 sum = vec4(0.0);
    vec3 wsum = vec3(0.0);
    for (int i = 0; i < NUM_SAMPLES; ++i) {
        float t = float(i) * RCP_NUM_SAMPLES_F;
        uv.x = sat(uv.x + ofs * t);
        vec4 samplecol = IMG_NORM_PIXEL(inputImage, uv);
        vec3 s = spectrum_offset(t);
        samplecol.rgb *= s;
        sum += samplecol;
        wsum += s;
    }
    sum.rgb /= wsum;
    sum.a *= RCP_NUM_SAMPLES_F;
    
    gl_FragColor = sum;
}