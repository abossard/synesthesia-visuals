// COMMON

// https://www.shadertoy.com/view/t3l3R7 a pixel fluid cellular automaton, 2025 by jt 
// diffusion: https://www.shadertoy.com/view/W3l3R4 integer average conserving total (jt)
// gradient: https://www.shadertoy.com/view/tfjSWc pixel fluid gravitation rnd swap (jt)

// A cellular automaton that simulates a compressible
// pixel fluid inside an arbitrary container.
// Simulation consists of two main passes:
// (1) averaging mass while keeping total mass constant
// (2) enforcing a vertical pressure gradient

// Press SPACE to reset.
// Click mouse to add water.

// Feel free to use this in your games/simulations as long as this shader is credited.
// Looking forward to see wonderful pixel worlds :D

// tags: pixel, sandbox, diffusion, cellular, ca, automaton, boundary, conditions, gravity, fluid, communicating, vessels, compressible

// The MIT License
// Copyright (c) 2025 Jakob Thomsen
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


#define SCALE 5

vec2 grad( ivec2 z ) // Perlin noise by inigo quilez - iq/2013   https://www.shadertoy.com/view/XdXGW8
{
    // 2D to 1D  (feel free to replace by some other)
    int n = z.x+z.y*11111;

    // Hugo Elias hash (feel free to replace by another one)
    n = (n<<13)^n;
    n = (n*(n*n*15731+789221)+1376312589)>>16;

#if 0

    // simple random vectors
    return vec2(cos(float(n)),sin(float(n)));
    
#else

    // Perlin style vectors
    n &= 7;
    vec2 gr = vec2(n&1,n>>1)*2.0-1.0;
    return ( n>=6 ) ? vec2(0.0,gr.x) : 
           ( n>=4 ) ? vec2(gr.x,0.0) :
                              gr;
#endif                              
}

float noise( in vec2 p ) // Perlin noise by inigo quilez - iq/2013   https://www.shadertoy.com/view/XdXGW8
{
    ivec2 i = ivec2(floor( p ));
     vec2 f =       fract( p );
	
	vec2 u = f*f*(3.0-2.0*f); // feel free to replace by a quintic smoothstep instead

    return mix( mix( dot( grad( i+ivec2(0,0) ), f-vec2(0.0,0.0) ), 
                     dot( grad( i+ivec2(1,0) ), f-vec2(1.0,0.0) ), u.x),
                mix( dot( grad( i+ivec2(0,1) ), f-vec2(0.0,1.0) ), 
                     dot( grad( i+ivec2(1,1) ), f-vec2(1.0,1.0) ), u.x), u.y);
}

// https://www.shadertoy.com/view/WttXWX "Best" Integer Hash by FabriceNeyret2,
// implementing Chris Wellons https://nullprogram.com/blog/2018/07/31/
uint triple32(uint x)
{
    x ^= x >> 17u;
    x *= 0xed5ad4bbu;
    x ^= x >> 11u;
    x *= 0xac4c1b51u;
    x ^= x >> 15u;
    x *= 0x31848babu;
    x ^= x >> 14u;
    return x;
}

#define HASH(u) triple32(u)

uint uhash(uvec2 v)
{
    return HASH(v.x + HASH(v.y));
}

float hash(vec2 v)
{
    return float(uhash(uvec2(v)))/float(0xffffffffU);
}

