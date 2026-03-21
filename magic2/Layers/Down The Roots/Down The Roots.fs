/*{
    "DESCRIPTION": "Marble with integrated cracks",
    "CREDIT": "Original Shadertoy shader by user, converted to ISF",
    "ISFVSN": "2",
    "CATEGORIES": [
        "Tile Effect",
        "Generator"
    ],
    "INPUTS": [
        {
            "NAME": "zebra",
            "TYPE": "float",
            "DEFAULT": 1.0
        },
        {
            "NAME": "move",
            "TYPE": "float",
            "DEFAULT": 1.0
        },
        {
            "NAME": "zoom",
            "TYPE": "float",
            "DEFAULT": 0.5
        },
        {
            "NAME": "blend",
            "TYPE": "float",
            "DEFAULT": 1.0
        },
        {
            "NAME": "speed",
            "TYPE": "float",
            "MIN": -1.0,
            "MAX": 1.0,
            "DEFAULT": -0.2
        }
    ]
}*/

// Forked and modified from FabriceNeycets (as always) awesome work
// https://www.shadertoy.com/view/Xd3fRN

vec3 hash3(vec3 x) {
    const float A = 1103515245.0;
    const float B = 0.0000001;
    const float M = 2.0;

    return mod(x * A, M) / M + B;
}

#define hash22(p)  fract( 18.5453 * sin( p * mat2(127.1,311.7,269.5,183.3)) )
#define disp(p) ( -ofs + (1.+2.*ofs) * hash22(p) )
#define ofs 0.5
#define hash21(p) fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453123)
#define rot(a) mat2(cos(a),-sin(a),sin(a),cos(a))


int MOD = 1;
float RATIO = 1.0,
      CRACK_depth = 3.0,
      CRACK_zebra_scale = 1.0,
      CRACK_zebra_amp = 0.67,
      CRACK_profile = 1.0,
      CRACK_slope = 50.0,
      CRACK_width = 0.0;

float modInt(float x, float y) {
    return mod(x, y);  // Use built-in mod function for float
}

float dnoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p); 
        f = f * f * (3.0 - 2.0 * f); 
    
    float hash00 = hash21(i + vec2(0.0, 0.0));  // Hash value for bottom-left corner
    float hash10 = hash21(i + vec2(1.0, 0.0));  // Hash value for bottom-right corner
    float hash01 = hash21(i + vec2(0.0, 1.0));  // Hash value for top-left corner
    float hash11 = hash21(i + vec2(1.0, 1.0));  // Hash value for top-right corner
    
    // Interpolate along the x axis
    float interpX0 = mix(hash00, hash10, f.x);  // Interpolation for the bottom row
    float interpX1 = mix(hash01, hash11, f.x);  // Interpolation for the top row
    
    // Interpolate along the y axis
    float result = mix(interpX0, interpX1, f.y);  // Final interpolation
    
    return result;}

vec2 dnoise22(vec2 p) {
    vec2 p2 = p + vec2(17.7);
    float y = dnoise2(p2);
    float x = dnoise2(p);
    return vec2(x, y);  // Corrected arguments here
}


float fbm2(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 R = rot(0.37);

    for (int i = 0; i < 5; i++) {
        p = R * (p * 2.0);
        v += a * dnoise2(p);
        a *= 0.5;
    }

    return v;
}

vec2 fbm22(vec2 p) {
    vec2 v = vec2(0.0);
    float a = 0.5;
    mat2 R = rot(0.37);

    for (int i = 0; i < 5; i++) {
        p = R * (p * 2.0);
        v += a * dnoise22(p);
        a *= 0.5;
    }

    return v;
}



int modInt(int x, int y) {
    return x - y * (x / y);  // Replace mod with faster alternative
}

vec3 voronoi(vec2 u) {
    vec2 iu = floor(u);
    vec2 v;
    float m = 1e9, d;

    vec2 p = iu + vec2(3, 2);
    vec2 o = disp(p);
    vec2 r = p - u + o;
    d = dot(r, r);
    if (d < m) {
        m = d;
        v = r;
    }

    return vec3(sqrt(m), v + u);
}

vec3 voronoiB(vec2 u) {
    vec2 iu = floor(u);
    vec2 C, P;
    float m = 1e9, d;

    for (int k = 0; k < 19; k++) {
        vec2 p = iu + vec2(modInt(k, 5) - 2, k / 5 - 2);
        vec2 o = disp(p);
        vec2 r = p - u + o;
        d = dot(r, r);
        if (d < m) {
            m = d;
            C = p - iu;
            P = r;
        }
    }

    m = 1e9;
    
    for (int k = 0; k < 15; k++) {
        vec2 p = iu + C + vec2(modInt(k, 5) - 2, k / 5 - 2);
        vec2 o = disp(p);
        vec2 r = p - u + o;

        float dot_diff = dot(P - r, P - r);
        if (dot_diff > 1e-5) {
            m = min(m, 0.5 * dot((P + r), normalize(r - P)));
        }
    }

    return vec3(m, P + u);
}

void main() {
    vec2 U = gl_FragCoord.xy * 4.0 / RENDERSIZE.y;
    vec3 H0 = vec3(0.0);
    vec4 O = vec4(0.0);
    
    for (float i = 0.0; i < 3.0; i++) {
        float layerFactor = (4.0 - i) * 0.25;  // Foreground layers move faster
        
        vec2 layerU = U + vec2(0.0, TIME * speed * layerFactor);
        vec2 V = layerU / vec2(RATIO, 1.0);
        vec2 D = CRACK_zebra_amp * fbm22(layerU / CRACK_zebra_scale * zebra * 2.) * CRACK_zebra_scale + (move * 0.2);
        vec3 H = voronoiB(V + D); 
        if (i == 0.0) H0 = H;
        float d = H.x;
        d = min(1.0, CRACK_slope * pow(max(0.0, d - CRACK_width), CRACK_profile));
    
        O += vec4(1.0 - d) / exp2(i / (0.01 + blend));
    
        U = (U - 0.5 * layerFactor) * (1.0 + zoom) + 0.5;
    }

    gl_FragColor = vec4(O.rgb, 1.0);
}
