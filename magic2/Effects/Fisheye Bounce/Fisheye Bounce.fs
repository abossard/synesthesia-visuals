/*{
    "DESCRIPTION": "Chromatic dispersion effect shader",
    "CATEGORIES": [ "Distortion", "Color Effect" ],
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
            "MAX": 2.0
        }
    ]
}*/

void main() {
    float k = -0.8, kcube = 0.2, scale = 1.0;
    float Amount = amount;
    float Chroma = -0.1;
    
    k = -0.8 * Amount;
    float dispersion = Chroma * Amount;
    
    vec2 uv = isf_FragNormCoord.xy;
    
    scale = 1.0 - 0.1 * Amount;
    
    // Index of refraction of each color channel, causing chromatic dispersion
    vec3 eta = vec3(1.0 + dispersion * 0.9, 1.0 + dispersion * 0.6, 1.0 + dispersion * 0.3);
    
    // Texture coordinates
    vec2 texcoord = uv.xy;
    vec2 cancoord = uv.xy;
    float r2 = (cancoord.x - 0.5) * (cancoord.x - 0.5) + (cancoord.y - 0.5) * (cancoord.y - 0.5);
    
    float f = 0.0;
    
    if (kcube == 0.0) {
        f = 1.0 + r2 * k;
    } else {
        f = 1.0 + r2 * (k + kcube * sqrt(r2));
    }
    
    vec2 rCoords = (f * eta.r) * scale * (texcoord.xy - 0.5) + 0.5;
    vec2 gCoords = (f * eta.g) * scale * (texcoord.xy - 0.5) + 0.5;
    vec2 bCoords = (f * eta.b) * scale * (texcoord.xy - 0.5) + 0.5;
    
    vec3 inputDistort = vec3(0.0);
    
    inputDistort.r = IMG_NORM_PIXEL(inputImage, rCoords).r;
    inputDistort.g = IMG_NORM_PIXEL(inputImage, gCoords).g;
    inputDistort.b = IMG_NORM_PIXEL(inputImage, bCoords).b;
    
    gl_FragColor = vec4(inputDistort.r, inputDistort.g, inputDistort.b, 1.0);
}
