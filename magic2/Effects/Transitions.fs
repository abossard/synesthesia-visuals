/*{
    "DESCRIPTION": "Transition shader with multiple effects like zoom, slide, rotate, and color adjustments.",
    "CATEGORIES": [ "Transition" ],
    "INPUTS": [
        { "NAME": "inputImage", "TYPE": "image" },
        { "NAME": "amount", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.5 },
        { 
            "NAME": "type", 
            "TYPE": "long",  
            "LABELS": [
                "Zoom Out",
                "Zoom In",
                "Slide Left",
                "Slide Right",
                "Slide Up",
                "Slide Down",
                "Rotate",
                "Darker",
                "Brighter"
            ], 
            "VALUES": [
                0,
                1,
                2,
                3,
                4,
                5,
                6,
                7,
                8
            ], 
            "DEFAULT": 0
        }    
        ]
}*/

vec2 mirrorEdges(vec2 loc) {
    if (loc.x < 0.0)
        loc.x = -1. * loc.x;
    if (loc.x > 1.0)
        loc.x = 2.0 - (loc.x);
    if (loc.y < 0.0)
        loc.y = -1.0 * loc.y;
    if(loc.y > 1.0)
        loc.y = 2.0 - loc.y;
    
    return loc;
}

vec4 blur(vec2 uv, vec2 biasAmount) {
    vec4 fragmentColor = IMG_NORM_PIXEL(inputImage, uv) * 0.18;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv + biasAmount) * 0.15;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv + biasAmount * 2.0) * 0.12;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv + biasAmount * 3.0) * 0.09;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv + biasAmount * 4.0) * 0.05;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv - biasAmount) * 0.15;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv - biasAmount * 2.0) * 0.12;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv - biasAmount * 3.0) * 0.09;
    fragmentColor += IMG_NORM_PIXEL(inputImage, uv - biasAmount * 4.0) * 0.05;
    return fragmentColor;
}

float slideTransition(float amount, float pos, float biasAmount) {
    pos -= (1.0 - amount) * 0.25 * biasAmount;
    return pos;
}

vec2 rotateTransition(float amount, vec2 pos, vec2 center, float biasAmount) {
    float angle = -(1.0 - amount) * biasAmount;
    float s = sin(angle);
    float c = cos(angle);
    pos -= center;
    vec2 newPos = vec2(
        pos.x * c - pos.y * s,
        pos.x * s + pos.y * c
    );
    return newPos + center;
}

vec2 zoomTransition(float amount, vec2 pos, float biasAmount) {
    return mix(vec2(0.5), pos, 1.0 - (1.0 - amount) * biasAmount);
}

void main() {
    vec2 uv = isf_FragNormCoord.xy;
    vec2 blurBias = vec2(0.0);
    float normalizedAmount = 1.0 - (amount);

    if (type == 0) {
        uv = zoomTransition(amount, uv, 0.3);
        blurBias = (vec2(0.5) - uv) * normalizedAmount * 0.03;
    } else if (type == 1) {
        uv = zoomTransition(amount, uv, -0.3);
        blurBias = (vec2(0.5) - uv) * normalizedAmount * 0.03;
    } else if (type == 2) {
        uv.x = slideTransition(amount, uv.x, 2.0);
        blurBias = vec2(1.0, 0.0) * normalizedAmount * 0.02;
    } else if (type == 3) {
        uv.x = slideTransition(amount, uv.x, -2.0);
        blurBias = vec2(1.0, 0.0) * normalizedAmount * 0.02;
    } else if (type == 4) {
        uv.y = slideTransition(amount, uv.y, -1.0);
        blurBias = vec2(0.0, 1.0) * normalizedAmount * 0.02;
    } else if (type == 5) {
        uv.y = slideTransition(amount, uv.y, 1.0);
        blurBias = vec2(0.0, 1.0) * normalizedAmount * 0.02;
    } else if (type == 6) {
        blurBias = (vec2(0.5) - uv) * normalizedAmount * 0.03;
        uv = rotateTransition(amount, uv * RENDERSIZE, 0.5 * RENDERSIZE, 0.22);
        uv /= RENDERSIZE;
    } else if (type == 7) {
        vec4 color = IMG_NORM_PIXEL(inputImage, uv);
        color.rgb = pow(color.rgb, vec3(1.0 / (1.0 - normalizedAmount)));
        gl_FragColor = color;
        return;
    } else {
        vec4 color = IMG_NORM_PIXEL(inputImage, uv);
        color.rgb *= pow(2.0, normalizedAmount * 2.0);
        gl_FragColor = color;
    }
    uv = mirrorEdges(uv);

    if (type < 7) {
        gl_FragColor = mix(blur(uv, blurBias), IMG_NORM_PIXEL(inputImage, uv), max(0., -1. + amount * 2.));
    } else {
        gl_FragColor = IMG_NORM_PIXEL(inputImage, uv);
    }
}
