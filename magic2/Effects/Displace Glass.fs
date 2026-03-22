/*
{
  "CATEGORIES" : [
    "Distortion Effect"
  ],
  "DESCRIPTION" : "Simple Displace",
  "ISFVSN" : "2",
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "amount",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.8,
      "MIN" : 0
    },
    {
      "NAME" : "strength",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.5,
      "MIN" : 0
    },
    {
      "NAME" : "scale",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.2,
      "MIN" : 0
    },
    {
      "NAME" : "speed",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.2,
      "MIN" : 0
    }
  ],
  "CREDIT" : "by @colin_movecraft"
}
*/
#define 	twpi  	6.2831853  	// two pi, 2*pi

#define twpi 6.2831853

const vec3 NOISE_OFFSETS = vec3(0.0, 20.0, 40.0);
const float SCALE_X = 10.0;
const float SCALE_Y = 4.0;

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
  return mod289(((x * 34.0) + 1.0) * x);
}

vec4 taylorInvSqrt(vec4 r) {
  return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(vec3 v) { 
  const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

  vec3 i = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);

  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);

  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;

  i = mod289(i);
  vec4 p = permute(permute(permute(i.z + vec4(0.0, i1.z, i2.z, 1.0))
             + i.y + vec4(0.0, i1.y, i2.y, 1.0))
             + i.x + vec4(0.0, i1.x, i2.x, 1.0));

  float n_ = 0.142857142857;
  vec3 ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);
  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 s0 = floor(vec4(x.xy, y.xy)) * 2.0 + 1.0;
  vec4 s1 = floor(vec4(x.zw, y.zw)) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = vec4(x.xy, y.xy) + s0 * sh.xxyy;
  vec4 a1 = vec4(x.zw, y.zw) + s1 * sh.zzww;

  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);

  vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

  vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
  m = m * m;

  return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

vec3 surface(vec3 coord) {
  float noise1 = snoise(coord);
  float noise2 = snoise(coord + NOISE_OFFSETS.y);
  float noise3 = snoise(coord + NOISE_OFFSETS.z);
  
  return vec3(noise1, noise2, noise3);
}

void main() {
  vec2 p = isf_FragNormCoord.xy;

  vec3 noiseInput = vec3(p.x * scale * SCALE_X, p.y * scale * SCALE_Y, TIME * speed);
  vec3 n = surface(noiseInput);

  vec2 displace = vec2(n.r - n.b * 2.0, n.g - n.r - n.b * 2.0) - vec2(0.5);
  displace *= amount * strength * strength * strength * strength;

  gl_FragColor = IMG_NORM_PIXEL(inputImage, p + displace);
}
