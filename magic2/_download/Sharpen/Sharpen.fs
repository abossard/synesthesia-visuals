/*{
    "CATEGORIES": [
    "Sharpen And Blur"
    ],
    "DESCRIPTION": "A shader that applies a conditional sharpening effect based on the fragment's x-coordinate.",
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "sharpenAmount",
            "TYPE": "float",
            "DEFAULT": 5.0,
            "MIN": 0.0,
            "MAX": 20.0
        }
    ]
}*/

void main()
{
    vec2 uv = isf_FragNormCoord.xy;
    
    
    vec2 step = 1.0 / RENDERSIZE;
    
    vec3 texA = IMG_NORM_PIXEL(inputImage, uv + vec2(-step.x, -step.y) * 1.5).rgb;
    vec3 texB = IMG_NORM_PIXEL(inputImage, uv + vec2(step.x, -step.y) * 1.5).rgb;
    vec3 texC = IMG_NORM_PIXEL(inputImage, uv + vec2(-step.x, step.y) * 1.5).rgb;
    vec3 texD = IMG_NORM_PIXEL(inputImage, uv + vec2(step.x, step.y) * 1.5).rgb;
   
    vec3 around = 0.25 * (texA + texB + texC + texD);
    vec3 center  = IMG_NORM_PIXEL(inputImage, uv).rgb;
    
    float sharpness = sharpenAmount;
    
    vec3 col = center + (center - around) * sharpness;
    
    gl_FragColor = vec4(col, 1.0);
}
