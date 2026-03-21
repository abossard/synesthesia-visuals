/*{
    "DESCRIPTION": "Dynamic wave effect with customizable inputs.",
    "CATEGORIES": ["Generator"],
    "INPUTS": [
        {
            "NAME": "speed",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.1,
            "MAX": 5.0
        },
        {
            "NAME": "wave_intensity",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.1,
            "MAX": 2.0
        },
        {
            "NAME": "color",
            "TYPE": "color",
            "DEFAULT": [0.1, 0.3, 0.8, 1.0]
        },
        {
            "NAME": "brightness",
            "TYPE": "float",
            "DEFAULT": 0.02,
            "MIN": 0.01,
            "MAX": 0.1
        },
        {
            "NAME": "zoom",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.5,
            "MAX": 2.0
        }
    ]
}*/

void main() {
    vec2 uv = (isf_FragNormCoord.xy - 0.5) * 2.0 / zoom;
    vec3 c = vec3(0.0);

    for (int i = 0; i < 6; i++) {
        uv.x -= TIME * speed / float(i + 2);
        uv.y += sin(uv.x + TIME * speed / float(i + 1) + float(i) * 0.5) * wave_intensity / float(i + 1);
        c += brightness / abs(uv.y);
    }

    c = mix(vec3(0.0), color.rgb, c);
    gl_FragColor = vec4(c, 1.0);
}