/*
{
    "CATEGORIES": [
        "Automatically Converted",
        "Shadertoy"
    ],
    "DESCRIPTION": "Automatically converted from https://www.shadertoy.com/view/DtXfDr by supah.  Discoteq 2 with added parameters",
    "IMPORTED": {
    },
    "INPUTS": [
        {
            "NAME": "baseSpeed",
            "TYPE": "float",
            "DEFAULT": 0.3,
            "MIN": 0.0,
            "MAX": 5.0
        },
        {
            "NAME": "baseHeight",
            "TYPE": "float",
            "DEFAULT": 4.0,
            "MIN": 0.0,
            "MAX": 10.0
        },
        {
            "NAME": "blur",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "color1",
            "TYPE": "color",
            "DEFAULT": [0.2, 0.2, 0.3, 1.0]
        },
        {
            "NAME": "color2",
            "TYPE": "color",
            "DEFAULT": [0.9, 0.6, 0.3, 1.0]
        }
    ]
}
*/

#define S smoothstep

vec4 Line(vec2 uv, float speed, float height, vec3 col) {
    uv.y += S(1., 0., abs(uv.x)) * sin(TIME * speed + uv.x * height) * .2;
    return vec4(S(.06 * S(.1, 0.3 + blur * 0.8, abs(uv.x)), 0., abs(uv.y) - .004) * col, 1.0) * S(1., .01, abs(uv.x));
}

void main() {
    vec2 uv = (gl_FragCoord.xy - .5 * RENDERSIZE.xy) / RENDERSIZE.y;
    gl_FragColor = vec4(0.0);

    // Loop through the lines
    for (float i = 0.; i <= 5.; i += 1.) {
        float t = i / 5.;
        vec3 col = mix(color1.rgb, color2.rgb, t); // Interpolate between the two colors
        float speed = baseSpeed + t;              // Adjust speed based on line index
        float height = baseHeight + t;            // Adjust height based on line index
        gl_FragColor += Line(uv, speed, height, col);
    }
}
