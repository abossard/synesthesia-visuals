/*{
    "DESCRIPTION": "Converted and optimized shader with audio input.",
    "CATEGORIES": ["Effect", "Audio Reactive"],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "size",
            "TYPE": "float"
        },
        {
            "NAME": "amount",
            "TYPE": "float",
            "DEFAULT": 0.75
        }
    ]
}*/

// Fork from
// https://www.shadertoy.com/view/XtdcWS

#define N(u) fract(sin(dot(floor(u * 128.0), vec2(12.13, 4.47))) * 13.5 + TIME)

void main() {
    vec2 uv = isf_FragNormCoord; // Normalized pixel coordinates (0,1)
    uv.y -= mod(uv.y, 1.0 / 128.0); // Creates a horizontal line effect

    // Scaling u vector based on y value
    uv *= vec2(exp2(floor(uv.y * 5.0)), uv.y);

    // Sample the audio texture at y position
    float t = IMG_NORM_PIXEL(inputImage, vec2(uv.y, 0.0)).r * amount - 0.3;
    float n = N(uv) * (1. - size) - t; // Noise value
    uv.x /= 32.0; // Scale x coordinate

    vec4 samplecol = IMG_THIS_PIXEL(inputImage);
    // Output color based on noise value comparison
    vec4 glitch = step(0.0, n * (t - N(uv))) * vec4(1.0); // White color when condition is met
    gl_FragColor = mix(samplecol, glitch, glitch);
}
