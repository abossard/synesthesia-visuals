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
            "NAME": "flip",
            "TYPE": "float",
            "DEFAULT": 0
        },
        {
            "NAME": "linePos",
            "TYPE": "float",
            "DEFAULT": 0.5
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
    uv *= 2.0;

    // Map linePos from 0.0–1.0 to -1.0–1.0
    float target = linePos * 2.0 - 1.0;

    // Select coordinate depending on flip, apply aspect correction to vertical line only
    float coord = mix(uv.y, uv.x, flip);
    if (flip > 0.5) {
        coord *= RENDERSIZE.x / RENDERSIZE.y;
        target *= RENDERSIZE.x / RENDERSIZE.y;
    }

    float dist = abs(coord - target);
    float line = line_width / dist;
    float light = line * brightness;

    vec3 c = color.rgb * light;
    gl_FragColor = vec4(c, light);
}

