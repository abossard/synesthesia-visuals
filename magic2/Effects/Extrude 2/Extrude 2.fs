/*{
	"DESCRIPTION": "Optimized shader with adjustable parameters for VJ use",
	"CREDIT": "by you",
	"CATEGORIES": [
		"Stylize"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "size",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.1,
			"MAX": 1.0
		},
		{
			"NAME": "zGain",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.1,
			"MAX": 4.0
		},
		{
			"NAME": "FAR",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.1,
			"MAX": 1.0
		},
		{
			"NAME": "timeSpeed",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.1,
			"MAX": 2.0
		},
		{
			"NAME": "rotationSpeed",
			"TYPE": "float",
			"DEFAULT": 0.2,
			"MIN": 0.0,
			"MAX": 1.0
		}
	]
}*/

#define MOSTFAR 128.0

// Global variables
vec4 iMouse = vec4(0.5 * RENDERSIZE.x, 0.5 * RENDERSIZE.y, 0.0, 0.0); // Centered
float objID;

// Standard 2D rotation formula
mat2 rot2(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

// Texture fetch with simple sRGB to linear conversion
vec3 getTex(vec2 p) {
    p *= vec2(RENDERSIZE.y / RENDERSIZE.x, 1);
    vec3 tx = IMG_NORM_PIXEL(inputImage, fract(p / 2.0 - 0.5)).xyz;
    return tx * tx;
}

// Height map value based on pixel's grayscale value
float hm(vec2 p) {
    return dot(getTex(p), vec3(0.299, 0.587, 0.114));
}

// Extrusion formula with zGain adjustment
float opExtrusion(float sdf, float pz, float h, float zGain) {
    vec2 w = vec2(sdf, abs(pz) - h * zGain);
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
}

// Unsigned box distance formula
float sBoxS(vec2 p, vec2 b, float sf) {
    return length(max(abs(p) - b + sf, 0.0)) - sf;
}

// Blocks function generating the scene
vec4 blocks(vec3 q3, float zGain) {
    float scale = 1.0 / (64.0 * size);
    vec2 l = vec2(scale);
    vec2 s = l * 2.0;
    float d = 1e5;
    vec2 p, ip;
    vec2 id = vec2(0);
    vec2 cntr = vec2(0);
    vec2 ps4[4];
    ps4[0] = vec2(-l.x, l.y);
    ps4[1] = vec2(l.x, l.y);
    ps4[2] = vec2(-l.x, -l.y);
    ps4[3] = vec2(l.x, -l.y);

    for (int i = 0; i < 4; i++) {
        cntr = ps4[i] / 2.0;
        p = q3.xy - cntr;
        ip = floor(p / s) + 0.5;
        p -= ip * s;
        vec2 idi = ip * s + cntr;
        float h = hm(idi) * 0.15;
        float di2D = sBoxS(p, l / 2.0 - 0.05 * scale, 0.015);
        float di = opExtrusion(di2D, q3.z + h, h, zGain);

        if (di < d) {
            d = di;
            id = idi;
        }
    }
    return vec4(d, id, 0.0);
}

// Map function to return scene distance
float map(vec3 p, float zGain) {
    float fl = -p.z + 0.1;
    vec4 d4 = blocks(p, zGain);
    objID = (fl < d4.x) ? 1.0 : 0.0;
    return min(fl, d4.x);
}

// Ray marching
float trace(vec3 ro, vec3 rd, float zGain) {
    float t = 0.0, d;
    for (int i = 0; i < 64; i++) {
        d = map(ro + rd * t, zGain);
        if (abs(d) < 0.001 || t > MOSTFAR) break;
        t += d * 0.7;
    }
    return min(t, MOSTFAR);
}

// Calculate normal from scene distance
vec3 getNormal(vec3 p, float zGain) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        map(p + e.xyy, zGain) - map(p - e.xyy, zGain),
        map(p + e.yxy, zGain) - map(p - e.yxy, zGain),
        map(p + e.yyx, zGain) - map(p - e.yyx, zGain)
    ));
}

// Main function
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - RENDERSIZE.xy * 0.5) / RENDERSIZE.y;
    float timeMod = TIME * timeSpeed;
    vec3 lk = vec3(0.0);
    vec3 ro = lk + vec3(-0.5 * 0.3 * cos(timeMod), -0.5 * 0.2 * sin(timeMod), -2.0);
    vec3 lp = ro + vec3(1.5, 2.0, -1.0);
    float FOV = 1.0;
    vec3 fwd = normalize(lk - ro);
    vec3 rgt = normalize(vec3(fwd.z, 0.0, -fwd.x));
    vec3 up = cross(fwd, rgt);
    vec3 rd = normalize(fwd + FOV * uv.x * rgt + FOV * uv.y * up);

    rd.xy *= rot2(rotationSpeed * sin(timeMod) / 32.0);

    float t = trace(ro, rd, zGain);
    vec3 col = vec3(0.0);

    if (t < MOSTFAR) {
        vec3 sp = ro + rd * t;
        vec3 sn = getNormal(sp, zGain);
        vec3 texCol = (objID < 0.5) ? smoothstep(0.0, 1.0, getTex(sp.xy)) : vec3(0.0);
        vec3 ld = lp - sp;
        float lDist = max(length(ld), FAR);
        ld /= lDist;
        float diff = max(dot(sn, ld), 0.0);
        float spec = pow(max(dot(reflect(ld, sn), rd), 0.0), 16.0);
        float fre = pow(clamp(dot(sn, rd) + 1.0, 0.0, 1.0), 2.0);
        col = texCol * (diff + vec3(0.25, 0.5, 1.0) * diff * fre * 16.0 + vec3(1.0, 0.5, 0.2) * spec * 2.0);
    }

    fragColor = vec4(sqrt(max(col, 0.0)), 1.0);
}

void main(void) {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}
