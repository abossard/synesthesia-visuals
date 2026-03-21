/*{
  "CREDIT": "by isak.burstrom",
  "DESCRIPTION": "converted from: http://roy.red/infinite-regression-.html#infinite-regression",
  "CATEGORIES": [
    "INKA",
    "Distortion Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "twist",
      "TYPE": "float",
      "DEFAULT": 2,
      "MIN": 0.1,
      "MAX": 2
    },
    {
      "NAME": "amount",
      "TYPE": "float",
      "DEFAULT": 1,
      "MIN": 0,
      "MAX": 1
    }
  ]
}*/

#define PI 3.14159265359

vec2 cInv(vec2 c) {
  return vec2(c.x, -c.y) / dot(c, c);
}

vec2 cExp(vec2 c) {
  return exp(c.x) * vec2( cos(c.y), sin(c.y) );
}

vec2 cLog(vec2 c) {
  return vec2( log( length(c) ), atan(c.y, c.x) );
}

vec2 cMul(vec2 a, vec2 b) {
  return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

vec2 cDiv(vec2 a, vec2 b) {
  return cMul(a, cInv(b));
}
    
float f(float x,float n){
    return pow(n, -floor(log(x) / log(n)));
}

void main() {
	vec2 z = -1. + isf_FragNormCoord.xy * 2.;
	
    float ratio = 5.264;
    float angle = atan(log(ratio) / (twist * PI));
    
    z = cExp(cDiv(cLog(z), cExp(vec2(0, angle)) * cos(angle)));
    
    vec2 a_z = abs(z);
    
    z *= f(max(a_z.x, a_z.y) * 2., ratio);
    vec2 newCoord = z / ratio + .5;
    vec2 originalCoord = isf_FragNormCoord.xy;
    vec2 resultCoord = mix(originalCoord, newCoord, amount);
    
    gl_FragColor = IMG_NORM_PIXEL(inputImage, resultCoord);
}