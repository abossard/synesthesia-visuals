/*{
  "DESCRIPTION": "Sharpen effect with standard and sqrt-space comparison",
  "CREDIT": "Converted by ChatGPT",
  "ISFVSN": "2",
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "sharpenStrength",
      "TYPE": "float",
      "DEFAULT": 30.0,
      "MIN": 0.0,
      "MAX": 120.0
    }
  ]
}*/

void main() {
    vec2 uv = isf_FragNormCoord.xy;
    vec2 offset = vec2(1.0) / RENDERSIZE;

    vec4 left   = IMG_NORM_PIXEL(inputImage, uv + vec2(-offset.x, 0.0));
    vec4 right  = IMG_NORM_PIXEL(inputImage, uv + vec2(offset.x,  0.0));
    vec4 up     = IMG_NORM_PIXEL(inputImage, uv + vec2(0.0,         offset.y));
    vec4 down   = IMG_NORM_PIXEL(inputImage, uv + vec2(0.0,         -offset.y));
    vec4 avg = (up + left + right + down) * 0.25;

    vec4 center = IMG_NORM_PIXEL(inputImage, uv);

    // Sqrt-space sharpen
    vec4 sqAvg = sqrt(avg);
    vec4 sqCenter = sqrt(center);
    vec4 sqResult = sqCenter + sqrt(sharpenStrength) * (sqCenter - sqAvg);

    // Bottom-right: sqrt space version
    float halfScreen = step(uv.x - uv.y, 0.0);
    gl_FragColor =  sqResult * sqResult;
}
