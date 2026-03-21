/*
{
  "CATEGORIES" : [
    "Stylize"
  ],
  "DESCRIPTION" : "Grainy noise overlay and distortion effect. Adds organic film grain texture to the input.",
  "ISFVSN" : "2",
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "intensity",
      "TYPE" : "float",
      "DEFAULT" : 1,
      "MIN" : 0.0,
      "MAX" : 1.0
    },
    {
      "NAME" : "noise",
      "TYPE" : "float",
      "DEFAULT" : 0.7,
      "MIN" : 0.0,
      "MAX" : 1.0
    },
    {
      "NAME" : "scale",
      "TYPE" : "float",
      "DEFAULT" : 3.0,
      "MIN" : 0.1,
      "MAX" : 4.0
    },
    {
      "NAME" : "speed",
      "TYPE" : "float",
      "DEFAULT" : 0.5,
      "MIN" : 0.0,
      "MAX" : 4.0
    }
  ],
  "CREDIT" : "Adapted from paper-design/shaders grain-gradient"
}
*/

// --- Simplex noise ---
vec3 permute(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
float snoise(vec2 v) {
    const vec4 C = vec4(0.211324865405187, 0.366025403784439,
        -0.577350269189626, 0.024390243902439);
    vec2 i = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);
    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod(i, 289.0);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
        + i.x + vec3(0.0, i1.x, 1.0));
    vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
        dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    vec3 x = 2.0 * fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    vec3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

// --- Rotation helper ---
vec2 rotate(vec2 uv, float th) {
    return mat2(cos(th), sin(th), -sin(th), cos(th)) * uv;
}

// --- Procedural hash ---
float hash21(vec2 p) {
    p = fract(p * vec2(0.3183099, 0.3678794)) + 0.1;
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float randomR(vec2 p) {
    return hash21(floor(p));
}

// --- Value noise ---
float valueNoiseR(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    float a = randomR(i);
    float b = randomR(i + vec2(1.0, 0.0));
    float c = randomR(i + vec2(0.0, 1.0));
    float d = randomR(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    float x1 = mix(a, b, u.x);
    float x2 = mix(c, d, u.x);
    return mix(x1, x2, u.y);
}

// --- FBM ---
vec4 fbmR(vec2 n0, vec2 n1, vec2 n2, vec2 n3) {
    float amplitude = 0.2;
    vec4 total = vec4(0.);
    for (int i = 0; i < 3; i++) {
        n0 = rotate(n0, 0.3);
        n1 = rotate(n1, 0.3);
        n2 = rotate(n2, 0.3);
        n3 = rotate(n3, 0.3);
        total.x += valueNoiseR(n0) * amplitude;
        total.y += valueNoiseR(n1) * amplitude;
        total.z += valueNoiseR(n2) * amplitude;
        total.w += valueNoiseR(n3) * amplitude;
        n0 *= 1.99;
        n1 *= 1.99;
        n2 *= 1.99;
        n3 *= 1.99;
        amplitude *= 0.6;
    }
    return total;
}

void main() {
    vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
    vec4 src = IMG_THIS_PIXEL(inputImage);

    // Grain UV: pixel-space noise coordinates
    vec2 grain_uv = gl_FragCoord.xy * 0.7 / scale;

    // Animate grain slowly so it doesn't look static
    float t = TIME * speed * 0.3;
    grain_uv += vec2(t * 7.3, t * 5.1);

    // Compute grain noise
    float baseNoise = snoise(grain_uv * 0.5);
    vec4 fbmVals = fbmR(
        0.002 * grain_uv + 10.0,
        0.003 * grain_uv,
        0.001 * grain_uv,
        rotate(0.4 * grain_uv, 2.0)
    );
    float grainDist = baseNoise * snoise(grain_uv * 0.2) - fbmVals.x - fbmVals.y;
    float rawNoise = 0.75 * baseNoise - fbmVals.w - fbmVals.z;
    float noiseVal = clamp(rawNoise, 0.0, 1.0);

    // Intensity: UV distortion (displaces sample position)
    vec2 distortOffset = vec2(grainDist, rawNoise) * intensity * 0.02;
    vec2 distortedUV = clamp(uv + distortOffset, vec2(0.0), vec2(1.0));
    vec4 distorted = IMG_NORM_PIXEL(inputImage, distortedUV);

    // Noise: additive grain overlay
    float grain = (noiseVal - 0.5) * noise;

    vec3 outColor = distorted.rgb + grain;
    gl_FragColor = vec4(outColor, distorted.a);
}
