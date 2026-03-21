// ISF Shader

/*
{
  "DESCRIPTION": "Applies bilateral filter  based on input texture.",
  "CATEGORIES": ["Filter", "blur"],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "amount",
      "TYPE": "float",
      "DEFAULT": 1.0,
      "MIN": 0.0,
      "MAX": 1.0
    },
    {
      "NAME": "sigmaSpace",
      "TYPE": "float",
      "DEFAULT": 10.0,
      "MIN": 1.0,
      "MAX": 10.0
    },
    {
      "NAME": "sigmaColor",
      "TYPE": "float",
      "DEFAULT": 25.0,
      "MIN": 1.0,
      "MAX": 100.0
    }
  ]
}
*/

void main() {
    vec2 uv = isf_FragNormCoord; // Normalized pixel coordinates (from 0 to 1)
    vec4 fragColor;

    vec4 I = IMG_NORM_PIXEL(inputImage, uv);


    // Bilateral Filter
    float Ss = pow(sigmaSpace, 2.0) * 2.0;
    float Sc = pow(sigmaColor, 2.0) * 2.0;

    vec4 TW = vec4(0.0); // Sum of Weights
    vec4 WI = vec4(0.0); // Sum of Weighted Intensities

    for (int i = -10; i <= 10; i++) {
        for (int j = -10; j <= 10; j++) {
            vec2 dx = vec2(float(i), float(j));
            vec2 tc = uv + dx / RENDERSIZE;
            vec4 Iw = IMG_NORM_PIXEL(inputImage, tc);
            vec4 dc = (I - Iw) * 255.0;

            vec4 w = exp(-dot(dx, dx) / Ss - dc * dc / Sc);
            TW += w;
            WI += Iw * w;
        }
    }

    
    gl_FragColor = mix(I, vec4((WI / TW).rgb, 1.0), amount);
}
