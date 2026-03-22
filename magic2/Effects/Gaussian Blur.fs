/*{
  "CREDIT": "Optimized ISF Gaussian Blur",
  "CATEGORIES": ["Blur"],
  "INPUTS": [
    { "NAME": "inputImage", "TYPE": "image" },
    { "NAME": "blurAmount", "TYPE": "float", "MIN": 0, "MAX": 24, "DEFAULT": 12 }
  ],
  "PASSES": [
    { "TARGET": "halfSize", "WIDTH": "floor($WIDTH/2.0)", "HEIGHT": "floor($HEIGHT/2.0)", "DESCRIPTION": "Pass 0 - Half Res" },
    { "TARGET": "quarterSize", "WIDTH": "floor($WIDTH/4.0)", "HEIGHT": "floor($HEIGHT/4.0)", "DESCRIPTION": "Pass 1 - Quarter Res" },
    { "TARGET": "blurHalf", "WIDTH": "floor($WIDTH/2.0)", "HEIGHT": "floor($HEIGHT/2.0)", "DESCRIPTION": "Pass 2 - Blur Half" },
    { "TARGET": "blurQuarter", "WIDTH": "floor($WIDTH/4.0)", "HEIGHT": "floor($HEIGHT/4.0)", "DESCRIPTION": "Pass 3 - Blur Quarter" },
    { "TARGET": "final", "DESCRIPTION": "Pass 4 - Upsample & Blend" }
  ]
}*/

varying vec2 texOffsets[5];

void main() {
    int blurLevel = int(floor(blurAmount / 6.0));
    float blurMod = mod(blurAmount, 6.0);
    vec4 sample0, sample1, sample2;

    if (PASSINDEX == 0) {
        gl_FragColor = IMG_NORM_PIXEL(inputImage, isf_FragNormCoord);
    }
    else if (PASSINDEX == 1) {
        gl_FragColor = IMG_NORM_PIXEL(halfSize, isf_FragNormCoord);
    }
    else if (PASSINDEX == 2) {
        sample0 = IMG_NORM_PIXEL(halfSize, texOffsets[0]);
        sample1 = IMG_NORM_PIXEL(halfSize, texOffsets[1]);
        sample2 = IMG_NORM_PIXEL(halfSize, texOffsets[2]);
        gl_FragColor = vec4((sample0 + sample1 + sample2).rgb / 3.0, 1.0);
    }
    else if (PASSINDEX == 3) {
        sample0 = IMG_NORM_PIXEL(quarterSize, texOffsets[0]);
        sample1 = IMG_NORM_PIXEL(quarterSize, texOffsets[1]);
        sample2 = IMG_NORM_PIXEL(quarterSize, texOffsets[2]);
        gl_FragColor = vec4((sample0 + sample1 + sample2).rgb / 3.0, 1.0);
    }
    else if (PASSINDEX == 4) {
        vec4 blurred = IMG_NORM_PIXEL(blurHalf, isf_FragNormCoord) * 0.5 +
                       IMG_NORM_PIXEL(blurQuarter, isf_FragNormCoord) * 0.5;
        gl_FragColor = mix(IMG_NORM_PIXEL(inputImage, isf_FragNormCoord), blurred, (blurLevel == 0) ? blurMod / 6.0 : 1.0);
    }
}