/*
 * Copyright (C) Michael Thomas / Jiagual 2024
 *
 * 
 */
 
#define PI 3.141592
#define TAU (2. * PI)
#define SIN(x) (sin(x) * .5 + .5)
#define BUMP_EPS 0.004
#define sabsk(x, k) sqrt(x *x + k * k)
#define sabs(x) (sabsk(x, .1))
#define S(a, b, x) smoothstep(a, b, x)

const highp float NOISE_GRANULARITY = 0.5 / 255.0;

float tt, g_mat, fadeIn;
vec3 ro;

mat2 rot(float a) { return mat2(cos(a), -sin(a), sin(a), cos(a)); }

float saturate(float x) { return clamp(x, 0., 1.); }


//  some 2d noise for dithering
highp float random(highp vec2 coords) {
    return fract(sin(dot(coords.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Normal of a plan having a dihedral angle of PI/3 with the YZ plan and PI/5
// with the XZ plane
const float CP = cos(3.1415 / 5.), SP = sqrt(0.75 - CP * CP);
const vec3 P35 = vec3(-0.5, -CP, SP);

// Dihedral angles of the Dode. and Ico.
// This probably can be obtained using linera algebra calculations
// https://en.wikipedia.org/wiki/Table_of_polyhedron_dihedral_angles

const float ICODIHEDRAL = acos(sqrt(5.) / 3.);
const float DODEDIHEDRAL = acos(sqrt(5.) / 5.);

// below are the directions from the origin limiting the coordniate's domain
// after folding space trivial, this is the Z axis
const vec3 ICOMIDEDGE = vec3(0, 0, 1);
// direction in the XZ plan, the ICO vertex on this line
// I think this is also the normal of a DODE face
const vec3 ICOVERTEX = normalize(vec3(SP, 0.0, 0.5));
// direction in the YZ plan, you will find the DODE vertex on this line
// I think this is also the normal of an ICO face
const vec3 ICOMIDFACE = normalize(vec3(0.0, SP, CP));


const float X_TO_ICO_VERTEX =
    length(cross(ICOMIDEDGE, ICOVERTEX)) / dot(ICOMIDEDGE, ICOVERTEX);
const float Y_TO_DODE_VERTEX =
    length(cross(ICOMIDEDGE, ICOMIDFACE)) / dot(ICOMIDEDGE, ICOMIDFACE);
const float X_TO_DODE_CENTER = X_TO_ICO_VERTEX * cos(DODEDIHEDRAL * .5);
const float Y_TO_ICO_CENTER = Y_TO_DODE_VERTEX * cos(ICODIHEDRAL * .5);

#define COPY_COLOR(N, colorsK)    \
    for (int i = 0; i < N; i++) { \
        colors[i] = colorsK[i];   \
    }

vec3 rgb2hsl(vec3 color) {
    float r = color.r;
    float g = color.g;
    float b = color.b;
    float max = max(max(r, g), b);
    float min = min(min(r, g), b);
    float h, s, l;
    l = (max + min) / 2.0;

    if (max == min) {
        h = s = 0.0;  // achromatic
    } else {
        float d = max - min;
        s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
        if (max == r) {
            h = (g - b) / d + (g < b ? 6.0 : 0.0);
        } else if (max == g) {
            h = (b - r) / d + 2.0;
        } else if (max == b) {
            h = (r - g) / d + 4.0;
        }
        h /= 6.0;
    }
    return vec3(h, s, l);
}

const vec3 colors2[] = vec3[](
    vec3(27, 231, 255) / 255.0, // Electric blue
    vec3(110, 235, 131) / 255.0, // Light green
    vec3(228, 255, 26) / 255.0, // Lemon Lime
    vec3(255, 184, 0) / 255.0, // Selective yellow
    vec3(255, 87, 20) / 255.0 // Giants orange
);

const vec3 colors1[] = vec3[](
    vec3(84, 13, 110) / 255.0, // Indigo
    vec3(238, 66, 102) / 255.0, // Red (Crayola)
    vec3(255, 210, 63) / 255.0, // Sunglow
    vec3(59, 206, 172) / 255.0, // Turquoise
    vec3(14, 173, 105) / 255.0 // Jade
);
  

const vec3 colors3[] = vec3[](
    vec3(155, 93, 229) / 255.0, // Amethyst
    vec3(241, 91, 181) / 255.0, // Brilliant rose
    vec3(254, 228, 64) / 255.0, // Maize
    vec3(0, 187, 249) / 255.0, // Deep Sky Blue
    vec3(0, 245, 212) / 255.0 // Aquamarine
);


const vec3 colors4[] = vec3[](
    vec3(0.169, 0.761, 0.718),
    vec3(0.357, 0.518, 0.008),
    vec3(0.604, 0.851, 0.259),
    vec3(0.820, 0.235, 0.196),
    vec3(0.522, 0.075, 0.020)
);

const vec3 colors5[] = vec3[](
    vec3(237, 174, 73) / 255.0, // Hunyadi yellow
    vec3(209, 73, 91) / 255.0, // Amaranth
    vec3(0, 121, 140) / 255.0, // Caribbean Current
    vec3(48, 99, 142) / 255.0, // Lapis Lazuli
    vec3(0, 61, 91) / 255.0 // Indigo dye
);


const vec3 colors6[] = vec3[](
    vec3(0, 204, 255) / 255.0, // Vivid sky blue
    vec3(0, 255, 204) / 255.0, // Aquamarine
    vec3(255, 255, 0) / 255.0, // Yellow
    vec3(255, 0, 204) / 255.0, // Hot magenta
    vec3(204, 0, 255) / 255.0 // Electric purple
);


const vec3 colors8[] = vec3[](
    vec3(39, 39, 39) / 255.0, // Raisin black
    vec3(254, 215, 102) / 255.0, // Mustard
    vec3(0, 159, 183) / 255.0, // Moonstone
    vec3(105, 103, 115) / 255.0, // Dim gray
    vec3(239, 241, 243) / 255.0 // Anti-flash white
);

const vec3 colors9[] = vec3[](
    vec3(0.000, 0.141, 0.224),
    vec3(0.000, 0.314, 0.400),
    vec3(0.306, 0.475, 0.533),
    vec3(0.471, 0.800, 0.886),
    vec3(0.894, 0.937, 0.941)
);

// Allow up to 10 colors per palette
vec3 getColorRamp_(vec3 cols[10], int N, float x) {
    // Calculate adjusted length to ensure end color is reachable within [0, 1]
    float len = float(N);

    // Scale x according to the adjusted length and apply modulo for wrapping
    float scaledX = mod(x * (len - 1.), len);

    // Calculate indices. Ensure index2 wraps around to the start if necessary
    int index1 = int(scaledX);
    int index2 = index1 + 1;
    if (index2 >= cols.length()) {
        index2 = 0;  // Wrap to the start to close the loop
    }

    // Calculate the fraction between the two indices for smooth interpolation
    float frac = fract(scaledX);

    // Interpolate between the two selected colors
    return mix(cols[index1], cols[index2], smoothstep(0.0, .9, frac));
}

vec3 getColorRamp(int palette, float x) {

    vec3 colors[10];
    int len = 0;
    
    
    if(palette == 0) {
        len = colors1.length();
        COPY_COLOR(len, colors1);       
    }
    
    if(palette == 1) {
        len = colors2.length();
        COPY_COLOR(len, colors2);
    }
    if(palette == 2) {
        len = colors3.length();
        COPY_COLOR(len, colors3);
        
    }
    if(palette == 3) {
        len = colors4.length();
        COPY_COLOR(len, colors4);    
    }
    
    if(palette == 4) {
        len = colors5.length();
        COPY_COLOR(len, colors5);    
    }
    if(palette == 5) { 
        len = colors6.length();
        COPY_COLOR(len, colors6);    
    }
    if(palette == 6) {
        len = colors8.length();
        COPY_COLOR(len, colors8);    
    }
    if(palette == 7) {
        len = colors9.length();
        COPY_COLOR(len, colors9);    
    }
    return getColorRamp_(colors, len, x);

}

// zucconis spectral palette
// https://www.alanzucconi.com/2017/07/15/improving-the-rainbow-2/
vec3 bump3y(vec3 x, vec3 yoffset) {
    vec3 y = 1. - x * x;
    y = clamp((y - yoffset), vec3(0), vec3(1));
    return y;
}
// Zucconi's spectral palette
vec3 spectral_zucconi6(float x) {
    x = fract(x);
    const vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
    const vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
    const vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);
    const vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
    const vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
    const vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);
    return bump3y(c1 * (x - x1), y1) + bump3y(c2 * (x - x2), y2);
}

vec3 getPal(int id, float t) {
    
    id = id % 12;

    vec3 col = vec3(0);
    if( id == 0 ) col = getColorRamp(0, t); // Vibrant Coral 
    if( id == 1 ) col = getColorRamp(5, t); // Neon 
    if( id == 2 ) col = getColorRamp(1, t); // Ocean Sunset 
    if( id == 3 ) col = getColorRamp(6, t); // Electric Cosmos 
    if( id == 4 ) col = getColorRamp(3, t); // Chameleon
	if( id == 5 ) col = spectral_zucconi6(t);
    if( id == 6 ) col = getColorRamp(2, t); // Pastel 
    if( id == 7) col = getColorRamp(4, t); // Vulcaono
    if( id == 8) col = getColorRamp(7, t); // SciFi Machine
    if( id == 9) col = mix(vec3(0), vec3(1), S(0., 1., SIN(5.*t)));
    return col;
}

float smoothNoise21(vec2 p) {
    // Calculate integer and fractional coordinates
    vec2 i = floor(p);
    vec2 f = fract(p);

    // Compute gradients at the four corners of the cell
    float n00 = dot(
        vec2(cos(dot(i, vec2(127.1, 311.7))), sin(dot(i, vec2(127.1, 311.7)))),
        f - vec2(0.0, 0.0));
    float n01 = dot(vec2(cos(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))),
                         sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7)))),
                    f - vec2(0.0, 1.0));
    float n10 = dot(vec2(cos(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))),
                         sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7)))),
                    f - vec2(1.0, 0.0));
    float n11 = dot(vec2(cos(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))),
                         sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7)))),
                    f - vec2(1.0, 1.0));

    // Smooth interpolation using Hermite curve (smoothstep)
    vec2 u = f * f * (3.0 - 2.0 * f);

    // Bilinear interpolation with gradients
    return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}

