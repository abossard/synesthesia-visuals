/*

{
  "CATEGORIES": ["Optimized","FullOverlap"],
  "DESCRIPTION": "Full overlap (no alpha), adaptive stepping. Discrete per-line colors A/B/C with controllable line count and look.",
  "IMPORTED": {},
  "INPUTS": [
    {"DEFAULT":1.8,  "LABEL":"twist",      "MAX":5.0, "MIN":1.0, "NAME":"twist",      "TYPE":"float"},
    {"DEFAULT":0.1,  "LABEL":"speed",      "MAX":0.6,            "NAME":"speed",      "TYPE":"float"},
    {"DEFAULT":6.0,  "LABEL":"twist2",     "MAX":20.0,"MIN":0.0, "NAME":"twist2",     "TYPE":"float"},
    {"DEFAULT":0.3,  "LABEL":"cork",       "MAX":4.0, "MIN":0.0, "NAME":"cork",       "TYPE":"float"},
    {"DEFAULT":1.0,  "LABEL":"clip",       "MAX":1.0, "MIN":0.0, "NAME":"clip",       "TYPE":"float"},

    {"DEFAULT":0.48, "LABEL":"Cell Size (more lines ←)", "MAX":1.0, "MIN":0.05, "NAME":"cellSize",   "TYPE":"float"},
    {"DEFAULT":0.3,  "LABEL":"Thickness",                "MAX":2.5, "MIN":0.25, "NAME":"thickness",  "TYPE":"float"},
    {"DEFAULT":0.37, "LABEL":"Clip Bias",                "MAX":0.6, "MIN":0.0,  "NAME":"clipBias",   "TYPE":"float"},
    {"DEFAULT":1.08, "LABEL":"Gamma",                    "MAX":1.3, "MIN":0.4,  "NAME":"gamma",      "TYPE":"float"},
    {"DEFAULT":0.0,  "LABEL":"Color Mode (0/1/2)",       "MAX":2.0, "MIN":0.0,  "NAME":"colorMode",  "TYPE":"float"},

    {"NAME":"COLORA","LABEL":"Color A","TYPE":"color","DEFAULT":[0.95,0.80,0.20,1.0]},
    {"NAME":"COLORB","LABEL":"Color B","TYPE":"color","DEFAULT":[0.20,0.80,1.00,1.0]},
    {"NAME":"COLORC","LABEL":"Color C","TYPE":"color","DEFAULT":[0.90,0.30,1.00,1.0]}
  ],
  "ISFVSN":"2"
}



*/

// Full-overlap, no alpha blending, adaptive ray-march (fast path).
// Discrete per-line color selection (A/B/C) via tile ID + modes.

mat2 rot2(float a){ float s=sin(a), c=cos(a); return mat2(c,-s,s,c); }

// global to carry tile class from map() to caller
float gSelF = 0.0; // 0,1,2 -> A,B,C

float map(vec3 p){
    // twists
    p.x += sin(p.z * twist);
    p.y += cos(p.z * twist2) * sin(p.x * cork);

    // rotate around Z
    float ang = p.z * 0.8 + sin(p.x) + cos(p.y);
    p.xy = rot2(ang) * p.xy;

    // precompute tiling with adjustable cellSize
    float cs = max(0.0001, cellSize);
    float invCs = 1.0 / cs;
    vec2 uvTile = p.xy * invCs;   // == p.xy / cs
    vec2 tile   = floor(uvTile);

    // wrap into cell (cheap tiling)
    p.xy = (fract(uvTile) - 0.5) * cs;

    // color bucket patterns
    float sel;
    if (colorMode < 0.5)      sel = mod(tile.x + tile.y, 3.0);        // checker-ish
    else if (colorMode < 1.5) sel = mod(tile.x + tile.y * 2.0, 3.0);  // diagonal drift
    else                      sel = mod(tile.x * 2.0 + tile.y, 3.0);  // alt X weight
    gSelF = sel;

    // distance to line (XY)
    return length(p.xy);
}

void main(){
    vec2 uv = (gl_FragCoord.xy - RENDERSIZE.xy * 0.5) / RENDERSIZE.y;

    // camera
    vec3 rd = normalize(vec3(uv, (1.0 - dot(uv,uv) * 0.5) * 0.5));
    vec3 ro = vec3(0.0, 0.0, TIME * 1.26 * speed);

    // spin
    float ang = TIME * 0.375 * speed;
    rd.xz = rot2(ang) * rd.xz;

    // march
    const int LOOP_CAP = 80;              // hard cap
    float t = 0.06;
    float layers = 0.0;

    // thickness in scene units (scaled)
    float thBase = 0.02 * thickness;

    // per-bucket accumulators (winner-takes-all, full overlap)
    float mA = 0.0, mB = 0.0, mC = 0.0;

    // runtime max steps (avoid branching the for loop bound)

    for(int i=0; i<LOOP_CAP; i++){
        if(layers > 4. || t > 5.6) break;

        // progressive density: denser early, looser later
        float stepMul = mix(0.18, 1.0, float(i)/float(LOOP_CAP));

        vec3 sp = ro + rd * t;
        float d  = map(sp);
        int sel  = int(gSelF + 0.5);

        // robust step size tied to clip and cellSize (prevents “dots” at high clip)
        float stepLen = max(d * 0.55, thBase * 0.9) * stepMul * (clipBias + 0.3 * clip);

        // inflate thickness with step to remain continuous
        float th = thBase + stepLen * 0.65;

        // response around surface
        float aD = (th - abs(d)) / th;

        if(aD > 0.0){
            // base weight + distance falloff
            float w = aD * aD * (3.0 - 2.0 * aD) / (1.0 + t*t*0.25) * 0.28;

            // central tap to selected bucket
            if(sel==0) mA = max(mA, w);
            else if(sel==1) mB = max(mB, w);
            else mC = max(mC, w);

            layers += 1.0;

            // early out if we already have a strong hit and enough layers
            float mMaxPre = max(mA, max(mB, mC));
            if(mMaxPre > 0.98 && layers > 6.0) break;
        }

        t += stepLen * clip;
    }

    // choose winning bucket first, then apply gain/gamma ONCE
    float mPreA = mA, mPreB = mB, mPreC = mC;
    float mPre  = mPreA; int idx = 0;
    if(mPreB > mPre){ mPre = mPreB; idx = 1; }
    if(mPreC > mPre){ mPre = mPreC; idx = 2; }

    float m = pow(clamp(mPre * 4.0, 0.0, 1.0), max(0.0001, gamma));

    vec3 col = (idx==0) ? COLORA.rgb * m :
               (idx==1) ? COLORB.rgb * m :
                          COLORC.rgb * m;

    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
