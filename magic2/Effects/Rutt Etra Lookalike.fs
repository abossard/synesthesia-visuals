
/*
{
    "DESCRIPTION": "Rutt Etra ",
    "CREDIT": "RV & AKASCAPE",
    "CATEGORIES": [
        "Effect"
    ],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "LineNum",
            "TYPE": "float",
            "DEFAULT": 0.03,
            "MIN": 0.0,
            "MAX": 0.05
        },
        {
            "NAME": "Brightness",
            "TYPE": "float",
            "DEFAULT": 5.0,
            "MIN": 0.0,
            "MAX": 10.0
        },
        {
            "NAME": "Animation",
            "TYPE": "float",
            "DEFAULT": 0.01,
            "MIN": 0.0,
            "MAX": 0.1
        },
        {
            "NAME": "Depth",
            "TYPE": "float",
            "DEFAULT": 80.0,
            "MIN": 0.0,
            "MAX": 200.0
        },
        {
            "NAME": "LineWidth",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 5.0
        }
    ]
}

*/


// RUTT ETRA EFFECT SHADER PORTED BY RV OG BY AKASCAPE

// Converted to Interactive Shader Format with published parameters for VDMX by Jim Warrier

// Customizable properties for the effect:

// Main Image
/* Main Image */
const int samples = 5; // Increased number of samples for better quality

void main() {
    vec2 fragCoord = isf_FragNormCoord.xy * RENDERSIZE;
    vec2 uv = fragCoord / RENDERSIZE;
    float img = IMG_NORM_PIXEL(inputImage, uv).g;

    vec2 n[samples];
    for (int i = 0; i < samples; ++i) {
        vec2 modUv = uv + vec2(0.0, float(i - (samples / 2)) / RENDERSIZE.y); // Change to vary along y-axis
        float lines = IMG_NORM_PIXEL(inputImage, modUv).r;

        lines += fract(Animation * TIME);
        n[i] = vec2(floor(lines * LineNum * RENDERSIZE.y)); // Store y-coordinates
    }

    float br = 0.0;
    for (int i = 0; i < samples - 1; ++i) {
        if (n[i + 1].y - n[i].y > 0.1) { // Compare y-coordinates
            float s = float(i - (samples / 2));
            br += max(0.0, 1.0 - abs(s / (LineWidth + img)));
        }
    }

    // Interpolating between points for smoother transitions
    float interp = 0.0;
    for (int i = 0; i < samples - 1; ++i) {
        float weight = 1.0 - abs(float(i - (samples / 2)) / float(samples / 2));
        interp += br * weight;
    }

    vec3 color = mix(vec3(0.0), vec3(img), pow(interp, 1.0 / Brightness));
    gl_FragColor = vec4(color, 1.0);
}
