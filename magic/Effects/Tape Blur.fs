/*{
    "DESCRIPTION": "VHS Blur",
    "CATEGORIES": ["Effect"],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "amount",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 0.75
        }
    ]
}*/


vec2 sat(vec2 t) {
    return clamp(t, 0.0, 1.0);
}

vec3 spectrum_offset(float t) {
    vec3 ret;
    float lo = step(t, 0.5);
    float hi = 1.0 - lo;
    float w = 1.0 - abs(2.0 * t - 1.0);
    float neg_w = 1.0 - w;
    ret = vec3(lo, 1.0, hi) * vec3(neg_w, w, neg_w);
    return pow(ret, vec3(1.0 / 2.2));
}

void main() {
    vec2 uv = isf_FragNormCoord.xy;

    float GLITCH = amount;
    float time = TIME;

    const int NUM_SAMPLES = 10;
    const float RCP_NUM_SAMPLES_F = 1.0 / float(NUM_SAMPLES);

    vec4 sum = vec4(0.0);
    vec3 wsum = vec3(0.0);

    // Color shift only
    for (int i = 0; i < NUM_SAMPLES; ++i) {
        float t = float(i) * RCP_NUM_SAMPLES_F;
        float shift = GLITCH * 0.02 * (0.5 - t); // Centered shift
        vec2 shiftedUV = sat(vec2(uv.x + shift, uv.y));
        vec4 samplecol = IMG_NORM_PIXEL(inputImage, shiftedUV);
        vec3 s = spectrum_offset(t);
        samplecol.rgb *= s;
        sum += samplecol;
        wsum += s;
    }

    sum.rgb /= wsum;
    sum.a *= RCP_NUM_SAMPLES_F;

    gl_FragColor = vec4(sum.rgb, sum.a);
}
