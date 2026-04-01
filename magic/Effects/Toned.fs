/*{
  "CREDIT": "by v002",
  "ISFVSN": "2",
  "CATEGORIES": [
    "v002",
    "Film"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "amount",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 0.5
    }
  ]
}*/


//	Based on v002 technicolor – https://github.com/v002/v002-Film-Effects/

const vec4 redfilter1 		= vec4(1., 0., -0.5, 1.0);
const vec4 bluegreenfilter1 	= vec4(1.0, 1.0, 0.0, 1.0);




void main (void) 
{
	vec4 input0 = IMG_THIS_PIXEL(inputImage);
	vec4 result;

	vec4 redrecord = input0 * redfilter1;
	vec4 bluegreenrecord = input0 * bluegreenfilter1;
	vec4 rednegative = vec4(redrecord.r);
	vec4 bluegreennegative = vec4((bluegreenrecord.g + bluegreenrecord.b)/2.0);

	vec4 redoutput = rednegative * redfilter1;
	vec4 bluegreenoutput = bluegreennegative * bluegreenfilter1;

	// additive 'projection"
	result = redoutput + bluegreenoutput;

	result = mix(input0, result, amount);
	result.a = input0.a;
	gl_FragColor = result;		
} 