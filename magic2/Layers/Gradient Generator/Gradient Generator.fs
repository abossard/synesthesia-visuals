/*
{
  "CATEGORIES" : [
    "Generator"
  ],
  "DESCRIPTION" : "Multi-color gradient with grainy noise-textured distortion. Inspired by paper.design grain-gradient shader.",
  "ISFVSN" : "2",
  "INPUTS" : [
    {
      "NAME" : "color1",
      "TYPE" : "color",
      "DEFAULT" : [0.35, 0.0, 0.9, 1.0]
    },
    {
      "NAME" : "color2",
      "TYPE" : "color",
      "DEFAULT" : [0.85, 0.45, 0.75, 1.0]
    },
    {
      "NAME" : "color3",
      "TYPE" : "color",
      "DEFAULT" : [0.0, 0.55, 0.95, 1.0]
    },
    {
      "NAME" : "colorBack",
      "TYPE" : "color",
      "DEFAULT" : [0.0, 0.0, 0.0, 1.0]
    },
    {
      "NAME" : "softness",
      "TYPE" : "float",
      "DEFAULT" : 0.5,
      "MIN" : 0.0,
      "MAX" : 1.0
    },
    {
      "NAME" : "intensity",
      "TYPE" : "float",
      "DEFAULT" : 0.5,
      "MIN" : 0.0,
      "MAX" : 1.0
    },
    {
      "NAME" : "noise",
      "TYPE" : "float",
      "DEFAULT" : 0.25,
      "MIN" : 0.0,
      "MAX" : 1.0
    },
    {
      "NAME" : "shape",
      "TYPE" : "long",
      "DEFAULT" : 3,
      "VALUES" : [0, 1, 2, 3, 4, 5, 6],
      "LABELS" : ["Wave", "Dots", "Truchet", "Corners", "Ripple", "Blob", "Sphere"]
    },
    {
      "NAME" : "speed",
      "TYPE" : "float",
      "DEFAULT" : 1.0,
      "MIN" : 0.0,
      "MAX" : 4.0
    },
    {
      "NAME" : "scale",
      "TYPE" : "float",
      "DEFAULT" : 1.0,
      "MIN" : 0.1,
      "MAX" : 4.0
    }
  ],
  "CREDIT" : "Adapted from paper-design/shaders grain-gradient"
}
*/

#define TWO_PI 6.28318530718
#define PI 3.14159265358979323846

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

// --- Procedural hash (replaces texture-based randomizer) ---
float hash11(float p) {
    p = fract(p * 0.3183099) + 0.1;
    p *= p + 19.19;
    return fract(p * p);
}