float rect(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - (b - r);
    return length(max(d, 0.)) + min(max(d.x, d.y), 0.) - r;
}

vec3 invGamma(vec3 col) { return pow(col, vec3(2.2)); }

vec3 gamma(vec3 col) { return pow(col, vec3(1. / 2.2)); }



// spectral palette by wavelength
vec3 waveSpectrum(float w) {
    if (w > 700.0 || w < 400.0) {
        return vec3(0);
    }

    float x = fract((w - 400.0) / 300.0);

    vec3 col = spectral_zucconi6(x);

    // Undo gamma
    col = invGamma(col);

    return col;
}

vec2 field(in vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);
    vec2 m = vec2(5., 1.);
    for (int j = 0; j <= 1; j++)
        for (int i = 0; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 r = g - f;
            float d =
                length(r) * (sin(1.) * 0.5 + 1.5);  // any metric can be used
            d = sin(d * 5. + 1.5);
            m.x *= d;
            m.y += d * 1.4;
        }
    return abs(m);
}

vec3 tex(in vec2 p, in float ofst) {
    p *= .3;

    vec2 rz = field(p * ofst * 0.5);
    vec3 col =
        sin(vec3(1., 1., .1) * rz.y * .1 + 3. + ofst * 2.) + .9 * (rz.x + 1.);
    col = col * col * .6;
    col *= .3;
    return col * vec3(0.933, 0.882, 0.843);
}

vec3 cubem(in vec3 p, in float ofst) {
    vec3 col =
        mix(vec3(0.275, 0.255, 0.208) * 4., vec3(1),
            smoothstep(0., .5,
                       p.y + sin(p.x * 2.) * .2 + .4 - .2 * sin(p.y * 2.4)));

    col *= 1.2 * mix(vec3(0.169, 0.157, 0.129) * 1.2, vec3(1),
                     smoothstep(0., .5, p.y + sin(p.x * 5.) * .2));
    col *= mix(vec3(0.545, 0.392, 0.176), vec3(1),
               smoothstep(0., .4, p.y + asin(sin(p.x * 9. + 2.) * .25)));
    col *= mix(vec3(0.322, 0.420, 0.404) * 2., vec3(1),
               smoothstep(0., .9, p.y + sin(p.x * 3. + 5.) * .3));
    return col;
}

// from https://mercury.sexy/hg_sdf/
float pModPolar(inout vec2 p, float repetitions) {
    float angle = 2. * PI / repetitions;
    float a = atan(p.y, p.x) + angle / 2.;
    float r = length(p);
    float c = floor(a / angle);
    a = mod(a, angle) - angle / 2.;
    p = vec2(cos(a), sin(a)) * r;
    // For an odd number of repetitions, fix cell index of the cell in -x
    // direction (cell index would be e.g. -5 and 5 in the two halves of the
    // cell):
    if (abs(c) >= (repetitions / 2.)) c = abs(c);
    return c;
}

