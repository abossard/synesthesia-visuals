/*{
  "DESCRIPTION": "Optical Flow Effect",
  "CREDIT": "Arkestra",
  "CATEGORIES": ["Effect"],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "flowAmount",
      "TYPE": "float",
      "DEFAULT": 0.5,
      "MIN": 0.0,
      "MAX": 1.0
    },
    {
      "NAME": "flowHold",
      "TYPE": "float",
      "DEFAULT": 0.98,
      "MIN": 0.95,
      "MAX": 0.99
    },
    {
      "NAME": "motionScale",
      "TYPE": "float",
      "DEFAULT": 2.0,
      "MIN": 0.0,
      "MAX": 10.0
    },
    {
      "NAME": "zoom",
      "TYPE": "float",
      "DEFAULT": 1.01,
      "MIN": 0.95,
      "MAX": 1.05
    },
    {
      "NAME": "spin",
      "TYPE": "float",
      "DEFAULT": 0.0,
      "MIN": -0.1,
      "MAX": 0.1
    }
  ],
  "PASSES": [
    {"TARGET": "inputBuffer", "PERSISTENT": false},
    {"TARGET": "maskBuffer", "PERSISTENT": true},
    {"TARGET": "delayBuffer", "PERSISTENT": true},
    {}
  ]
}*/

varying vec2 left_coord;
varying vec2 right_coord;
varying vec2 above_coord;
varying vec2 below_coord;
varying vec2 lefta_coord;
varying vec2 righta_coord;
varying vec2 leftb_coord;
varying vec2 rightb_coord;

const vec4 coeffs = vec4(0.2126, 0.7152, 0.0722, 1.0);

float gray(vec4 n) {
  return (n.r + n.g + n.b) / 3.0;
}

void main() {
  if (PASSINDEX == 0) {
    // Copy inputImage to buffer
    gl_FragColor = IMG_THIS_PIXEL(inputImage);
  }
  else if (PASSINDEX == 1) {
    // Calculate optical flow mask with motion
    vec2 uv = isf_FragNormCoord.xy;
    
    // Apply zoom and rotation
    vec2 center = vec2(0.5);
    vec2 delta = uv - center;
    float angle = spin;
    float cosA = cos(angle);
    float sinA = sin(angle);
    vec2 rotated = vec2(
      delta.x * cosA - delta.y * sinA,
      delta.x * sinA + delta.y * cosA
    );
    vec2 transformed = center + rotated * zoom;
    
    vec4 a = IMG_NORM_PIXEL(inputBuffer, transformed) * coeffs;
    float brightness = gray(a);
    
    vec4 b = IMG_THIS_NORM_PIXEL(delayBuffer) * coeffs;
    float brightness_prev = gray(b);
    
    // Motion detection
    float motion = abs(brightness - brightness_prev) * motionScale;
    
    vec4 mask = vec4(motion, 0.0, motion, 0.0);
    
    // 9-tap blur of motion mask
    vec4 color = IMG_THIS_NORM_PIXEL(maskBuffer);
    vec4 colorL = IMG_NORM_PIXEL(maskBuffer, left_coord);
    vec4 colorR = IMG_NORM_PIXEL(maskBuffer, right_coord);
    vec4 colorA = IMG_NORM_PIXEL(maskBuffer, above_coord);
    vec4 colorB = IMG_NORM_PIXEL(maskBuffer, below_coord);
    vec4 colorLA = IMG_NORM_PIXEL(maskBuffer, lefta_coord);
    vec4 colorRA = IMG_NORM_PIXEL(maskBuffer, righta_coord);
    vec4 colorLB = IMG_NORM_PIXEL(maskBuffer, leftb_coord);
    vec4 colorRB = IMG_NORM_PIXEL(maskBuffer, rightb_coord);
    
    vec4 blurVector = (color + colorL + colorR + colorA + colorB + colorLA + colorRA + colorLB + colorRB) / 9.0;
    gl_FragColor = mask + flowHold * blurVector;
  }
  else if (PASSINDEX == 2) {
    // Store current frame
    gl_FragColor = IMG_THIS_NORM_PIXEL(inputBuffer);
  }
  else {
    // Apply flow distortion
    vec4 color = IMG_THIS_NORM_PIXEL(maskBuffer);
    vec4 colorL = IMG_NORM_PIXEL(maskBuffer, left_coord);
    vec4 colorR = IMG_NORM_PIXEL(maskBuffer, right_coord);
    vec4 colorA = IMG_NORM_PIXEL(maskBuffer, above_coord);
    vec4 colorB = IMG_NORM_PIXEL(maskBuffer, below_coord);
    vec4 colorLA = IMG_NORM_PIXEL(maskBuffer, lefta_coord);
    vec4 colorRA = IMG_NORM_PIXEL(maskBuffer, righta_coord);
    vec4 colorLB = IMG_NORM_PIXEL(maskBuffer, leftb_coord);
    vec4 colorRB = IMG_NORM_PIXEL(maskBuffer, rightb_coord);
    
    vec4 blurVector = (color + colorL + colorR + colorA + colorB + colorLA + colorRA + colorLB + colorRB) / 9.0;
    vec2 blurAmount = vec2(blurVector.y - blurVector.x, blurVector.w - blurVector.z);
    vec2 flowUV = isf_FragNormCoord.xy + blurAmount * flowAmount;
    flowUV = clamp(flowUV, 0.0, 1.0);
    
    gl_FragColor = IMG_NORM_PIXEL(inputImage, flowUV);
  }
}