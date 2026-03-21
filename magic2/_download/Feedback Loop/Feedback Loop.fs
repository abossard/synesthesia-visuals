/*{
  "DESCRIPTION": "trails",
  "CREDIT": "INKA",
  "CATEGORIES": [
    "Feedback",
    "INKA"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "feedback",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 1.0
    },
    {
      "NAME": "hue",
      "TYPE": "float"
    },
    {
      "NAME": "saturation",
      "TYPE": "float"
    },
    {
      "NAME": "zoom",
      "TYPE": "float",

      "DEFAULT": 0.2
    },
    {
      "NAME": "brightness",
      "TYPE": "float",
      "DEFAULT": 1
    },
    {
      "NAME": "bleedthrough",
      "TYPE": "float",
      "DEFAULT": 0.5
    },
    {
      "NAME": "rotation",
      "TYPE": "float"
    }
  ],
  "PASSES" : [
    {
      "TARGET" : "BufferA",
      "PERSISTENT" : true
    },
    {

    }
  ]
}*/



float gray(vec4 n)
{
	return (n.r + n.g + n.b)/3.0;
}


vec3 rgb2hsv(vec3 c)	{
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = c.g < c.b ? vec4(c.bg, K.wz) : vec4(c.gb, K.xy);
	vec4 q = c.r < p.x ? vec4(p.xyw, c.r) : vec4(c.r, p.yzx);
	
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)	{
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}


mat2 rotmat( float deg ) {
	float theta = radians(deg);
	float s = sin(theta);
	float c = cos(theta);

	return mat2(c, -s, s, c);
}

void main()
{
	vec2 uv =  gl_FragCoord.xy / RENDERSIZE.xy;
	vec4 color;

	if (PASSINDEX == 0)	{
		vec4 original = IMG_THIS_PIXEL(inputImage);
 		vec2 warp = (uv - 0.5) * (1.0 + zoom * 0.05);
 		
		warp *= rotmat(rotation * .25);
		warp += 0.5;
		warp.y += 0.0009;
		
 		color = IMG_NORM_PIXEL(BufferA, warp); 
 		
 		vec4 tmpColor;
 		
 		tmpColor.xyz = rgb2hsv(color.rgb);
		tmpColor.a = color.a;
		
		// hue
		tmpColor.x = mod((tmpColor.x + hue * 0.01), 1.0);
		
		//	saturation
		tmpColor.y = tmpColor.y * (1. + saturation * .3);
		
		// brightness
		tmpColor.z -= brightness * 0.01;
		color.rgb = hsv2rgb(clamp(tmpColor.xyz, 0.0, 1.0));
		
		if(bleedthrough > 0.) {
			if(gray(original) > 1.0 - bleedthrough) {
				color = original;
			}
		}

		gl_FragColor = mix(original, color, feedback);
	}
	else if (PASSINDEX == 1)	{	
		color = IMG_THIS_PIXEL(BufferA);
			
		gl_FragColor = color;
	}
}
