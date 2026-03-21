/*{
    "DESCRIPTION": "Wave Deformation",
    "CATEGORIES": [
        "Distortion"
    ],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "waveCount",
            "TYPE": "float",
            "MIN": 1.0,
            "MAX": 10.0,
            "DEFAULT": 3.0
        },
        {
            "NAME": "waveSpeed",
            "TYPE": "float",
            "MIN": 0.1,
            "MAX": 5.0,
            "DEFAULT": 1.0
        },
        {
            "NAME": "waveAmplitude",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.11
        }
    ]
}*/

void main() {
    vec2 uv = isf_FragNormCoord;

    vec2 distortedUV = uv;
    const int maxWaves = 10;
    for (int i = 0; i < maxWaves; i++) {
        if (float(i) >= waveCount) break;
        float angle = float(i) * 2.0 * 3.14159 / waveCount;
        vec2 direction = vec2(cos(angle), sin(angle));
        float distance = length(uv - direction);
        float frequency = 10.0 + float(i) * 2.0; // Different frequencies for each wave
        float amplitude = waveAmplitude * (1.0 - float(i) * 0.1); // Decreasing amplitude for each wave
        float wave = sin(distance * frequency - TIME * waveSpeed) * amplitude;
        distortedUV += direction * wave;
    }

    distortedUV = distortedUV;
    vec4 color = IMG_NORM_PIXEL(inputImage, distortedUV);
    gl_FragColor = color;
}
