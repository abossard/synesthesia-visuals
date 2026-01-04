/*{
  "DESCRIPTION": "Truchet Pattern Generator with smooth transitions (fixed: valid JSON header, no uint, correct final pass)",
  "CREDIT": "Converted to ISF 2.0 with enhancements by dot2dot, original by @liu7d7 - Shadertoy. Fixed for broader ISF GLSL compatibility.",
  "ISFVSN": "2.0",
  "CATEGORIES": ["GENERATOR"],
  "INPUTS": [
    { "NAME": "speed", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 5.0, "LABEL": "Animation Speed" },
    { "NAME": "rotationSpeed", "TYPE": "float", "DEFAULT": 0.125, "MIN": -0.5, "MAX": 0.5, "LABEL": "Rotation Speed" },
    { "NAME": "scale", "TYPE": "float", "DEFAULT": 900.0, "MIN": 100.0, "MAX": 2000.0, "LABEL": "Pattern Scale" },
    { "NAME": "colorShift", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.1, "MAX": 2.0, "LABEL": "Color Shift Speed" },
    { "NAME": "colorA", "TYPE": "color", "DEFAULT": [0.5, 0.5, 0.5, 1.0], "LABEL": "Base Color A" },
    { "NAME": "colorB", "TYPE": "color", "DEFAULT": [0.5, 0.5, 0.5, 1.0], "LABEL": "Base Color B" },
    { "NAME": "colorC", "TYPE": "color", "DEFAULT": [0.8, 0.8, 0.5, 1.0], "LABEL": "Color Frequency" },
    { "NAME": "colorD", "TYPE": "color", "DEFAULT": [0.0, 0.2, 0.5, 1.0], "LABEL": "Color Phase" },
    { "NAME": "transitionSpeed", "TYPE": "float", "DEFAULT": 2.0, "MIN": 0.1, "MAX": 10.0, "LABEL": "Transition Smoothness" }
  ],
  "PASSES": [
    { "TARGET": "timeBuffer", "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1 },
    { "TARGET": "paramBuffer", "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1 },
    {}
  ]
}*/

#define PI 3.1415926

// Float-only hash (no uint/uvec2/bitwise ops)
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float triangle(float t, float p, float a) {
    float m = mod(t, p), hp = p * 0.5;
    float s = step(hp, m);
    return (m * (1.0 - s) + (p - m) * s) / hp * a;
}

vec3 colorFunc(float t, vec3 a, vec3 b, vec3 c, vec3 d) {
    return a + b * cos(2.0 * PI * (c * t + d));
}

#define rot(t) mat2(cos(t), sin(t), -sin(t), cos(t))

vec4 truchet(
    vec2 p, float r, float w, float time,
    vec3 a, vec3 b, vec3 c, vec3 d,
    float colorShiftSpeed
) {
    float hr = r / 2.0;
    float hw = w / 2.0;

    vec2 b_pos = floor(p / r) * r;
    vec2 c_pos = b_pos + vec2(hr);

    // 0..3 orientation
    float h = floor(hash21(abs(c_pos) * 0.01) * 4.0);
    float i = 3.0 - h;

    vec2 a0 = b_pos + vec2(mod(h, 2.0) * r, floor(h / 2.0) * r);
    vec2 a1 = b_pos + vec2(mod(i, 2.0) * r, floor(i / 2.0) * r);

    float d1 = distance(p, a0);
    float d2 = distance(p, a1);
    float dist = min(d1, d2);

    vec3 colorVal = colorFunc(triangle(time * colorShiftSpeed, 3.0, 1.0), a, b, c, d);

    float alpha = (1.0 - (abs(dist - hr) - hw) / max(w, 1e-6)) * 0.5;
    alpha = clamp(alpha, 0.0, 1.0);

    float edge = smoothstep(hw, hw + 1.414, abs(dist - hr));

    vec4 whitePart = vec4(1.0) * (1.0 - edge);
    vec4 colorPart = vec4(colorVal, alpha) * edge;

    return whitePart + colorPart;
}

void main() {
    vec4 prevTimeData, prevParamData;
    float accumulatedTime;
    float currentRotSpeed, adjustedRotSpeed;
    float currentScale, adjustedScale;
    float currentColorShift, adjustedColorShift;

    if (PASSINDEX == 0) {
        prevTimeData = IMG_NORM_PIXEL(timeBuffer, vec2(0.5, 0.5));
        accumulatedTime = prevTimeData.r;

        if (FRAMEINDEX == 0) accumulatedTime = 0.0;
        else accumulatedTime += TIMEDELTA * speed;

        gl_FragColor = vec4(accumulatedTime, 0.0, 0.0, 1.0);
    }
    else if (PASSINDEX == 1) {
        prevParamData = IMG_NORM_PIXEL(paramBuffer, vec2(0.5, 0.5));

        if (FRAMEINDEX == 0) {
            adjustedRotSpeed = rotationSpeed;
            adjustedScale = scale;
            adjustedColorShift = colorShift;
        } else {
            currentRotSpeed = prevParamData.r;
            currentScale = prevParamData.g;
            currentColorShift = prevParamData.b;

            float k = min(1.0, TIMEDELTA * transitionSpeed);
            adjustedRotSpeed = mix(currentRotSpeed, rotationSpeed, k);
            adjustedScale = mix(currentScale, scale, k);
            adjustedColorShift = mix(currentColorShift, colorShift, k);
        }

        gl_FragColor = vec4(adjustedRotSpeed, adjustedScale, adjustedColorShift, 1.0);
    }
    else {
        prevTimeData = IMG_NORM_PIXEL(timeBuffer, vec2(0.5, 0.5));
        prevParamData = IMG_NORM_PIXEL(paramBuffer, vec2(0.5, 0.5));

        float effectiveTime = prevTimeData.r;
        float effectiveRotSpeed = prevParamData.r;
        float effectiveScale = prevParamData.g;
        float effectiveColorShift = prevParamData.b;

        vec3 a_color = colorA.rgb;
        vec3 b_color = colorB.rgb;
        vec3 c_color = colorC.rgb;
        vec3 d_color = colorD.rgb;

        vec2 uv = (2.0 * gl_FragCoord.xy - RENDERSIZE.xy) / RENDERSIZE.y;
        uv *= effectiveScale / 2.0;
        uv = rot(effectiveTime * effectiveRotSpeed) * uv;

        vec3 finalCol = vec3(0.0);

        for (float j = 3.0; j > -0.1; j--) {
            vec2 offset = vec2(
                sin(effectiveTime * 1.3) * (400.0 - 400.0/6.0 * j),
                cos(effectiveTime * 0.7) * (400.0 - 400.0/6.0 * j)
            );

            vec4 truc = truchet(
                uv + offset,
                80.0 - j * 20.0,
                10.0 - j * 2.0,
                effectiveTime,
                a_color, b_color, c_color, d_color,
                effectiveColorShift
            ) * (4.0 - j * 0.75) * 0.25;

            float a = clamp(truc.a, 0.0, 1.0);
            finalCol = finalCol * (1.0 - a) + clamp(truc.rgb, 0.0, 1.0) * a;
        }

        gl_FragColor = vec4(finalCol, 1.0);
    }
}