float hash21(vec2 p) {
    p = fract(p * vec2(0.3183099, 0.3678794)) + 0.1;
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

// Procedural replacement for texture-based randomR
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

// --- FBM (fractal brownian motion) ---
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

// --- Truchet tiling ---
vec2 truchet(vec2 uv, float idx) {
    idx = fract(((idx - 0.5) * 2.0));
    if (idx > 0.75) {
        uv = vec2(1.0) - uv;
    } else if (idx > 0.5) {
        uv = vec2(1.0 - uv.x, uv.y);
    } else if (idx > 0.25) {
        uv = 1.0 - vec2(1.0 - uv.x, uv.y);
    }
    return uv;
}

void main() {
    // Normalized UV in [-1, 1] range, aspect-corrected
    vec2 uv = (gl_FragCoord.xy / RENDERSIZE.xy) * 2.0 - 1.0;
    float aspect = RENDERSIZE.x / RENDERSIZE.y;
    uv.x *= aspect;

    float colorsCount = 3.0;
    const float firstFrameOffset = 7.0;
    float t = 0.1 * (TIME * speed + firstFrameOffset);

    // Shape UV and grain UV
    vec2 shape_uv = uv / scale;
    vec2 grain_uv = uv * RENDERSIZE.y * 0.7 / scale;

    float shapeVal = 0.0;

    if (shape == 0) {
        // Wave
        float wave = cos(0.5 * shape_uv.x - 4.0 * t) * sin(1.5 * shape_uv.x + 2.0 * t) * (0.75 + 0.25 * cos(6.0 * t));
        shapeVal = 1.0 - smoothstep(-1.0, 1.0, shape_uv.y + wave);

    } else if (shape == 1) {
        // Dots
        float stripeIdx = floor(2.0 * shape_uv.x / TWO_PI);
        float rand = hash11(stripeIdx * 100.0);
        rand = sign(rand - 0.5) * pow(4.0 * abs(rand), 0.3);
        shapeVal = sin(shape_uv.x) * cos(shape_uv.y - 5.0 * rand * t);
        shapeVal = pow(abs(shapeVal), 4.0);

    } else if (shape == 2) {
        // Truchet
        float n2 = valueNoiseR(shape_uv * 0.4 - 3.75 * t);
        shape_uv.x += 10.0;
        shape_uv *= 0.6;
        vec2 tile = truchet(fract(shape_uv), randomR(floor(shape_uv)));
        float distance1 = length(tile);
        float distance2 = length(tile - vec2(1.0));
        n2 -= 0.5;
        n2 *= 0.1;
        shapeVal = smoothstep(0.2, 0.55, distance1 + n2) * (1.0 - smoothstep(0.45, 0.8, distance1 - n2));
        shapeVal += smoothstep(0.2, 0.55, distance2 + n2) * (1.0 - smoothstep(0.45, 0.8, distance2 - n2));
        shapeVal = pow(shapeVal, 1.5);

    } else if (shape == 3) {
        // Corners
        shape_uv *= 0.6;
        vec2 outer = vec2(0.5);
        vec2 bl = smoothstep(vec2(0.0), outer, shape_uv + vec2(0.1 + 0.1 * sin(3.0 * t), 0.2 - 0.1 * sin(5.25 * t)));
        vec2 tr = smoothstep(vec2(0.0), outer, 1.0 - shape_uv);
        shapeVal = 1.0 - bl.x * bl.y * tr.x * tr.y;
        shape_uv = -shape_uv;
        bl = smoothstep(vec2(0.0), outer, shape_uv + vec2(0.1 + 0.1 * sin(3.0 * t), 0.2 - 0.1 * cos(5.25 * t)));
        tr = smoothstep(vec2(0.0), outer, 1.0 - shape_uv);
        shapeVal -= bl.x * bl.y * tr.x * tr.y;
        shapeVal = 1.0 - smoothstep(0.0, 1.0, shapeVal);

    } else if (shape == 4) {
        // Ripple
        shape_uv *= 2.0;
        float dist = length(0.4 * shape_uv);
        float waves = sin(pow(dist, 1.2) * 5.0 - 3.0 * t) * 0.5 + 0.5;
        shapeVal = waves;

    } else if (shape == 5) {
        // Blob
        float bt = t * 2.0;
        vec2 f1_traj = 0.25 * vec2(1.3 * sin(bt), 0.2 + 1.3 * cos(0.6 * bt + 4.0));
        vec2 f2_traj = 0.2 * vec2(1.2 * sin(-bt), 1.3 * sin(1.6 * bt));
        vec2 f3_traj = 0.25 * vec2(1.7 * cos(-0.6 * bt), cos(-1.6 * bt));
        vec2 f4_traj = 0.3 * vec2(1.4 * cos(0.8 * bt), 1.2 * sin(-0.6 * bt - 3.0));
        shapeVal = 0.5 * pow(1.0 - clamp(length(shape_uv + f1_traj), 0.0, 1.0), 5.0);
        shapeVal += 0.5 * pow(1.0 - clamp(length(shape_uv + f2_traj), 0.0, 1.0), 5.0);
        shapeVal += 0.5 * pow(1.0 - clamp(length(shape_uv + f3_traj), 0.0, 1.0), 5.0);
        shapeVal += 0.5 * pow(1.0 - clamp(length(shape_uv + f4_traj), 0.0, 1.0), 5.0);
        shapeVal = smoothstep(0.0, 0.9, shapeVal);
        float edge = smoothstep(0.25, 0.3, shapeVal);
        shapeVal = mix(0.0, shapeVal, edge);

    } else {
        // Sphere
        shape_uv *= 2.0;
        float d = 1.0 - pow(length(shape_uv), 2.0);
        vec3 pos = vec3(shape_uv, sqrt(max(d, 0.0)));
        vec3 lightPos = normalize(vec3(cos(1.5 * t), 0.8, sin(1.25 * t)));
        shapeVal = 0.5 + 0.5 * dot(lightPos, pos);
        shapeVal *= step(0.0, d);
    }

    // Grain noise computation
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

    // Apply intensity and noise to shape
    shapeVal += intensity * 2.0 / colorsCount * (grainDist + 0.5);
    shapeVal += noise * 10.0 / colorsCount * noiseVal;

    float aa = 0.005;

    shapeVal = clamp(shapeVal - 0.5 / colorsCount, 0.0, 1.0);
    float totalShape = smoothstep(0.0, softness + 2.0 * aa, clamp(shapeVal * colorsCount, 0.0, 1.0));
    float mixer = shapeVal * (colorsCount - 1.0);

    // Color gradient blending (3 colors)
    vec4 colors[3];
    colors[0] = color1;
    colors[1] = color2;
    colors[2] = color3;

    vec4 gradient = colors[0];
    gradient.rgb *= gradient.a;
    for (int i = 1; i < 3; i++) {
        float localT = clamp(mixer - float(i - 1), 0.0, 1.0);
        localT = smoothstep(0.5 - 0.5 * softness - aa, 0.5 + 0.5 * softness + aa, localT);
        vec4 c = colors[i];
        c.rgb *= c.a;
        gradient = mix(gradient, c, localT);
    }

    vec3 outColor = gradient.rgb * totalShape;
    float opacity = gradient.a * totalShape;

    vec3 bgColor = colorBack.rgb * colorBack.a;
    outColor = outColor + bgColor * (1.0 - opacity);
    opacity = opacity + colorBack.a * (1.0 - opacity);

    gl_FragColor = vec4(outColor, opacity);
}
