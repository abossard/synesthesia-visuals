
/*{
	"DESCRIPTION": "infinite zoom",
	"CREDIT": "",
	"ISFVSN": "2",
	"CATEGORIES": [
		"Tile Effect"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "t",
			"TYPE": "float",
			"DEFAULT": 0.0,
			"MIN": 0.0,
			"MAX": 10.0
		},
		{
			"NAME": "speed",
			"TYPE": "float",
			"DEFAULT": 0.1,
			"MIN": -1.0,
			"MAX": 1.0
		},
		{
			"NAME": "Wsource",
			"TYPE": "float",
			"DEFAULT": 5184,
			"MIN": 0.0,
			"MAX": 10000.0
		},
		{
			"NAME": "Hsource",
			"TYPE": "float",
			"DEFAULT": 3456,
			"MIN": 0.0,
			"MAX": 10000.0
		},
		{
			"NAME": "flipH",
			"TYPE": "bool",
			"DEFAULT": 1.0
		},
		{
			"NAME": "flipW",
			"TYPE": "bool",
			"DEFAULT": 1.0
		}
	],
	"PASSES": [
		{
			"TARGET":"bufferVariableNameA",
			"WIDTH": "$WIDTH/16.0",
			"HEIGHT": "$HEIGHT/16.0"
		},
		{
			"DESCRIPTION": "this empty pass is rendered at the same rez as whatever you are running the ISF filter at- the previous step rendered an image at one-sixteenth the res, so this step ensures that the output is full-size"
		}
	]
	
}*/

vec2 pix2quilt(vec2 p) {
    float W = Hsource;
    float H = Wsource;
    
    float x0 = 0.5;
    float y0 = 0.5;
    float pi = 3.14159265359;
    float Rmax = sqrt(x0*x0+y0*y0);
    float Rmin = 1. / (W*W+H*H);
    float alpha = log(Rmin/Rmax);
    
    float r = sqrt(pow(p[0]-x0, 2.) + pow(p[1]-y0, 2.));
    r = clamp(r, Rmin, Rmax);
    
    float theta = atan(p[1] - y0, p[0] - x0);
    float x = (pi - theta) / (2. * pi);
    float y = -log(r / Rmax) / alpha;
    
    return vec2(x, y);
}

void main()	{
	vec2 pos = pix2quilt(isf_FragNormCoord);
	float offset = 0.5 * speed * (TIME + 0.1 * t);
	
	//vec2(pos[0], mod(pos[1] - offset, 1.));
	float x;
	float y;
	float y_offset;
	x = (flipW)?(1.-pos[0]):pos[0];
	y = (flipH)?(1.-pos[1]):pos[1];
	//x = pos[0];
	//y = pos[1];
	vec2 pos_offset = vec2(x, mod(y - offset, 1.));
	vec4 sampled = IMG_NORM_PIXEL(inputImage, pos_offset);
	
	gl_FragColor = sampled;
}
