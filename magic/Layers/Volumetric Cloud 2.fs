/*{
    "DESCRIPTION": "Texture 3d displacement",
    "CREDIT": "Rhythmic Visions",
    "ISFVSN": "2",
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "grow",
            "TYPE": "float",
            "DEFAULT": 8.5,
            "MIN": 0.001,
            "MAX": 10.0
        },
        {
            "NAME": "density",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.001,
            "MAX": 1.0
        },
        {
            "NAME": "density2",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.001,
            "MAX": 1.0
        },
        {
            "NAME": "rotation",
            "TYPE": "float",
            "DEFAULT": 1.8,
            "MIN": 0.0,
            "MAX": 2.5
        },
        {
            "NAME": "zoom",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.25,
            "MAX": 1.5
        },
        {
            "NAME": "mod1",
            "TYPE": "float",
            "DEFAULT": 1.3,
            "MIN": 0.25,
            "MAX": 1.5
        },
        {
            "NAME": "mod2",
            "TYPE": "float",
            "DEFAULT": 0.77,
            "MIN": 0.25,
            "MAX": 1.5
        },
        {
            "NAME": "mod3",
            "TYPE": "float",
            "DEFAULT": 0.47,
            "MIN": 0.0,
            "MAX": 1.8
        },
        {
            "NAME": "light",
            "TYPE": "float",
            "DEFAULT": 0.18,
            "MIN": 0.1,
            "MAX": 1.0
        },
        {
            "NAME": "lighteffect",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.1,
            "MAX": 1.0
        }
        
    ]
}*/


#ifdef GL_ES
precision mediump float;
#endif


// Port of "Growing Paint" by olav
// Port of "Volumetric cloud" by Duke
// https://www.shadertoy.com/view/4ldGRf
//-------------------------------------------------------------------------------------
// Based on "Above the clouds" (https://www.shadertoy.com/view/ll2SWd)
// "Volumetric explosion" (https://www.shadertoy.com/view/lsySzd)
// and other previous shaders.
// Also was useful
// otaviogood's "Alien Beacon" (https://www.shadertoy.com/view/ld2SzK)
// and IQ's "Clouds" (https://www.shadertoy.com/view/XslGRr) shaders
// Some ideas came from other shaders from this wonderful site
// Press 1-2-3 to zoom in and zoom out.
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
//-------------------------------------------------------------------------------------

// Comment this string to see another type of clouds
#define TWISTED
// Comment this string to make cloud less dense
//#define DITHERING

#define pi 3.14159265
#define R(p, a) p=cos(a)*p+sin(a)*vec2(p.y, -p.x)

vec3 hash(vec3 p) {
    return fract(sin(p * vec3(127.1, 311.7, 74.7)) * 43758.5453123);
}

float noise( in vec3 p )
{
    vec3 i = floor( p );
    vec3 f = fract( p );
	
    vec3 u = f*f*(3.0-2.0*f);
	
    return 1. - .9 * mix( mix( mix( dot( hash( i + vec3(0.0,0.0,0.0) ), f - vec3(0.0,0.0,0.0) ), 
                          dot( hash( i + vec3(1.0,0.0,0.0) ), f - vec3(1.0,0.0,0.0) ), u.x),
                     mix( dot( hash( i + vec3(0.0,1.0,0.0) ), f - vec3(0.0,1.0,0.0) ), 
                          dot( hash( i + vec3(1.0,1.0,0.0) ), f - vec3(1.0,1.0,0.0) ), u.x), u.y),
                mix( mix( dot( hash( i + vec3(0.0,0.0,1.0) ), f - vec3(0.0,0.0,1.0) ), 
                          dot( hash( i + vec3(1.0,0.0,1.0) ), f - vec3(1.0,0.0,1.0) ), u.x),
                     mix( dot( hash( i + vec3(0.0,1.0,1.0) ), f - vec3(0.0,1.0,1.0) ), 
                          dot( hash( i + vec3(1.0,1.0,1.0) ), f - vec3(1.0,1.0,1.0) ), u.x), u.y), u.z );
}

float fbm(vec3 p) {
    return noise(p * 0.0625) * 0.75 + noise(p * 0.125) * 0.325 + noise(p * 0.4) * 0.2;
}

// implementation found at: lumina.sourceforge.net/Tutorials/Noise.html
float rand(vec2 co)
{
    return fract(sin(dot(co*0.123,vec2(12.9898,78.233))) * 43758.5453);
}

float Sphere( vec3 p, float r )
{
    return length(p)-r;
}

