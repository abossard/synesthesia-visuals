/*{
    "CATEGORIES": [
        "Generator"
    ],
    "CREDIT": "Sonic Walker, based on cube1 by foreman",
    "DESCRIPTION": "Rotating 3D Wireframe Cube with Glow and Customizable Appearance",
    "INPUTS": [
        {
            "DEFAULT": 0,
            "MAX": 1,
            "MIN": 0,
            "NAME": "rotX",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0,
            "MAX": 1,
            "MIN": 0,
            "NAME": "rotY",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0,
            "MAX": 1,
            "MIN": 0,
            "NAME": "rotZ",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0,
            "MAX": 1,
            "MIN": -1,
            "NAME": "zoomAmount",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0.002,
            "MAX": 0.02,
            "MIN": 0.001,
            "NAME": "lineThickness",
            "TYPE": "float"
        },
        {
            "DEFAULT": 0.005,
            "MAX": 0.1,
            "MIN": 0,
            "NAME": "lineGlow",
            "TYPE": "float"
        },
        {
            "DEFAULT": [
                1,
                1,
                1,
                1
            ],
            "NAME": "lineColor",
            "TYPE": "color"
        }
    ],
    "ISFVSN": "2"
}
*/

#define PI 3.14159265359

vec2 projectPoint(vec3 p) {
    float fov = 1.5;
    return vec2(p.x / (p.z + 2.5), p.y / (p.z + 2.5)) * fov;
}

vec3 cubeVertex(int index) {
    if (index == 0) return vec3(-0.5, -0.5, -0.5);
    if (index == 1) return vec3(0.5, -0.5, -0.5);
    if (index == 2) return vec3(0.5, 0.5, -0.5);
    if (index == 3) return vec3(-0.5, 0.5, -0.5);
    if (index == 4) return vec3(-0.5, -0.5, 0.5);
    if (index == 5) return vec3(0.5, -0.5, 0.5);
    if (index == 6) return vec3(0.5, 0.5, 0.5);
    return vec3(-0.5, 0.5, 0.5);
}

int edgeStart(int index) {
    if (index == 0) return 0;
    if (index == 1) return 1;
    if (index == 2) return 2;
    if (index == 3) return 3;
    if (index == 4) return 4;
    if (index == 5) return 5;
    if (index == 6) return 6;
    if (index == 7) return 7;
    if (index == 8) return 0;
    if (index == 9) return 1;
    if (index == 10) return 2;
    return 3;
}

int edgeEnd(int index) {
    if (index == 0) return 1;
    if (index == 1) return 2;
    if (index == 2) return 3;
    if (index == 3) return 0;
    if (index == 4) return 5;
    if (index == 5) return 6;
    if (index == 6) return 7;
    if (index == 7) return 4;
    if (index == 8) return 4;
    if (index == 9) return 5;
    if (index == 10) return 6;
    return 7;
}

mat3 rotateX(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat3(
        1.0, 0.0, 0.0,
        0.0, c, -s,
        0.0, s, c
    );
}

mat3 rotateY(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat3(
        c, 0.0, s,
        0.0, 1.0, 0.0,
        -s, 0.0, c
    );
}

mat3 rotateZ(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat3(
        c, -s, 0.0,
        s, c, 0.0,
        0.0, 0.0, 1.0
    );
}

vec3 applyZoom(vec3 p) {
    float dist = length(p);
    return p * (1.0 + zoomAmount * dist * dist);
}

void main() {
    vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy * 2.0 - 1.0;
    uv.x *= RENDERSIZE.x / RENDERSIZE.y;
    
    float rotationAngleX = (PI) * 2. * rotX;
    float rotationAngleY = (PI) * 2. * rotY;
    float rotationAngleZ = (PI) * 2. * rotZ;

    mat3 rotationMatrix = rotateX(rotationAngleX) 
                        * rotateY(rotationAngleY) 
                        * rotateZ(rotationAngleZ);
    
    vec4 color = vec4(0.0);
    float minDistToCube = 1000.0;
    
    for (int i = 0; i < 12; i++) {
        vec3 start = cubeVertex(edgeStart(i));
        vec3 end = cubeVertex(edgeEnd(i));
        
        vec3 rotatedStart = rotationMatrix * start;
        vec3 rotatedEnd = rotationMatrix * end;
        
        vec3 zoomStart = applyZoom(rotatedStart);
        vec3 zoomEnd = applyZoom(rotatedEnd);
        
        vec2 projectedStart = projectPoint(zoomStart);
        vec2 projectedEnd = projectPoint(zoomEnd);
        
        vec2 line = projectedEnd - projectedStart;
        float h = clamp(dot(uv - projectedStart, line) / dot(line, line), 0.0, 1.0);
        vec2 pointOnLine = projectedStart + h * line;
        
        float distToLine = length(uv - pointOnLine);
        minDistToCube = min(minDistToCube, distToLine);
        
        float intensity = 1.0 - smoothstep(lineThickness, lineThickness + lineGlow, distToLine);
        color = max(color, vec4(lineColor.rgb * intensity, intensity * lineColor.a));
    }
    
    // Apply cube bounds mask
    float cubeMask = 1.0 - smoothstep(0.0, lineGlow * 2.0, minDistToCube - lineThickness);
    color *= cubeMask;
    
    gl_FragColor = color;
}