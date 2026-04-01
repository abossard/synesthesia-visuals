/*{
  "CREDIT": "by INKA",
  "CATEGORIES": [
    "Stylize",
    "INKA"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "intensity",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 100,
      "DEFAULT": 30
    },
    {
      "NAME": "size",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 0.5,
      "DEFAULT": 0.3
    },
    {
      "NAME": "speed",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 16,
      "DEFAULT":1
    },
    {
      "NAME": "colorize",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 1
    },
    {
      "NAME": "fade",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 0.05,
      "DEFAULT": 0.05
    },
    {
      "NAME": "manual",
      "TYPE": "bool",
      "DEFAULT": false
    },
    {
      "NAME": "manualPosition",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 1
    }
  ],
  "PASSES": [
    {
      "TARGET" : "BufferA",
      "PERSISTENT" : true
    },
    {}
  ]
}*/

/*
	TRACE EDGES
	-----------
	This is a work in progress of 
	my beloved effect "tracer.qtz" 
	but as a shader
	
*/

varying vec2 left_coord;
varying vec2 right_coord;
varying vec2 above_coord;
varying vec2 below_coord;

varying vec2 lefta_coord;
varying vec2 righta_coord;
varying vec2 leftb_coord;
varying vec2 rightb_coord;

const vec4 redfilter1 		= vec4(1.0, 0.01, 0.0, 1.0);
const vec4 bluegreenfilter1 	= vec4(0.0, 1.0, 0.7, 1.0);



float gray(vec4 n)
{
	return (n.r + n.g + n.b)/3.0;
}


void main()
{
     if (PASSINDEX == 0) {
	//	do this junk so that the ripple starts from nothing
	vec2 uv = isf_FragNormCoord.xy;
	vec2 texCoord = uv;
	vec2 mod_center = vec2(0.5);//center / RENDERSIZE;
	vec4 color = IMG_PIXEL(inputImage, gl_FragCoord.xy);
	vec4 stalePixel = IMG_PIXEL(BufferA, gl_FragCoord.xy);

	float dist = distance(uv, mod_center);
	
	float curPos = manual ? manualPosition : TIME*speed;
		
	float pos = size / 2. + abs(sin(curPos)) * 0.35 - (size / 4.0);
	float adjustedTime = (pos * RENDERSIZE.x/RENDERSIZE.y - size)/(1.0 - size);

	if ( (dist <= (adjustedTime + size)) && (dist >= (adjustedTime - size)) ) 	{
		float diff = (1.0 - abs(adjustedTime - dist) / size);
		
		vec4 colorL = IMG_NORM_PIXEL(inputImage, left_coord);
		vec4 colorR = IMG_NORM_PIXEL(inputImage, right_coord);
		vec4 colorA = IMG_NORM_PIXEL(inputImage, above_coord);
		vec4 colorB = IMG_NORM_PIXEL(inputImage, below_coord);
	
		vec4 colorLA = IMG_NORM_PIXEL(inputImage, lefta_coord);
		vec4 colorRA = IMG_NORM_PIXEL(inputImage, righta_coord);
		vec4 colorLB = IMG_NORM_PIXEL(inputImage, leftb_coord);
		vec4 colorRB = IMG_NORM_PIXEL(inputImage, rightb_coord);
	
		float gx = (0.0);
		float gy = (0.0);
		
		gx = (-1.0 * gray(colorLA)) + (-1.0 * gray(colorL)) + (-1.0 * gray(colorLB)) + (1.0 * gray(colorRA)) + (1.0 * gray(colorR)) + (1.0 * gray(colorRB));
		gy = (1.0 * gray(colorLA)) + (1.0 * gray(colorA)) + (1.0 * gray(colorRA)) + (-1.0 * gray(colorRB)) + (-1.0 * gray(colorB)) + (-1.0 * gray(colorLB));

		float bright = pow(gx*gx + gy*gy,0.5);
		vec4 final = color * bright;
		
		final = (final * (intensity)) * diff;
		final.a = 1.0;
		
		color = final;
		
	} else {
		color = vec4(0.0, 0.0, 0.0, 1.0);
	}
	
	// echo trace mashup
	
	float brightLevel = (color.r + color.b + color.g) / 3.0;
	
	if (brightLevel < 0.5)
		brightLevel = 1.0;
	else
		brightLevel = 0.0;

	color = mix(color, stalePixel*(1.-fade), brightLevel);

		
	vec4 redrecord = color * redfilter1;
	vec4 bluegreenrecord = color * bluegreenfilter1;
	vec4 rednegative = vec4(redrecord.r);
	vec4 bluegreennegative = vec4((bluegreenrecord.g + bluegreenrecord.b)/2.0);

	vec4 redoutput = rednegative * redfilter1;
	vec4 bluegreenoutput = bluegreennegative * bluegreenfilter1;

	// additive 'projection"
    	vec4 result = redoutput + bluegreenoutput;

    	color = mix(color, result, colorize);
        color.a = 1.0;
	
	    gl_FragColor = color;
     }
	  else if (PASSINDEX == 1) {
        gl_FragColor = IMG_THIS_PIXEL(BufferA);
    }
}