float hash12(vec2 p) // https://www.shadertoy.com/view/4djSRW Hash without Sine by Dave_Hoskins
{
	vec3 p3  = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float fbm(vec2 x, float H, int N) // https://iquilezles.org/articles/fbm/
{    
    float G = exp2(-H);
    float f = 1.0;
    float a = 1.0;
    float t = 0.0;
    for( int i=0; i<N; i++ )
    {
        //t += a*hash12(f*x);
        t += a*hash(f*x);
        f *= 2.0;
        a *= G;
    }
    return t;
}

// https://www.shadertoy.com/view/DtjyWD integer division - rounding down
ivec2 div_floor(ivec2 a, ivec2 b) // vector version thanks to Fabrice
{
    ivec2  S = (sign(abs(a*b))-sign(a*b))/2; // 0 if a*b >= 0
    return S * ((1 - abs(a)) / abs(b) - 1)+(1-S)*(a / b); // emulates ()?:
}

// this implementation replaces operator % which is buggy (for negative numbers) on windows
ivec2 mod_positive(ivec2 a, ivec2 b) // https://www.shadertoy.com/view/DtjyWD integer modulo strictly positive
{
    return a - div_floor(a, b) * b;
}

vec4 get(sampler2D s, ivec2 v)
{
    //return texelFetch(iChannel0, mod_positive(v, textureSize(iChannel0, 0)), 0);
    return texelFetch(s, v, 0);
}

bool get_w(sampler2D s, ivec2 v)
{
    return get(s, v).w >= 0.5;
}

int decode(vec4 v)
{
    return int(v.z*255.0);
}

vec4 encode(int i)
{
    return vec4(0,0,float(i) / 255.0,0);
}

vec4 hstep(sampler2D s, ivec2 v) // https://www.shadertoy.com/view/tcjXzz cellular automaton heat equation (jt)
{
    vec4 left_raw   = get(s, v+ivec2(-1,0));
    vec4 center_raw = get(s, v+ivec2( 0,0));
    vec4 right_raw  = get(s, v+ivec2(+1,0));
    
    bool left_wall   = left_raw.w > 0.5;
    bool center_wall = center_raw.w > 0.5;
    bool right_wall  = right_raw.w > 0.5;

    int left_value   = decode(left_raw);
    int center_value = decode(center_raw);
    int right_value  = decode(right_raw);

    bool left_parity   = (left_value&1)!=0;
    bool center_parity = (center_value&1)!=0;
    bool right_parity  = (right_value&1)!=0;
    
    // NOTE: subtracting parity bit ensures following division by two is lossless
    int left_half   = (left_value-int(left_parity))>>1;
    int center_half = (center_value-int(center_parity))>>1;
    int right_half  = (right_value-int(right_parity))>>1;

    if(center_wall)
    {
        // center position solid: keep as is
        return center_raw;
    }

    int result = int(center_parity); // preserve even/odd (which otherwise disappears by average)

    // NOTE: adding and duplicating is lossless
    if(left_wall)
    {
        if(right_wall)
        {
            // both left solid and right solid: keep previous value
            result += 2*center_half;
        }
        else
        {
            // left solid but right free: average center with right
            result += center_half + right_half;
        }
    }
    else
    {
        if(right_wall)
        {
            // left free and right solid: average center with left
            result += center_half + left_half;
        }
        else
        {
            // both left free and right free: average left with right
            result += left_half + right_half;
        }
    }

    return encode(result);
}

vec4 vstep(sampler2D s, ivec2 v) // https://www.shadertoy.com/view/tcjXzz cellular automaton heat equation (jt)
{
    vec4 down_raw   = get(s, v+ivec2(0,-1));
    vec4 center_raw = get(s, v+ivec2(0, 0));
    vec4 up_raw     = get(s, v+ivec2(0,+1));
    
    bool down_wall   = down_raw.w > 0.5;
    bool center_wall = center_raw.w > 0.5;
    bool up_wall     = up_raw.w > 0.5;

    int down_value   = decode(down_raw);
    int center_value = decode(center_raw);
    int up_value     = decode(up_raw);

    bool down_parity   = (down_value&1)!=0;
    bool center_parity = (center_value&1)!=0;
    bool up_parity     = (up_value&1)!=0;
    
    // NOTE: subtracting parity bit ensures following division by two is lossless
    int down_half   = (down_value-int(down_parity))>>1;
    int center_half = (center_value-int(center_parity))>>1;
    int up_half     = (up_value-int(up_parity))>>1;

    if(center_wall)
    {
        // center position solid: keep as is
        return center_raw;
    }

    int result = int(center_parity); // preserve even/odd (which otherwise disappears by average)


    // NOTE: adding and duplicating is lossless
    if(down_wall)
    {
        if(up_wall)
        {
            // both down solid and up solid: keep previous value
            result += 2*center_half;
        }
        else
        {
            // down solid but up free: average center with up
            result += center_half + up_half;
        }
    }
    else
    {
        if(up_wall)
        {
            // down free and up solid: average center with up
            result += center_half + down_half;
        }
        else
        {
            // both down free and up free: average down with up
            result += down_half + up_half;
        }
    }
    
    return encode(result);
}

vec4 sim(sampler2D s, ivec2 p, bool flip) // https://www.shadertoy.com/view/tfjSWc pixel fluid gravitation rnd swap (jt)
{
    ivec2 q = p;
    q.y = ((q.y + int(flip)) ^ 1) - int(flip); // flip even-odd

    vec4 a = get(s, p);
    vec4 b = get(s, q);
    if(a.w > 0.5 || b.w > 0.5)
        return a; // position in a wall: keep as is

    int A = decode(a);
    int B = decode(b);
    return
        ((p.y & 1) == int(flip))
        ?
        encode(A + (B > 0 && A < 255 ? 1 : 0))
        :
        encode(A - (A > 0 && B < 255 ? 1 : 0));
}