float box(vec3 p, vec3 r) {
    vec3 d = abs(p) - r;
    return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

float smin(float a, float b, float k) {
    float h = clamp((a - b) / k * .5 + .5, 0.0, 1.0);
    return mix(a, b, h) - h * (1. - h) * k;
}

vec2 toPolar(vec2 p) { return vec2(length(p), atan(p.y, p.x)); }

vec2 fromPolar(vec2 p) { return vec2(cos(p.y) * p.x, sin(p.y) * p.x); }

float pMod(inout float p, float size) {
    float halfsize = size * 0.5;
    float c = floor((p + halfsize) / size);
    p = mod(p + halfsize, size) - halfsize;
    return c;
}

vec3 pMod3(inout vec3 p, vec3 size) {
	vec3 c = floor((p + size*0.5)/size);
	p = mod(p + size*0.5, size) - size*0.5;
	return c;
}

#define PHI 1.618033988749895
#define SQR2 1.4152135
#define ISQR2 1. / SQR2

// Million thanks to https://mercury.sexy/hg_sdf
const vec3 GDFVectors[19] =
    vec3[](normalize(vec3(1, 0, 0)), normalize(vec3(0, 1, 0)),
           normalize(vec3(0, 0, 1)),

           normalize(vec3(1, 1, 1)), normalize(vec3(-1, 1, 1)),
           normalize(vec3(1, -1, 1)), normalize(vec3(1, 1, -1)),

           normalize(vec3(0, 1, PHI + 1.)), normalize(vec3(0, -1, PHI + 1.)),
           normalize(vec3(PHI + 1., 0, 1)), normalize(vec3(-PHI - 1., 0, 1)),
           normalize(vec3(1, PHI + 1., 0)), normalize(vec3(-1, PHI + 1., 0)),

           normalize(vec3(0, PHI, 1)), normalize(vec3(0, -PHI, 1)),
           normalize(vec3(1, 0, PHI)), normalize(vec3(-1, 0, PHI)),
           normalize(vec3(PHI, 1, 0)), normalize(vec3(-PHI, 1, 0)));

float fGDF(vec3 p, float r, int begin, int end) {
    float d = 0.;
    for (int i = begin; i <= end; ++i) d = max(d, abs(dot(p, GDFVectors[i])));
    return d - r;
}

float dodecahedron(vec3 p, float r) { return fGDF(p, r, 13, 18); }

float icosahedron(vec3 p, float r) { return fGDF(p, r, 3, 12); }

float n21(vec2 p) {
    return fract(sin(dot(p, vec2(524.423, 123.34))) * 3228324.345);
}

float n11(float p) { return fract(sin(p) * 3228324.345); }

// smooth noise
float noise(vec2 n) {
    const vec2 d = vec2(0., 1.0);
    vec2 b = floor(n);
    vec2 f = mix(vec2(0.0), vec2(1.0), fract(n));
    return mix(mix(n21(b), n21(b + d.yx), f.x),
               mix(n21(b + d.xy), n21(b + d.yy), f.x), f.y);
}

// Repeat only a few times: from indices <start> to <stop> (similar to above,
// but more flexible)
float pModInterval1(inout float p, float size, float start, float stop) {
    float halfsize = size * 0.5;
    float c = floor((p + halfsize) / size);
    p = mod(p + halfsize, size) - halfsize;
    if (c > stop) {  // yes, this might not be the best thing numerically.
        p += size * (c - stop);
        c = stop;
    }
    if (c < start) {
        p += size * (c - start);
        c = start;
    }
    return c;
}

vec3 g_p;
vec3 transformDode(vec3 p) {
    // p.xz *= rot(.2*tt);
    // p.xy *= rot(.4*tt);
    return p;
}
vec3 opIcosahedralSymmetry(vec3 p) {
    // const float c = cos(PI/5.), s=sqrt(0.75-c*c);
    // cos(PI/5.) = 0.80901699437
    // const vec3 n = vec3(-0.5, -c, s);
    const vec3 n = vec3(-0.5, -0.809, 0.309);
    p = abs(p);
    for (int i = 0; i < 3; i++) {
        float side = dot(p, n);
        if (side > 0.0) break;
        p -= 2. * min(0., side) * n;
        if (i != 2) p.xy = abs(p.xy);
    }
    return p;
}

float smax(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0);
    return max(a, b) + h * h * 0.25 / k;
}

// adapted from https://www.shadertoy.com/view/Nsd3Wl
float sdDodecahedron(vec3 p, float s) {
    p /= s;
    p = opIcosahedralSymmetry(p);
    vec3 q = p - ICOMIDEDGE;         // move
    q.xz *= rot(DODEDIHEDRAL * .5);  // rotate
    // rounded edge
    vec3 vtx = vec3(-q.x, q.y - Y_TO_DODE_VERTEX, q.z);
    // onioning and rounding
    float dDode = abs(length(max(vtx, -.01)) + min(vtx.z, 0.) - .01) - .01;
    float dist = dDode;
    //   float dBalls = length(vtx-vec3(round(vtx.z*10.0)/20.0,0.0,0.1))-.01;
    //  float dCorners = length(p - ICOMIDFACE * 1.24)-.01;
    // dist = smin(dist,dBalls,.07);
    // Holes are centered on the dodecaheron's faces center
    vec2 pCenter = vec2(q.x - X_TO_DODE_CENTER, q.y);
    float dHole = length(pCenter) - .2;

    dist = smax(dist, -(dHole), .02);
    return dist * s;
}

float sdDodecahedronBig(vec3 p) {
    p = opIcosahedralSymmetry(p);
    vec3 q = p - ICOMIDEDGE;         // move
    q.xz *= rot(DODEDIHEDRAL * .5);  // rotate
    // rounded edge
    vec3 vtx = vec3(-q.x, q.y - Y_TO_DODE_VERTEX, q.z);
    // onioning and rounding
    float dDode = abs(length(max(vtx, -.02)) + min(vtx.z, 0.) - .01) - .025;
    float dist = dDode;
    float dBalls =
        length(vtx - vec3(round(vtx.z * 10.0) / 20.0, 0.0, 0.1)) - .03;
    float dCorners = length(p - ICOMIDFACE * 1.24) - .12;
    // dist = smin(dist,dBalls,.07);
    //  Holes are centered on the dodecaheron's faces center
    vec2 pCenter = vec2(q.x - X_TO_DODE_CENTER, q.y);
    float dHole = length(pCenter) - .2;

    dist = smax(dist, -(dHole), .011);
    return dist;
}

float sdIcosahedron(vec3 p, float s) {
    p /= s;
    p = opIcosahedralSymmetry(p);
    vec3 q = p - ICOMIDEDGE;        // move
    q.yz *= rot(ICODIHEDRAL * .5);  // rotates the coordinates to have XY plan
                                    // aligned with a ICO face's plan
    // rounded edge
    vec3 vtx = vec3(q.x - X_TO_ICO_VERTEX, -q.y, q.z);
    float dIco = abs(length(max(vtx, 0.05)) + min(vtx.z, 0.) - .10) - .01;
    // Circles are centered on the icosahedron's faces
    float dBigHole = abs(length(q.xy - vec2(0.0, Y_TO_ICO_CENTER)) - .2) - .05;
    // Smaller circles are centered somewhere between the middle of the face and
    // the vertex of the Ico
    float dSmallHole =
        abs(abs(length(q.xy - mix(vec2(0.0, Y_TO_ICO_CENTER),
                                  vec2(X_TO_ICO_VERTEX, 0.0), .60)) -
                .07) -
            .025) -
        .010;
    // little chains of spheres on the edges
    float dBalls = length(q - vec3(round(q.x * 20.0) / 20.0, 0.0, 0.1)) - .03;
    // Corners of the Ico
    q = p - ICOVERTEX * 1.3;         // move
    q.xz *= rot(DODEDIHEDRAL * .5);  // rotate
    float dCorners = length(q) - .04 * (1.0 + .5 * sin(q.z * 50.0));
    // combine
    float dist = dIco;
    float dCarvings = dBigHole;
    ;
    // dist += 0.008*smoothstep(0.01,-0.01,dCarvings);
    dist = smax(dist, -dCarvings, .02);
    // dist = smin(dist,dCorners-.13,.1);
    // dist = min(dist,dBalls);
    return dist * s;
}

