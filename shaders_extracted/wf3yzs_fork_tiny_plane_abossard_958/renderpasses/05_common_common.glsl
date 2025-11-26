const bool autoRotate = true;

const bool showBackground = true;
const bool showPlanet = true;
const bool showClouds = true;

const bool debugMaterials = false;
    
#define time (iTime)


///////////////////////////////////////////////////////////////////////////////////
// Morgan's standard Shadertoy helpers
#define Vector2      vec2
#define Point3       vec3
#define Vector3      vec3
#define Color3       vec3
#define Radiance3    vec3
#define Radiance4    vec4
#define Irradiance3  vec3
#define Power3       vec3
#define Biradiance3  vec3

const float pi          = 3.1415926535;
const float degrees     = pi / 180.0;
const float inf         = 1.0 / 1e-10;

float square(float x) { return x * x; }
float pow3(float x) { return x * square(x); }
float pow4(float x) { return square(square(x)); }
float pow8(float x) { return square(pow4(x)); }
float pow5(float x) { return x * square(square(x)); }
float infIfNegative(float x) { return (x >= 0.0) ? x : inf; }

struct Ray { Point3 origin; Vector3 direction; };	
struct Material { Color3 color; float metal; float smoothness; };
struct Surfel { Point3 position; Vector3 normal; Material material; };
struct Sphere { Point3 center; float radius; Material material; };
   
/** Analytic ray-sphere intersection. */
bool intersectSphere(Point3 C, float r, Ray R, inout float nearDistance, inout float farDistance) { Point3 P = R.origin; Vector3 w = R.direction; Vector3 v = P - C; float b = 2.0 * dot(w, v); float c = dot(v, v) - square(r); float d = square(b) - 4.0 * c; if (d < 0.0) { return false; } float dsqrt = sqrt(d); float t0 = infIfNegative((-b - dsqrt) * 0.5); float t1 = infIfNegative((-b + dsqrt) * 0.5); nearDistance = min(t0, t1); farDistance  = max(t0, t1); return (nearDistance < inf); }

///////////////////////////////////////////////////////////////////////////////////
// The following are from https://www.shadertoy.com/view/4dS3Wd
float hash(float p) { p = fract(p * 0.011); p *= p + 7.5; p *= p + p; return fract(p); }
float hash(vec2 p) {vec3 p3 = fract(vec3(p.xyx) * 0.13); p3 += dot(p3, p3.yzx + 3.333); return fract((p3.x + p3.y) * p3.z); }
float noise(float x) { float i = floor(x); float f = fract(x); float u = f * f * (3.0 - 2.0 * f); return mix(hash(i), hash(i + 1.0), u); }
float noise(vec2 x) { vec2 i = floor(x); vec2 f = fract(x); float a = hash(i); float b = hash(i + vec2(1.0, 0.0)); float c = hash(i + vec2(0.0, 1.0)); float d = hash(i + vec2(1.0, 1.0)); vec2 u = f * f * (3.0 - 2.0 * f); return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y; }
float noise(vec3 x) { const vec3 step = vec3(110, 241, 171); vec3 i = floor(x); vec3 f = fract(x); float n = dot(i, step); vec3 u = f * f * (3.0 - 2.0 * f); return mix(mix(mix( hash(n + dot(step, vec3(0, 0, 0))), hash(n + dot(step, vec3(1, 0, 0))), u.x), mix( hash(n + dot(step, vec3(0, 1, 0))), hash(n + dot(step, vec3(1, 1, 0))), u.x), u.y), mix(mix( hash(n + dot(step, vec3(0, 0, 1))), hash(n + dot(step, vec3(1, 0, 1))), u.x), mix( hash(n + dot(step, vec3(0, 1, 1))), hash(n + dot(step, vec3(1, 1, 1))), u.x), u.y), u.z); }

#define DEFINE_FBM(name, OCTAVES) float name(vec3 x) { float v = 0.0; float a = 0.5; vec3 shift = vec3(100); for (int i = 0; i < OCTAVES; ++i) { v += a * noise(x); x = x * 2.0 + shift; a *= 0.5; } return v; }
DEFINE_FBM(fbm3, 3)
DEFINE_FBM(fbm5, 5)
DEFINE_FBM(fbm6, 6)
    
///////////////////////////////////////////////////////////////////////////////////

const float       verticalFieldOfView = 25.0 * degrees;

// Directional light source
const Vector3     w_i             = Vector3(1.0, 1.3, 0.6) / 1.7464;
const Biradiance3 B_i             = Biradiance3(2.9);

const Point3      planetCenter    = Point3(0);

// Including clouds
const float       planetMaxRadius = 1.0;

const float       cloudMinRadius  = 0.85;

const Radiance3   atmosphereColor = Color3(0.3, 0.6, 1.0) * 1.6;


// This can g1 negative in order to make derivatives smooth. Always
// clamp before using as a density. Must be kept in sync with Buf A code.
float cloudDensity(Point3 X, float t) {
    Point3 p = X * vec3(1.5, 2.5, 2.0);
	return fbm5(p + 1.5 * fbm3(p - t * 0.047) - t * vec3(0.03, 0.01, 0.01)) - 0.42;
}

Color3 shadowedAtmosphereColor(vec2 fragCoord, vec3 iResolution, float minVal) {
    vec2 rel = 0.65 * (fragCoord.xy - iResolution.xy * 0.5) / iResolution.y;
    const float maxVal = 1.0;
    
    float a = min(1.0,
                  pow(max(0.0, 1.0 - dot(rel, rel) * 6.5), 2.4) + 
                  max(abs(rel.x - rel.y) - 0.35, 0.0) * 12.0 +                   
	              max(0.0, 0.2 + dot(rel, vec2(2.75))) + 
                  0.0
                 );
    
    float planetShadow = mix(minVal, maxVal, a);
    
    return atmosphereColor * planetShadow;

}

