/*
{
    "CREDIT": "Magic Music Visuals",
    "DESCRIPTION": "Procedural mask of dancing figures based on 3D projected skeletons",
    "ISFVSN": "2.0",
    "CATEGORIES": [
        "Generator",
        "Mask",
        "People"
    ],
    "INPUTS": [
        {
            "NAME": "speed",
            "TYPE": "float",
            "DEFAULT": 1,
            "MIN": 0,
            "MAX": 3
        },
        {
            "NAME": "scale",
            "TYPE": "float",
            "DEFAULT": 1,
            "MIN": 0.5,
            "MAX": 2
        },
        {
            "NAME": "blur",
            "TYPE": "float",
            "DEFAULT": 0.01,
            "MIN": 0,
            "MAX": 0.2
        },
        {
            "NAME": "invert",
            "TYPE": "bool",
            "DEFAULT": false
        }
    ]
}
*/

#define PI 3.14159265359

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float sdSegment(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

vec3 rotX(vec3 p, float a) {
    float s = sin(a); float c = cos(a);
    return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

vec3 rotY(vec3 p, float a) {
    float s = sin(a); float c = cos(a);
    return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

vec3 rotZ(vec3 p, float a) {
    float s = sin(a); float c = cos(a);
    return vec3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

void main() {
    vec2 uv = (gl_FragCoord.xy * 2.0 - RENDERSIZE.xy) / RENDERSIZE.y;
    uv /= scale;

    float d = 1000.0;
    
        for (int i = 0; i < 3; i++) {
        float idx = float(i);
                float t = TIME * speed + idx * 12.34;
        
                float hScale = 1.0;
        float wScale = 1.0;
        float fatness = 0.0;
        
                vec3 root = vec3((idx - 1.0) * 0.9, -0.3, 0.0);
        
                if (i == 0) { 
                        hScale = 1.1; 
            fatness = 0.035;
            t *= 1.1;
        } else if (i == 1) { 
                        hScale = 0.9; 
            wScale = 1.1;
            fatness = 0.055;
            root.y -= 0.05;
        } else { 
                        hScale = 1.0; 
            fatness = 0.045;
            t *= 1.2;
        }

                
                float bounce = abs(sin(t * 4.0)) * 0.05;
        float sway = sin(t * 2.0) * 0.08 * wScale;
        root += vec3(sway, bounce, 0.0);
        
                vec3 spine = vec3(0.0, 0.45 * hScale, 0.0);
                spine = rotZ(spine, sin(t) * 0.1);
        spine = rotY(spine, sin(t * 0.7) * 0.2);
        vec3 neckPos = root + spine;
        
                vec3 headPos = neckPos + vec3(0.0, 0.15 * hScale, 0.0);
        headPos = rotZ(headPos - neckPos, sin(t * 3.0) * 0.1) + neckPos;
        
                float shWidth = 0.22 * wScale;
        vec3 shL = neckPos + rotY(vec3(-shWidth, -0.05, 0.0), sin(t*0.5)*0.5);
        vec3 shR = neckPos + rotY(vec3(shWidth, -0.05, 0.0), sin(t*0.5)*0.5);
        
                float armPhase = t * 2.5;
                vec3 uaL = vec3(-0.25 * hScale, 0.0, 0.0);         uaL = rotZ(uaL, sin(armPhase + idx) * 1.5 - 0.5);
        uaL = rotX(uaL, sin(t * 3.0));
        vec3 elbL = shL + uaL;
        
        vec3 laL = vec3(-0.25 * hScale, 0.0, 0.0);         laL = rotZ(laL, abs(sin(armPhase * 1.3)) * 2.0);         vec3 handL = elbL + laL;
        
                vec3 uaR = vec3(0.25 * hScale, 0.0, 0.0);
        uaR = rotZ(uaR, cos(armPhase + idx) * 1.5 + 0.5);
        uaR = rotX(uaR, cos(t * 3.1));
        vec3 elbR = shR + uaR;
        
        vec3 laR = vec3(0.25 * hScale, 0.0, 0.0);
        laR = rotZ(laR, -abs(cos(armPhase * 1.3)) * 2.0);
        vec3 handR = elbR + laR;
        
                float hipWidth = 0.12 * wScale;
        vec3 hipL = root + vec3(-hipWidth, 0.0, 0.0);
        vec3 hipR = root + vec3(hipWidth, 0.0, 0.0);
        
                float legPhase = t * 4.0;
        
                vec3 ulL = vec3(0.0, -0.35 * hScale, 0.0);
        ulL = rotX(ulL, sin(legPhase) * 0.5);
        vec3 kneeL = hipL + ulL;
        
        vec3 llL = vec3(0.0, -0.35 * hScale, 0.0);
        llL = rotX(llL, max(0.0, sin(legPhase + 0.5) * 1.5));         vec3 footL = kneeL + llL;
        
                vec3 ulR = vec3(0.0, -0.35 * hScale, 0.0);
        ulR = rotX(ulR, sin(legPhase + PI) * 0.5);
        vec3 kneeR = hipR + ulR;
        
        vec3 llR = vec3(0.0, -0.35 * hScale, 0.0);
        llR = rotX(llR, max(0.0, sin(legPhase + PI + 0.5) * 1.5));
        vec3 footR = kneeR + llR;

                        
        float cd = 100.0;
        
                cd = length(uv - headPos.xy) - (0.12 * wScale);
        
                float torsoR = fatness + 0.08 * wScale;
        cd = smin(cd, sdSegment(uv, root.xy, neckPos.xy, torsoR), 0.05);
        
                float armR = fatness + 0.03;
        cd = smin(cd, sdSegment(uv, shL.xy, elbL.xy, armR), 0.04);
        cd = smin(cd, sdSegment(uv, elbL.xy, handL.xy, armR * 0.8), 0.04);
        cd = smin(cd, sdSegment(uv, shR.xy, elbR.xy, armR), 0.04);
        cd = smin(cd, sdSegment(uv, elbR.xy, handR.xy, armR * 0.8), 0.04);
        
                float legR = fatness + 0.045;
        cd = smin(cd, sdSegment(uv, hipL.xy, kneeL.xy, legR), 0.05);
        cd = smin(cd, sdSegment(uv, kneeL.xy, footL.xy, legR * 0.8), 0.05);
        cd = smin(cd, sdSegment(uv, hipR.xy, kneeR.xy, legR), 0.05);
        cd = smin(cd, sdSegment(uv, kneeR.xy, footR.xy, legR * 0.8), 0.05);
        
                cd = smin(cd, sdSegment(uv, neckPos.xy, shL.xy, armR), 0.05);
        cd = smin(cd, sdSegment(uv, neckPos.xy, shR.xy, armR), 0.05);

                d = min(d, cd);
    }
    
        float edge = max(0.0001, blur);
    float mask = 1.0 - smoothstep(-edge, edge, d);
    
        if (invert) {
        mask = 1.0 - mask;
    }
    
            gl_FragColor = vec4(vec3(mask), mask);
}

// COST=26.4764
// MODEL=gemini-3-pro-preview
// PROMPT=make people dancing, but hyperrealistic like the iPod ads, so flat, 2d and like a mask. it can be based on real 3D but flat rendered. MAke it multiple people, woman, man, taller and smaller once, fatter onces, gooood dancers!!! GO
//