vec2 foldSym(vec2 p, float N) {
    float t = atan(p.x, -p.y);
    t = mod(t + PI / N, 2.0 * PI / N) - PI / N;
    p = length(p.xy) * vec2(cos(t), sin(t));
    p = abs(p) - 0.25;
    p = abs(p) - 0.25;
    return p;
}

float sdIcosahedronBig(vec3 p) {
    p = opIcosahedralSymmetry(p);
    vec3 q = p - ICOMIDEDGE;        // move
    q.yz *= rot(ICODIHEDRAL * .5);  // rotates the coordinates to have XY plan
                                    // aligned with a ICO face's plan
    // rounded edge
    vec3 vtx = vec3(q.x - X_TO_ICO_VERTEX, -q.y, q.z);
    float dIco = abs(length(max(vtx, 0.04)) + min(vtx.z, 0.) - .10) - .03;
    // Circles are centered on the icosahedron's faces
    float dBigHole = length(q.xy - vec2(0.0, Y_TO_ICO_CENTER)) - .25;
    // Smaller circles are centered somewhere between the middle of the face and
    // the vertex of the Ico
    vec3 qb = q;
    q.xy -= mix(vec2(0.0, Y_TO_ICO_CENTER), vec2(X_TO_ICO_VERTEX, 0.0), .55);
    q.xy = toPolar(q.xy);
    q.x *= .5 * sin(q.y * .32);
    q.xy = fromPolar(q.xy);
    float dSmallHole = abs(abs(abs(length(q.xy) - .07) - .025) - .011) - 0.002;
    q = qb;
    // little chains of spheres on the edges
    float dBalls = length(q - vec3(round(q.x * 20.0) / 20.0, 0.0, 0.1)) - .03;
    // Corners of the Ico
    q = p - ICOVERTEX * 1.27;        // move
    q.xz *= rot(DODEDIHEDRAL * .5);  // rotate
    float dCorners = length(q) - .05;
    // combine
    float dist = dIco;
    float dCarvings = min(dBigHole, dSmallHole);
    // dist += 0.008*smoothstep(0.01,-0.01,dCarvings);
    // dist = smax(dist, -dBigHole, .02);
    dist = smax(dist, -dSmallHole, .004);

    dist = smin(dist, dCorners, .02);
    // dist = min(dist,dBalls);
    return dist;
}



#define SIN(x) (sin(x) * .5 + .5)

#define PI 3.141592
#define SIN(x) (sin(x) * .5 + .5)
#define PHI 1.618033988749895
#define SQR2 1.4152135
#define ISQR2 1. / SQR2

float octahedron( vec3 p, float s )
{
  p = abs(p);
  float edge = .05;
  float m = p.x+p.y+p.z-s;
  vec3 q;
       if( 3.0*p.x < m ) q = p.xyz;
  else if( 3.0*p.y < m ) q = p.yzx;
  else if( 3.0*p.z < m ) q = p.zxy;
  else return m*0.57735027 -edge;
    
  float k = clamp(0.5*(q.z-q.y+s),0.0,s); 
  return length(vec3(q.x,q.y-s+k,q.z-k)) - edge; 
}

float cube(vec3 p, float r) { return box(p, vec3(r)); }

float tetrahedron(vec3 p, float r) {
    // basically cutting a cube at the diagonal and scaling/centering it.
    p.yz *= rot(PI / 2.);

    p.z -= ISQR2 * r;
    vec3 bp = p;
    p.z *= 0.5;
    p.z -= ISQR2 * r;

    p.yz *= rot(atan(ISQR2) * PI * .5);
    p.xy *= rot(PI / 4.);

    return smax(cube(p, r) - .05, bp.z, .05) * .4;
}

float smoothrect(float x) {
    return smoothstep(0., .25, mod(x, 1.5)) *
           smoothstep(.25, 0., mod(x, 1.5) - .75);
}

vec3 kalei(vec3 p) {
    for (int i = 0; i < 4; i++) {
        p = abs(p) - .1;
        p.xy *= rot(TAU * 1. / 3.);
        p.yz *= rot(TAU * 1. / 16. + (tt - 7.5) * .2);
    }
    return p;
}

vec3 fold(vec3 p) {
    float c = cos(PI / 5.), s = sqrt(.75 - c * c);

    vec3 n = vec3(-.5, -c, s);

    p = abs(p);
    ;
    p -= 2. * min(0., dot(p, n)) * n;

    p.xy = abs(p.xy);
    p -= 2. * min(0., dot(p, n)) * n;

    p.xy = abs(p.xy);
    p -= 2. * min(0., dot(p, n)) * n;

    return p;
}

