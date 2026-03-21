/*{
    "DESCRIPTION": "Aspect-ratio corrected dynamic circle outline with customizable inputs.",
    "CATEGORIES": ["Generator"],
    "INPUTS": [
        {
            "NAME": "radius",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.1,
            "MAX": 2.5
        },
        {
            "NAME": "line_width",
            "TYPE": "float",
            "DEFAULT": 0.02,
            "MIN": 0.01,
            "MAX": 0.1
        },
        {
            "NAME": "color",
            "TYPE": "color",
            "DEFAULT": [0.1, 0.3, 0.8, 1.0]
        },
        {
            "NAME": "brightness",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.1,
            "MAX": 1.0
        }
    ]
}*/

void main() {
    vec2 uv = isf_FragNormCoord.xy - 0.5;
    uv.x *= RENDERSIZE.x / RENDERSIZE.y; // Aspect-ratio correction
    uv *= 2.0;
    float len = length(uv);

    // Compute the dynamic outline of the circle with customizable line width
    float outline = line_width / abs(len - radius);
    float light = outline * brightness;
    // Combine circle outline with color and brightness
    vec3 c = color.rgb * light;

    gl_FragColor = vec4(c, light);
}