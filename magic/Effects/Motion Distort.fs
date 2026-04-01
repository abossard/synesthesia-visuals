/*{
  "DESCRIPTION": "Simplified version of Datamosh effect without motion inertia, with additional controls for motion and sensitivity.",
  "CREDIT": "Modified by adding controls for motion amount, sensitivity, and mask smoothness.",
  "CATEGORIES": [
    "Glitch",
    "Simplified"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "motionImage",
      "TYPE": "image"
    },
    {
      "NAME": "feedback",
      "TYPE": "float",
      "DEFAULT": 0.96
    },
    {
      "NAME": "amount",
      "TYPE": "float",
      "DEFAULT": 0.5,
      "MIN": 0.0,
      "MAX": 1.0
    },
    {
      "NAME": "sensivity",
      "TYPE": "float",
      "DEFAULT": 7.0,
      "MIN": 0.0,
      "MAX": 10.0
    }
  ],
  "PASSES": [
    {
      "TARGET": "BUFFER_A",
      "PERSISTENT": true
    },
    {
      "TARGET": "BUFFER_B",
      "PERSISTENT": true
    },
    {}
  ]
}*/

const vec4 coeffs = vec4(0.2126, 0.7152, 0.0722, 1.0);

float gray(vec4 n) {
    return (n.r + n.g + n.b) / 3.0;
}

void main() {
    if (PASSINDEX == 0) {
        // Generate motion mask
        vec4 a = IMG_THIS_NORM_PIXEL(motionImage) * coeffs;
        float brightness = gray(a);
        a = vec4(brightness);

        vec2 offset = vec2(1.0);
        vec4 gradx = IMG_PIXEL(motionImage, isf_FragNormCoord.xy + vec2(offset.x, 0.0)) -
                     IMG_PIXEL(motionImage, isf_FragNormCoord.xy - vec2(offset.x, 0.0));
        vec4 grady = IMG_PIXEL(motionImage, isf_FragNormCoord.xy + vec2(0.0, offset.y)) -
                     IMG_PIXEL(motionImage, isf_FragNormCoord.xy - vec2(0.0, offset.y));

        vec4 gradmag = sqrt((gradx * gradx) + (grady * grady));
        vec4 mask = clamp(gradmag * sensivity * a * 10., 0.0, 1.0);

        // Apply amount to mask to control how much motion is applied
        mask *= amount * 0.05;

        // Smooth the mask with maskSmoothness control
        vec4 color = IMG_THIS_NORM_PIXEL(BUFFER_A);
        vec4 colorL = IMG_NORM_PIXEL(BUFFER_A, isf_FragNormCoord.xy - vec2(offset.x, 0.0));
        vec4 colorR = IMG_NORM_PIXEL(BUFFER_A, isf_FragNormCoord.xy + vec2(offset.x, 0.0));
        vec4 colorA = IMG_NORM_PIXEL(BUFFER_A, isf_FragNormCoord.xy - vec2(0.0, offset.y));
        vec4 colorB = IMG_NORM_PIXEL(BUFFER_A, isf_FragNormCoord.xy + vec2(0.0, offset.y));

        vec4 blurVector = (color + colorL + colorR + colorA + colorB) / (15.);
        gl_FragColor = mask + blurVector * feedback;
        
    } else if (PASSINDEX == 1) {
        vec2 texcoord0 = isf_FragNormCoord.xy;

        vec4 blurVector = IMG_THIS_NORM_PIXEL(BUFFER_A);
        vec2 blurAmount = vec2(blurVector.y - blurVector.x, blurVector.w - blurVector.z);

        vec2 tmp = texcoord0 + (blurAmount * feedback);
        tmp = clamp(tmp, 0.0, 1.0);

        gl_FragColor = mix(IMG_NORM_PIXEL(inputImage, tmp), IMG_NORM_PIXEL(BUFFER_B, tmp), feedback);
    } else {
        vec4 color = IMG_THIS_PIXEL(BUFFER_B);
        gl_FragColor = color;
    }
}
