/*{
    "DESCRIPTION": "Transition shader with multiple effects like zoom, slide, rotate, and color adjustments.",
    "CATEGORIES": [ "Transition" ],
    "INPUTS": [
        { "NAME": "inputImage", "TYPE": "image" },
        { "NAME": "amount", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.5 },
        {
            "NAME": "inOut",
            "LABEL": "In / Out",
            "TYPE": "bool",
            "DEFAULT": false
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
    float dir = inOut ? 1.0 : -1.0;


    uv = zoomTransition(amount, uv, 0.3 * dir);
    blurBias = (vec2(0.5) - uv) * normalizedAmount * 0.03;
    
    uv = mirrorEdges(uv);
    gl_FragColor = blur(uv, blurBias);
}