//==============================================================
// otaviogood's noise from https://www.shadertoy.com/view/ld2SzK
//--------------------------------------------------------------
// This spiral noise works by successively adding and rotating sin waves while increasing frequency.
// It should work the same on all computers since it's not based on a hash function like some other noises.
// It can be much faster than other noise functions if you're ok with some repetition.
const float nudge = 2.;	// size of perpendicular vector
float normalizer = 1.0 / sqrt(1.0 + nudge*nudge);	// pythagorean theorem on that perpendicular to maintain scale
float SpiralNoiseC(vec3 p)
{
    float n = -mod(grow * 0.2,-2.); // noise amount
    float iter = 2.0;
    for (int i = 0; i < 8; i++)
    {
        // add sin and cos scaled inverse with the frequency
        n += -abs(sin(p.y*iter) + cos(p.x*iter)) / iter;	// abs for a ridged look
        // rotate by adding perpendicular and scaling down
        p.xy += vec2(p.y, -p.x) * mod3;
        p.xy *= normalizer;
        // rotate on other axis
        p.xz += vec2(p.z, -p.x) * mod3;
        p.xz *= normalizer;
        // increase the frequency
        iter *= 1.733733;
    }
    return n;
}

float VolumetricCloud(vec3 p)
{
    float final = Sphere(p,4.);
    float tnoise = noise(p*0.5) * density;
    final += SpiralNoiseC(p.zxy*0.4132*tnoise+333.)*3.25 * density2;
    return final;
}

float map(vec3 p) 
{
   float VolCloud = VolumetricCloud(p/0.5)*0.5; // scale
   return VolCloud;
}

bool RaySphereIntersect(vec3 org, vec3 dir, out float near, out float far) {
    float b = dot(dir, org);
    float c = dot(org, org) - 26.0;
    float delta = b * b - c;

    if (delta < 0.0) return false;

    float deltasqrt = sqrt(delta);
    near = -b - deltasqrt;
    far = -b + deltasqrt;
    return far > 0.0;
}

// Utility function that maps a value from one range to another.
float Remap(float original_value, float original_min, float original_max, float new_min, float new_max)
{
   return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
}

vec3 rotate(vec3 vec, vec3 axis, float ang)
{
    return vec * cos(ang) + cross(axis, vec) * sin(ang) + axis * dot(axis, vec) * (1.0 - cos(ang));
}


vec3 pin(vec3 v)
{
    return rotate(vec3(sin((v.x+v.y)*3.),cos((v.y+v.z)*3.+1.04719),sin((v.z+v.x)*3.+4.18879))*0.5+0.5,(v),cos((v.x+v.y+v.z)+length(v)));
}

//https://iquilezles.org/articles/palettes/
vec3 palette( float t ) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.263,0.416,0.557);

    return 0.15 + a + b*cos( 6.28318*(c*t+d) );
}

void main(void) {
    vec3 rd = normalize(vec3((gl_FragCoord.xy - 0.5 * RENDERSIZE.xy) / (RENDERSIZE.y * zoom), 1.0));
    vec3 ro = vec3(0.0, 0.0, -10.0);

    // Apply rotations only to the objects, not the entire scene
    vec3 sundir = normalize(vec3(0.0, 0.0, 1.0)); // Sun remains static

    const float h = 0.325;
    vec4 sum = vec4(0.0);

    float t = 0.0, td = 0.0, ld = 0.0, d = 1.0;
    float min_dist = 0.0, max_dist = 0.0;

    if (RaySphereIntersect(ro, rd, min_dist, max_dist)) {
        t = max(t, min_dist);

        for (int i = 0; i < 52; ++i) {
            vec3 pos = ro + t * rd;

            // Rotate the object space only
            R(pos.yz, -pi * 3.93);
            R(pos.xz, rotation * 0.8 * pi);

            // Exit conditions
            if (td > 0.9875 || d < 0.0006 * t || t > 12.0 || t > max_dist || sum.a > 0.99) break;

            d = map(pos);
            float d_remaped = Remap(max(d, -2.0), -2.0, h, h, 1.0);

            if (d < h) {
                ld = h - (1.0 - d_remaped);
                float fld = clamp((ld - (h - max(map(pos + 0.1 * sundir * lighteffect), 0.0))) / 1.3, 0.0, 1.0);

                float lightPos = mod1 - fld * 2. * mod2;
                vec4 col = vec4(palette(lightPos), exp(-d_remaped));
                col.a *= light * 2.;
                col.rgb *= col.a;
                sum += col * (1.0 - sum.a);
            }

            d = max(d, 0.1);
            t += max(d * 0.1, 0.01); // Finer step size

        }
        sum = clamp(sum, 0.0, 1.0);
    }
float vibrancy = (1.0 - light) * 0.05;
float contrast = 0.5 + (1.0 - light) * 0.1;
    sum.xyz *= 1.0 / exp(ld * 0.05) * 0.85;
    sum.xyz = sum.xyz * sum.xyz * (3.0 - 2.0 * clamp(sum.xyz, 0.0, 1.0));
    sum -= (max(sum.r, max(sum.g, sum.b)) - sum) * ((max(sum.r, max(sum.g, sum.b)) - (sum.r + sum.g + sum.b) / 3.) * vibrancy * 15.);
	sum.rgb = ((vec3(2.0) * (sum.rgb - vec3(0.5))) * vec3(contrast * 2.) / vec3(2.0)) + vec3(0.5);

    gl_FragColor = vec4(sum.xyz, 1.0);
}