// capped cylinder
float cylc(vec3 p, float h, float r) {
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(h, r);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

void cam(inout vec3 p) {
   float _shake = .4*cam_shake*syn_OnBeat*syn_BassPresence;
    p.z -= (-cam_z + 20);
    
    vec2 _cam_xy =  cam_xy*rot(PI*rotate_amount);
    if(mandala > .5) {
        p.z -= 5*max(abs(_cam_xy.x), abs(_cam_xy.y)) + 2.;
    }
    

    p.yz *= rot(.5*PI*_cam_xy.y  + bang_cut);
    p.xz *= rot(PI*_cam_xy.x  + 2.*bang_cut);

    
    if(mandala > .5) {
        
        p.z += 3.*sin(PI*2.*syn_Beat8*auto_cam);
        
        p.xz *= rot(.33*PI*sin(PI*2.*syn_Beat16)*auto_cam);
        p.yz *= rot(.33*PI*sin(PI*2.*syn_Beat16)*auto_cam);
        p.xy += 5.*_shake;
     //   p.y += asin(sin(tt))*5.;
    
    } else {
        p.yz *= rot(_shake + .5*syn_BassTime*auto_cam + .5*tt);
        p.xz *= rot(1.5*rotate_speed + _shake + .5*syn_BassTime*auto_cam + bang_move);
    }
    
 
  //  p.xz *= rot(.6 * tt + .5 * PI);
  //  p.yz *= rot(.5 * PI + .5 * tt);
}
float g_glow;
float g_id;

float sdSnake(vec3 p, float len, float move, float size, int shape) {
    float s = .5;

    p /= s;

    p.xz *= rot(1. * tt);

    vec2 pp = toPolar(p.xz);

    pp.x += sin(pp.y);
    pp.y = abs(pp.y) - 2.6;

    float lId = pModInterval1(pp.y, .15, -len / 2., len / 2.);
    
    float cm = mix(5., .3 * SIN(lId / 4. + 4. * tt + TIME), move);

    p.xz = fromPolar(pp);
    p.x -= 15. + 1.5 * sin(2. * lId / len + 2. * tt);

    p.xy *= rot(0.4 * lId / len + tt);
    float ds = 1e6;
    
    if(shape == 0) {
        ds = box(p, vec3(2., 2., .5) * cm*particle_size) - size;
    } else {
        ds = length(p) - cm*particle_size*1.5 - size;
    }
    return ds * s;
}

float sdSnake(vec3 p) {
    return sdSnake(p, 50., 1., .4, 0);
}

float opErode(vec3 p, float d, float s) {
    if(erode_object > 0.01) {
        float d2 = 1e6;

        p = abs(p) - 1.;
        d2 = cube(p, s*mix(1., SIN(.4*syn_MidHighHits), beat_erode)*erode_object);
        d = abs(d+.05) -.05; // onion
        d = smax(d, -d2, .2);
    }
    
    return d;
}

float platonicMorph(vec3 p) {
    vec3 bp = p;

    bp.xy *= rot(tt * .75);
    bp.zy *= rot(tt * .5);

    p = bp;
    // p = fold(p);

    float iv = 0., d1 = 0., d2 = 0., it = 0., ts = 0.;

    float il = 1.5;

    ts = mod(tt, il * 5.);
    iv = floor(ts / il);
    it = mod(ts, il);

    float s = 1.5;

    if (iv < 1.) {
        d1 = tetrahedron(p, 1. * s);
        d2 = cube(p, 0.8 * s) - .05;
    } else if (iv < 2.) {
        d1 = cube(p, 0.8 * s) - 0.05;
        d2 = octahedron(p, 1.5 * s);
    } else if (iv < 3.) {
        d1 = octahedron(p, 1.5 * s);
        d2 = sdDodecahedron(p, 1. * s);
    } else if (iv < 4.) {
        d1 = sdDodecahedron(p, 1. * s);
        d2 = sdIcosahedron(p, 1.0 * s);
        ;
    } else {
        d1 = sdIcosahedron(p, 1.0 * s);
        ;
        // p = kalei(p);
        d2 = tetrahedron(p, 1. * s);
    }

    float d = mix(d1, d2, smoothstep(.5, 1., it));
    
    d = opErode(p, d, .5);
    
    return d*.8;
}

float sdPlanetRing(vec3 p) {
    float _planet_ring_size = 4.;

    p.xy *= rot(tt + .33 * PI + syn_BassTime*beat_rings);
    p.xz *= rot(.5 * tt + .33 * PI + .5*syn_MidHighTime*beat_rings);

    float d = 1e6;
    
    if(show_planet_rings > 0.) {
        d = sdSnake(p*_planet_ring_size, 50., 1., .3 + .2*syn_BassHits*beat_rings, 0)/_planet_ring_size;

        g_glow += 0.3 / (15. + pow(abs(d * 8.), 10.));
     
    }
    return d;
}

float explodingOrb(vec3 p, out float size) {
    float d = 1e6;
    p.xy *= rot(.5 * tt);

    p = fold(p);

    float sn =
        mix(1., 9., S(.0, 1., mix(SIN(tt), syn_BPMSin4, beat_explode)));
    float is_bang = float(bang_explode > 0.01);
    if(bang_explode > 0.01) {
        sn = mix(.2, 10., bang_explode);

    }
    size = sn;
    // float sn = mix(1., 10., SIN(tt));
    float ds = sdSnake(p * sn, 50., 1., mix(0.2*particle_size, .3, sn/10.), 1) / sn;
    d = smin(d, ds, .5);
    g_glow += mix(0.6, .8, is_bang) / (15. + pow(abs(ds * mix(6., 2., is_bang)), 10.));

    return d;
}

vec3 opFoldObject(vec3 p, float id) {

    float _fold_object = mix(fold_object, step(.5, syn_Beat8)*fold_object, beat_fold);
    
    p.xz *= rot(tt + id);
    p.yz *= rot(tt + id);
    
    p = mix(p, fold(p), _fold_object);
    
    if(_fold_object > 0.) {
        p.xz *= rot(tt + id);
        p.yz *= rot(tt + id);
    }
    return p;
}

float glowOrb(vec3 p) {
    if(glow_orb > 0.) { 
        float s = mix(.3, 1., syn_BassHits*beat_glow);
        s = mix(s*1.5, s*.5, float(object_circle > .5));
        
        float gl = .5;
        if(mandala > 0.) {
            s *= 1.5;
            gl = .8;
        }
        float d = length(p) - s;
        g_glow += gl/ (10. + pow(abs(d*2.), 10.));
    
        return d;
    }
    return 1e6;
}

float opSplit(inout vec3 p, vec3 bp, float s, inout float split_dist) {
    float _duplicate =  mix(duplicate, syn_ToggleOnBeat*syn_BassPresence*beat_duplicate*duplicate, beat_duplicate);
    
    if(_duplicate > 0.) {
        p.y = sabsk(p.y, .4) - mix(0., s, _duplicate);
    }
    
    float dup_rot =  smoothstep(0.4, .9, _duplicate);
    float lid = step(0., bp.y)*dup_rot;
    float lid2 = step(0., -bp.y)*dup_rot;
    
    split_dist = lid - lid2; 
  
    p.xz *= rot(.25 * PI * split_dist*(1.-mandala));
    
    return lid;
}

float opSplit(inout vec3 p, vec3 bp, float s) {
    float split_dist = 0.;
    return opSplit(p, bp, s, split_dist);
}

float showExplodingOrb(vec3 p, in float d) {
    if(exploding_orb > 0. || bang_explode > 0.01) {
        float orbSize = 0.;
        float ds = explodingOrb(p, orbSize);
      //  g_mat = ds < d ? 1. : g_mat;
         d = smin(d, ds, mix(1.3, 0., S(2., 3., orbSize)));
    }
    return d;
}

vec3 opTwist(vec3 p, float minSpeed) {
   p.xy *= rot(.9*sin(.5*p.z + tt + mix(minSpeed*TIME, syn_MidTime, beat_twist))*twist_object);
   return p;
}

float energyLines(vec3 p, bool cut) {
    vec3 bp = p;
    p.xz *= 1.-.5*SIN(p.y + 2.*tt + 4.*syn_BassTime*beat_glow);
    p.y += 2.*tt + syn_BassTime*beat_glow;

    float id = pMod(p.y, .52);

    p.y *= .5; // skew
    float d = length(p) - .15*particle_size;

    if(cut) {
       d = max(d, bp.y+.1);
    }

    g_glow += .50 / (15. + pow(abs(d * 8.), 10.));
    return d;
}

float map(vec3 p) {
 //   g_mat = 0.;
   // return cube(p, 2.);

    p.xz += .5*sin(.8*p.y + syn_MidTime*beat_wobble + tt)*wobble;
    
    p.yz += 1.5*sin(.4*p.x)*bang_wobble;
  
    float idz = 0.;
    g_mat = 0.;
    
    // save references
    vec3 bp = p;
    vec3 bp3 = p;
    
         //  p.xyz = sabsk(p.xyz, .4) -1.;
    if(mandala > 0.) {
        p.xy += sin(.4*p.z + syn_BassTime*beat_mandala +bang_wobble)*beat_mandala;
        idz = pModInterval1(p.z, 10., 0., 4.);
        p.xy *= rot(2.12*S(0.3, 1., asin(sin(tt + idz/5.))));
              
        p.xy = foldSym(p.xy, floor(mandala_folds));
        p.xz *= rot(rotate_speed*(object_circle));;
        p.xy *= rot(tt*(object_circle));
        p.yz *= rot(rotate_speed*(1-object_circle));
        
        bp3 = p;
    }
    
    if(object_circle < 1.) {
        float d = 1e6;
        float ds = 1e6;
        vec3 bp = p;
        
        if(mandala > .5) {
            p.x -= 5.;
        }
        float lid = opSplit(p, bp, 5.5);
        
        g_id = lid*.2;
        
        if(energy_lines > 0.) {
            ds = energyLines(p, true);
            g_mat =  ds < d ? 1. : g_mat;
            d = min(ds, d);
        }
        
        p = opFoldObject(p, 0.);
        p = opTwist(p, .2);
        
        ds = platonicMorph(p/1.5)*1.5;
        g_mat =  ds < d ? 0. : g_mat;
            
        d = smin(ds, d, .3);
        
        ds = glowOrb(p*2)/2;
        g_mat = ds < d ? 1. : g_mat;
        d = min(ds, d);
        d = showExplodingOrb(bp, d);
        
        ds = sdPlanetRing(bp/2.)*2.;
        g_mat = ds < d ? 1. : g_mat;
        d = min(ds, d);
        
        return d;
    }
 

    float split_dist = 0.;
    float lid = opSplit(p, bp, mandala > 0. ? 2.1 : 3., split_dist);
    
     //  p = fold(p);

    float id = pModPolar(p.xz, 5.) + 2.;
    
    g_id = id + idz*.1 + lid*.2*(1.-mandala);

    p.x -= 4.4 + .5 * SIN(tt) - SIN(tt+idz);

    vec3 bp2 = p;

    p = opFoldObject(p, id+idz/5.);

    p = opTwist(p, .4);
   //   p += .05*sin(20.*abs(p.x) +  syn_HighTime)*syn_HighHits;
    float s = 1.5;

    s = mix(1., mix(1.5, .3, SIN(id * 10. + 1. *syn_BassTime*beat_object_size)), beat_object_size);
    
  //  s = .3;
    float d1 = 1e6;
    if (id == 1.) {
        d1 = tetrahedron(p, 0.9*s);
    } else if (id == 2.) {
        d1 = (cube(p/s, 0.8) - 0.1)*s;
    } else if (id == 3.) {
        d1 = octahedron(p/s, 1.4)*s;
    } else if (id == 4.) {
        d1 = sdDodecahedron(p/s, 1.2)*s;
    } else {
        d1 = sdIcosahedron(p/s, 1.1)*s;
    }
    
    float d = opErode(p, d1, .6);
    d *= mix(.9, .5, beat_object_size);

    p = bp2;

    float ds = 1e6;
    
    if(energy_lines > 0.) {
        vec3 bp = p;
        
        bool energy_to_center = beat_toggle_lines > 0. ? syn_ToggleOnBeat > 0.5 : energy_pentagon < 0.5;
        
        float s = 1.5;
        p *= s;
        p.yz = p.zy;
        if(energy_to_center) { 
            p.xy = p.yx;
            p.yz *= rot(-.18*PI * abs(split_dist)); // rotate towards center when split
        }
        ds = energyLines(p, energy_to_center)/s;
        g_mat =  ds < d ? 1. : g_mat;
        
        d = min(ds, d);
        p = bp;
    }
    

    vec3 lp = p; // vector to object on circle
    

    d = showExplodingOrb(bp3, d);
    ds = sdPlanetRing(lp); 

    g_mat = ds < d ? 1. : g_mat;
    
    d = min(d, ds);
    

    ds = glowOrb(bp3);
    g_mat = ds < d ? 3. : g_mat;
    d = min(ds, d);
    

    return d;
}

vec3 getMediaEdge(vec2 uv) {
    vec3 edges = vec3(0);
    
    edges = _edgeDetectSobel(syn_Media, uv).rgb;
    float lum = _luminance(edges);
    lum = saturate(lum)*3.;
    
    return edges*lum;

}

vec3 tex3DEdge(in vec3 p, in vec3 n) {
    // return cellTileColor(p);

    n = max((abs(n) - 0.2) * 7., 0.001);  // n = max(abs(n), 0.001), etc.
    n /= (n.x + n.y + n.z);
    return (getMediaEdge(p.yz) * n.x + getMediaEdge(p.zx) * n.y +
            getMediaEdge(p.xy) * n.z)
        .xyz;
}


vec3 getNormal(vec3 p) {
    vec2 eps = vec2(0.001, 0.0);
    return normalize(vec3(map(p + eps.xyy) - map(p - eps.xyy),
                          map(p + eps.yxy) - map(p - eps.yxy),
                          map(p + eps.yyx) - map(p - eps.yyx)));
}

float gridSurf(in vec3 p) {
    p.z += .3 * tt;
    p = abs(mod(p * 2., 1. * 0.125) - 0.0125);

    float x = min(p.x, min(p.z, p.y)) / 0.03125;

    return clamp(x, 0., 1.);
}

// Standard function-based bump mapping function (from Shane)
vec3 doBumpMap(in vec3 p, in vec3 nor, float bumpfactor) {
    const float eps = BUMP_EPS;
    float ref = gridSurf(p);
    vec3 grad = vec3(gridSurf(vec3(p.x - eps, p.y, p.z)) - ref,
                     gridSurf(vec3(p.x, p.y - eps, p.z)) - ref,
                     gridSurf(vec3(p.x, p.y, p.z - eps)) - ref) /
                eps;

    grad -= nor * dot(nor, grad);

    return normalize(nor + bumpfactor * grad);
}

// iq's shadow function
float softshadow(in vec3 ro, in vec3 rd, float mint, float maxt, float k) {
    float res = 1.0;
    float ph = 1e6;
    for (float t = mint; t < maxt;) {
        float h = map(ro + rd * t);
        if (h < 0.001) return 0.0;
        float y = h * h / (2.0 * ph);
        float d = sqrt(h * h - y * y);
        res = min(res, k * d / max(0.0, t - y));
        ph = h;
        t += h;
    }
    return res;
}

// why not put the raymarcher in a separate function (;
vec3 raymarch(vec3 ro, vec3 rd, float steps) {
    float mat = 0., t = 0., d = 0.;
    vec3 p = ro;
    bool hit = false;
    for (float i = .0; i < steps; i++) {
        d = map(p);
        mat = g_mat;  // save global material

        t += d;
        p += rd * d;
        if (abs(d) < 0.001 || t > 50.) {
            break;
        }
    }

    // g_p = p;

    return vec3(t, mat, float(d < 0.001));
}

/*vec3 raymarch(vec3 ro, vec3 rd, float steps) {
    float t_min = 5.0;
    float t_max = 50.0;
    float mat = 0.;
    float iter = 0.;
    float d = 1e6;
    bool hit = false;
    vec3 p = vec3(0);
    float omega = 2.0;
    float stepLength = 0.0;
    float t = t_min;
	float candidate_error = 100.0;
	float candidate_t = t_min;
	float previousRadius = 0.0;
    
    float pixelRadius = 0.001;

    // naive raymarching on right half of the screen for comparison
  //  if (uv.x > 0.0)
    //    omega = 1.;
    //p = ro;
    for( int i= 0; i < steps; i ++) {
        p = ro + rd * t;
        
        d = map(p); 
        
        mat = g_mat;
  
        if (abs(d) < pixelRadius || t > t_max) {
            hit = true;
            break;
        }
        
        float radius = abs(d);
        
        bool sorFail = omega > 1.0 && (radius + previousRadius) < stepLength;
        
        if (sorFail) { 
            stepLength -= omega * stepLength;
            omega = 1.0;
            
		} else { 
            stepLength = d * omega;
        } 
        
        
        previousRadius = radius;
        float error = radius / t;

        
        if (!sorFail && error < candidate_error) {
            candidate_t = t;
			candidate_error = error;
		}

        t += stepLength;
        iter ++;
        
        if (!sorFail && error < pixelRadius || t > t_max) {
            if(error < pixelRadius) {
                hit = true;
            }
            break;
        }
        
    }
    
      return vec3(t, mat, float(hit));
}*/

// from iq code
float softshadow(in vec3 ro, in vec3 rd, in float mint, in float tmax) {
    float res = 1.0;
    float t = mint;
    for (int i = 0; i < 1; i++) {
        float h = map(ro + rd * t);
        res = min(res, 8.0 * h / t);
        t += h * .25;
        if (h < 0.001 || t > tmax) break;
    }
    return clamp(res, 0., 1.);
}

float calcAO(vec3 p, vec3 n) {
    float sca = 2.0, occ = 0.0;
    for (int i = 0; i < 5; i++) {
        float hr = 0.01 + float(i) * 0.5 / 4.0;
        float dd = map(n * hr + p);
        occ += (hr - dd) * sca;
        sca *= 0.7;
    }
    return clamp(1.0 - occ, 0.0, 1.0);
}

vec3 rdToCol(vec3 rd) {
    // Ray direction as color
    vec3 col = 0.5 + 0.5 * rd;

    // Output to cubemap

    col.g *= .7;
    return col;
}

vec3 getRayDir(vec2 uv, vec3 p, vec3 l, float z) {
    // camera system
    vec3 f = normalize(l - p),                   // forward vector
        r = normalize(cross(vec3(0, 1, 0), f)),  // right vector
        u = cross(f, r),                         // up vector
        c = p + f * z,                           // center of virtual screen
        i = c + uv.x * r + uv.y * u,             // intersection with screen
        rd = normalize(i - p);                   // ray direction

    return rd;
}

vec3 loadTexture(vec2 uv) {
    if(_isMediaActive()) {
        if(media_edge_glow > 0.) {
            return 1.-getMediaEdge(uv);
        }
        return _textureMedia(uv).rgb;
    } else if(texture_name < 1.) {
        return texture(texShipibo, uv).rgb;
    } else if(texture_name < 2.) {
        return texture(texIllusion, uv).rgb;
    } else if(texture_name < 3.) {
        return texture(texTribal, uv).rgb;
    } else if(texture_name < 4.) {
        return texture(texRetro, uv).rgb;
    } else if(texture_name < 5.) {
        return texture(texElegant, uv).rgb;
    } else if(texture_name < 6.) {
        return texture(texHexagons, uv).rgb;
    }
    return vec3(0);
}

// Shane awesome work below
// Tri-Planar blending function. Based on an old Nvidia tutorial.
vec3 tex3D(in vec3 p, in vec3 n) {
    // return cellTileColor(p);

    n = max((abs(n) - 0.2) * 7., 0.001);  // n = max(abs(n), 0.001), etc.
    n /= (n.x + n.y + n.z);
    return (loadTexture(p.yz) * n.x + loadTexture(p.zx) * n.y +
            loadTexture(p.xy) * n.z)
        .xyz;
}


// Texture bump mapping. Four tri-planar lookups, or 12 texture lookups in
// total. I tried to make it as concise as possible. Whether that translates to
// time, or not, I couldn't say.
vec3 texBump(in vec3 p, in vec3 n, float bf) {
    const vec2 e = vec2(0.002, 0);

    // Three gradient vectors rolled into a matrix, constructed with offset
    // greyscale texture values.
    mat3 m = mat3(tex3D(p - e.xyy, n), tex3D(p - e.yxy, n),
                  tex3D(p - e.yyx, n));

    vec3 coeffs = vec3(0.299 * SIN(tt), 0.587, 0.114 * SIN(.7 * tt));
    vec3 g = coeffs * m;  // Converting to greyscale.
    g = (g - dot(tex3D(p, n), coeffs)) / e.x;
    g -= n * dot(n, g);

    return normalize(n + g * bf);  // Bumped normal. "bf" - bump factor.
}

vec3 plasma_quintic( float x )
{
	x = clamp( x, 0.0, 1.0);
	vec4 x1 = vec4( 1.0, x, x * x, x * x * x ); // 1 x x2 x3
	vec4 x2 = x1 * x1.w * x; // x4 x5 x6 x7
	return vec3(
		dot( x1.xyzw, vec4( +0.063861086, +1.992659096, -1.023901152, -0.490832805 ) ) + dot( x2.xy, vec2( +1.308442123, -0.914547012 ) ),
		dot( x1.xyzw, vec4( +0.049718590, -0.791144343, +2.892305078, +0.811726816 ) ) + dot( x2.xy, vec2( -4.686502417, +2.717794514 ) ),
		dot( x1.xyzw, vec4( +0.513275779, +1.580255060, -5.164414457, +4.559573646 ) ) + dot( x2.xy, vec2( -1.916810682, +0.570638854 ) ) );
}

vec4 renderMainImage() {
    vec4 fragColor = vec4(0.0);
    vec2 fragCoord = _xy;

    vec2 uv = (fragCoord - .5 * RENDERSIZE.xy) / RENDERSIZE.y;

    uv *=  rot(PI*rotate_amount);
   // uv = uv.yx;
    //uv = foldSym(uv, 6.);
    tt = time + 0.*.25*syn_BassTime + 1.*bang_move + bang_cut;
    float zoom = 9.;  // mix(4., 9., SIN(.4*TIME));
    vec3 lp = vec3(5., 2., -7), lp2 = vec3(-4., 0., -8);

    
    g_mat = 0.;
    g_id = 0.;
    g_glow = 0.;
    // uv = uv.yx;
    vec3 col = vec3(0);
    
    float alpha = 1.;

    ro = vec3(0., 0.,  0.);
    float pivot_z = mandala > .5 ? 11. : 0.;
    vec3 lookat = vec3(0, 0, pivot_z), p;

    cam(ro);
    cam(lp);
    cam(lp2);

    // cam(lookat);

    // ro.yz *= rot(.3*tt);
    vec3 rd = getRayDir(uv, ro, lookat, 1.);

    float mat = 0., t = 0., d = 0.;

    vec2 e = vec2(0.0035, -0.0035);

    // background color
    vec3 c1 = vec3(0.106, 0.255, 0.275);
    vec3 c2 = vec3(0.165, 0.051, 0.286);

    // light color
    vec3 lc1 = vec3(0.745, 0.761, 0.976);
    vec3 lc2 = vec3(0.573, 0.922, 0.969);
    
    vec3 glow_col = vec3(0.741, 1.000, 0.996);

    // currently only one pass
    for (float i = 0.; i < 1.; i++) {
        float steps = 140.;
        vec3 rm = raymarch(ro, rd, steps);

        float glow = g_glow;
        float id = g_id;
        mat = rm.y;

        vec3 p = ro + rm.x * rd;

        vec3 p2 = p;

        // p = g_p;
        vec3 n = normalize(e.xyy * map(p + e.xyy) + e.yyx * map(p + e.yyx) +
                           e.yxy * map(p + e.yxy) + e.xxx * map(p + e.xxx));


        vec3 q = p * mix(.5, .05, texture_scale);
        if (mat == 3.) q *= .1;

        float bumpFade = texture_scale > 0. ? 1. : 0.;

        if(mat > 0.) bumpFade = 0.;
        vec3 bumpCol = tex3D(q, n)*bumpFade;
        vec3 texCol =  1. - bumpCol * .4 ;
        bumpCol = (1.-bumpCol);
        n = texBump(q, n, .005 * bumpFade);


        if (rm.z > 0.9) {
            vec3 l = normalize(lp - p);
            vec3 l2 = normalize(lp2 - p);
            float dif = max(dot(n, l), .0);
            float dif2 = max(dot(n, l2), .0);
            float spe = pow(max(dot(reflect(-rd, n), -l), .0), 40.);

            float shd = softshadow(p, l2 + l, 2., 5.);

            float sss = smoothstep(0., 1., map(p + l * .3)) / .4;
            float sss2 = smoothstep(0., 1., map(p + l2 * .3)) / .4;

            vec3 n2 = n;
            n2.xy += noise(p.xy) * .5 - .025;
            n2 = normalize(n2);
            float height = atan(n2.y, n2.x);

            vec3 iri = (spectral_zucconi6(height * 1.11) *
                           smoothstep(.8, .2, abs(n2.z)) -
                       .02)*mix(.5, 1., color_range);

            if (mat < 2.) {
                col += ((dif + .4 * sss) * lc1 + (.4 * sss2 + dif2) * lc2) +
                       .4 * iri;
            }

            float ao = calcAO(p, n);

            col *= ao;
            if (mat <= 3.) {
                rd = reflect(rd, n);
                rd.yz = rd.zy;

                vec3 refl = cubem(rd + vec3(0, .2, 0), .9);

                refl *= mix(vec3(1), spectral_zucconi6(n.x * n.y * 3.),
                            .4);  // reflect rainbows too
                col = mix(col, .6 * refl.rgb, .9);

                
                texCol *= mix(.2, 1., SIN(color_range*(p.z * 1.8 + p.y) + .5 * tt));


                vec3 gradient = getPal(
                    int(palette),
                    abs(smoothNoise21(p.xz * .2) *
                        1.5*color_range + color_offset +1.5 *time*auto_color*.3 +id*3.*alternate_color));
                        
             

                col = mix(col, 1.7 * mix(.7 * gradient, col * gradient, .3),
                          texCol.r);
                
                if(texture_scale > 0.01) {
                    
                
                vec3 gradient2 = getPal(
                    int(palette), abs(smoothNoise21(p.xz * 1.2) * 1.5*color_range + color_offset + .5 * time*auto_color*.3 + id*3.*alternate_color));      
                    col = mix(col, 2.2 * mix(.7 * gradient2, col * gradient2, .3),
                              bumpCol.r* mix(.9, mix(.2, 1., syn_BassHits), beat_glow));
                }
                         
         
                col += dif2 * .5 * iri + .2 * refl * iri;
                col = clamp(col, vec3(0), vec3(1));
                       
                t = rm.x;

                col = mix(col, col*(.5*(dif+dif2)), mix(.3, .8, float(texture_scale < 0.001)));
                
                if(texture_scale < 0.001) {
                   col *= .8 + sss2;
                  }
                float fog = 1. - exp(-t * t * 0.00008);

                col = mix(col, vec3(0), fog);

                col *= mix(1.4, .9, bumpFade);
           
                if(mat > 0.) {
                    col += col*2. + .2;
                    if(bang_explode > 0.) {
                        col *= 2.;
                    }
                }
                if(mat > 2.) {
                    col = glow_col;
                }
                    
            }
            
            col = mix(col * shd, col, 0.5);
            
            col *= mix(1, 1.2, beat_object_size);
            //#define DEBUG_PEFORMANCE 1
            #ifdef DEBUG_PEFORMANCE
            
            col = plasma_quintic(t/steps);
          
            #endif

        } else {
          // col = vec3(0);
           alpha = 0.;
        }

        float glow_amount = mix(.9, (.2 + .9 * syn_BassHits), beat_glow) * glow * glow_intensity * mix(3.,    2., mandala);
   
        col += glow_amount*glow_col;
        alpha += glow_amount;
        
        //  col += .2*g_glow2 *vec3(0.890,0.796,0.984); // outer
    }

    //col = pow(col * 1.1, vec3(1.8));
   // col = gamma(col);  // gamma
   
#ifdef DEBUG_PEFORMANCE
    if (uv.y < -0.45) {
        col = plasma_quintic(uv.x*.5+.5);
    }
#endif

    //  col = pow(cubem(rd2*3., 1.5), vec3(.8));

    fragColor = vec4(col, alpha);
    return fragColor;
}

vec4 renderMain() {
    if (PASSINDEX == 0) {
        vec4 col =renderMainImage();
  
        // feedback
        float _feedback = mix(.2, .98, mix(feedback,0.,_luminance(col.rgb)));
       
        if(feedback <= 0. || (reset_feedback > 0.0)) _feedback = 0.0;
        col = mix(col, texture(syn_FinalPass, (_uv-.5 +.001*sin(10.*_uv.yx+0.*syn_MidHighTime+.3*TIME))*(1.-.004*_feedback)+.5).rgba, _feedback);
        
        return col;

    }
}
