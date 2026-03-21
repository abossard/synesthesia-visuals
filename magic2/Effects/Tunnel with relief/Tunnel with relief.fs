/*{
	"CREDIT": "by You",
	"CATEGORIES": [
		"XXX"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "movementDepth",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 2.0
		},
		{
			"NAME": "fadeAmount",
			"TYPE": "float",
			"DEFAULT": 0.6,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "speedIn",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.1,
			"MAX": 5.0
		},
		{
			"NAME": "speedOut",
			"TYPE": "float",
			"DEFAULT": 1.0,
			"MIN": 0.1,
			"MAX": 5.0
		}
	],
	"DESCRIPTION" : "Automatically converted from https:\/\/www.shadertoy.com\/view\/4sXGRn by iq.  A 2D tunnel with fake relief"
}*/

void main() {
    vec2 p = (-RENDERSIZE.xy + 2.0 * gl_FragCoord.xy) / RENDERSIZE.y;
    p *= 0.75;
    
    float a = atan(p.y, p.x);
    float r = sqrt(dot(p, p));
    
    a += sin(movementDepth * r - movementDepth * TIME);
    
    float h = 0.5 + 0.5 * cos(9.0 * a);
    float s = smoothstep(0.4, 0.5, h);
    
    vec2 uv;
    uv.x = TIME * speedIn + 1.0 / (r * speedOut + 0.1 * s);
    uv.y = 3.0 * a / 3.1416;
    uv = mod(uv, 1.0);
    
    vec3 col = IMG_NORM_PIXEL(inputImage, uv).xyz;
    float ao = smoothstep(0.0, 0.3, h) - smoothstep(0.5, 1.0, h);
    
    col *= 1.0 - fadeAmount * ao * r;
    col *= r;
    
    gl_FragColor = vec4(col, 1.0);
}
