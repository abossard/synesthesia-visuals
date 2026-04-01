
/*{
    "DESCRIPTION": "A converted shader with TIME, camera controls, and a parameter for smooth or hard grid extrusion patterns.",
    "CATEGORIES": [ "Raymarching" ],
    "INPUTS": [
        {
            "NAME": "xPos",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": -10.0,
            "MAX": 10.0
        },
        {
            "NAME": "yPos",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": 0.1,
            "MAX": 1.0
        },
        {
            "NAME": "cameraX",
            "TYPE": "float",
            "MIN": -3.14,
            "MAX": 3.14,
            "DEFAULT": 0.0
        },
        {
            "NAME": "cameraY",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.57,
            "DEFAULT": 1.2
        },
        {
            "NAME": "cameraZ",
            "TYPE": "float",
            "MIN": -3.14,
            "MAX": 3.14,
            "DEFAULT": 0.0
        },
        {
            "NAME": "extrude",
            "TYPE": "float",
            "MIN": 0.25,
            "MAX": 1,
            "DEFAULT": 0.8
        },
        {
            "NAME": "smoothness",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.5
        },
        {
            "NAME": "lineColor",
            "TYPE": "color",
            "DEFAULT": [1.0, 0.0, 0.1, 1.0],
            "DESCRIPTION": "Color of the haze effect."
        }
    ]
}*/

#define MIN_DIST 0.001
#define MAX_DIST 32.0
#define MAX_STEPS 96
#define STEP_MULT 0.9
#define NORMAL_OFFS 0.01
#define FOCAL_LENGTH 0.8

#define GRID_COLOR_1 vec3(0.00, 0.0, 0.0)
#define GRID_COLOR_2 vec3(1.00, 0.20, 0.60)

#define GRID_SIZE 0.50

#define SKYDOME 0.
#define FLOOR 1.

float pi = atan(1.0) * 4.0;
float tau = atan(1.0) * 8.0;

struct MarchResult {
    vec3 position;
    vec3 normal;
    float dist;
    float steps;
    float id;
};

mat3 Rotate(vec3 angles) {
    vec3 c = cos(angles);
    vec3 s = sin(angles);

    mat3 rotX = mat3(1.0, 0.0, 0.0, 0.0, c.x, s.x, 0.0, -s.x, c.x);
    mat3 rotY = mat3(c.y, 0.0, -s.y, 0.0, 1.0, 0.0, s.y, 0.0, c.y);
    mat3 rotZ = mat3(c.z, s.z, 0.0, -s.z, c.z, 0.0, 0.0, 0.0, 1.0);

    return rotX * rotY * rotZ;
}

vec2 opU(vec2 d1, vec2 d2) {
    return (d1.x < d2.x) ? d1 : d2;
}

vec2 opS(vec2 d1, vec2 d2) {
    return (-d1.x > d2.x) ? d1 * vec2(-1, 1) : d2;
}

vec2 sdSphere(vec3 p, float s, float id) {
    return vec2(length(p) - s, id);
}

vec2 sdBox( vec3 p, vec3 b, float id) {
  vec3 q = abs(p) - b;
  return vec2(length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0), id);
}

vec2 sdPlane(vec3 p, vec4 n, float id) {
    return vec2(dot(p, n.xyz) + n.w, id);
}


float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Triangle wave function with noise
float triangleWave(float x) {
    return -0.5 + abs(mod(x, 1.0) - 0.5); // Original triangle wave
}

// Main function that uses the triangle wave with noise
vec2 triWave(vec2 p) {
    float smoothF = 1.2;
    float smoothComp = (smoothF - smoothness * smoothF);
    float gain = extrude * 0.1 * smoothComp;
    float x = triangleWave(p.x + p.y);
    float y = triangleWave(p.y);
    return vec2(x * gain, y * gain);
}

// Updated heightmapNormal function
vec2 heightmapNormal(vec2 p) {
    vec2 squaredW = triWave(p);
    vec2 sinW = vec2(sin(p.x) * 0.15 * extrude, sin(p.y) * 0.15 * extrude);
    
    return mix(squaredW, sinW, 0.5 + smoothness * 0.5);

}

vec2 Scene(vec3 p) {
    vec2 d = vec2(MAX_DIST, SKYDOME);

    d = opU(sdPlane(p, normalize(vec4(heightmapNormal(p.xy), -1, 0)), FLOOR), d);

    return d;
}

vec3 Normal(vec3 p) {
    vec3 off = vec3(NORMAL_OFFS, 0, 0);
    return normalize(vec3(
        Scene(p + off.xyz).x - Scene(p - off.xyz).x,
        Scene(p + off.zxy).x - Scene(p - off.zxy).x,
        Scene(p + off.yzx).x - Scene(p - off.yzx).x
    ));
}

MarchResult MarchRay(vec3 orig, vec3 dir) {
    float steps = 0.0;
    float dist = 0.0;
    float id = 0.0;

    for (int i = 0; i < MAX_STEPS; i++) {
        vec2 object = Scene(orig + dir * dist);

        dist += object.x * STEP_MULT;

        id = object.y;

        steps++;

        if (abs(object.x) < MIN_DIST * dist) {
            break;
        }
    }

    MarchResult result;

    result.position = orig + dir * dist;
    result.normal = Normal(result.position);
    result.dist = dist;
    result.steps = steps;
    result.id = id;

    return result;
}

vec3 Shade(MarchResult hit, vec3 direction, vec3 camera) {
    vec3 color = vec3(0.0);

    if (hit.id == FLOOR) {
        vec2 uv = abs(mod(hit.position.xy + GRID_SIZE / 2.0, GRID_SIZE) - GRID_SIZE / 2.0);

        // Smooth or hard-edged grid
        float gridEdge = min(uv.x, uv.y) / GRID_SIZE;
        float edge = smoothstep(0., 0.1, gridEdge);
        color = mix(GRID_COLOR_1, lineColor.rgb, 1.0 - edge);
    }

    // Apply distance fog
    color *= 1.0 - smoothstep(0.0, MAX_DIST * 0.5 * (2.0 - yPos), hit.dist);

    return color;
}

void main() {
    vec2 res = RENDERSIZE.xy / RENDERSIZE.y;
    vec2 uv = gl_FragCoord.xy / RENDERSIZE.y;

    vec3 angles = vec3(cameraX, cameraY, 0.0);

    mat3 rotate = Rotate(angles.yzx);

    vec3 orig = vec3(xPos, (1.0 - yPos) * 5., -2.0) * rotate;

    vec3 dir = normalize(vec3(uv - res / 2.0, FOCAL_LENGTH)) * rotate;

    MarchResult hit = MarchRay(orig, dir);

    vec3 color = Shade(hit, dir, orig);

    gl_FragColor = vec4(color, 1.0);
}

