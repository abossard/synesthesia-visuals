/*{
  "DESCRIPTION": "Your shader description",
  "CREDIT": "by you",
  "CATEGORIES": [
    "Sharpen And Blur"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "amount",
      "TYPE": "float",
      "DEFAULT": 0.5,
      "MIN": 0,
      "MAX": 1
    },
    {
      "NAME": "radius",
      "TYPE": "float",
      "DEFAULT": 0.4,
      "MIN": 0,
      "MAX": 1
    },
    {
      "NAME": "JITTER",
      "TYPE": "bool",
      "DEFAULT": 1
    }
  ]
}*/


// Based on "lens: bokeh blur, circular 3pass"
// by hornet: https://www.shadertoy.com/view/Xd33Dl


const vec2 blurdir = vec2( 1.0, 0.0 );

const int NUM_SAMPLES = 1;

vec3 srgb2lin(vec3 c) { return c*c; }
vec3 lin2srgb(vec3 c) { return sqrt(c); }

//note: uniform pdf rand [0;1]

float hash12n(vec2 p)
{
	p  = fract(p * vec2(5.3987, 5.4421));
    p += dot(p.yx, p.xy + vec2(21.5351, 14.3137));
	return fract(p.x * p.y * 95.4307);
}

void main() {
    float blurdist_px = float(RENDERSIZE.x*radius);

    vec2 suv = gl_FragCoord.xy / RENDERSIZE.xy; 
    vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
    
    float blur = 3. * amount * blurdist_px;
    blur *= .1; //empiric constant...
    
    float da = 6.283;
    float a = 1.0;
    
    if (JITTER) { a = da * hash12n(uv+(TIME)); }
    else { a = da * hash12n(uv); }
    
    vec3 sumcol = vec3(0.0);
 
    for (int i=0;i<10;++i)
    	{
        vec2 ofs = vec2( cos(a), sin(a) ) / RENDERSIZE.xy * blur*float(i+1)*.31;
    	vec2 p = uv+(ofs/10.);
       	sumcol = sumcol+srgb2lin(IMG_NORM_PIXEL(inputImage, p).rgb);
        a += da;
    }
    
    sumcol = sumcol / 10.;
    sumcol = max( sumcol, 0.0 );

    
    
  gl_FragColor = vec4(lin2srgb( sumcol ), 1.0);
}