/*
{
  "CATEGORIES" : [
    "Glitch"
  ],
  "DESCRIPTION" : "Causes only part of an image to update",
  "ISFVSN" : "2",
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "maxUpdateSize",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.5,
      "LABEL" : "Size",
      "MIN" : 0
    },
    {
      "NAME" : "fadeSpeed",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.5,
      "MIN" : 0
    },
    {
      "NAME" : "seedShift",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.5,
      "MIN" : 0
    },
    {
      "NAME" : "maxBlendAmount",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0,
      "MIN" : 0
    },
    {
      "NAME" : "manual",
      "TYPE" : "bool",
      "DEFAULT": false
    }
  ],
  "PASSES" : [
    {
      "TARGET" : "lastState",
      "PERSISTENT" : true,
      "DESCRIPTION" : ""
    }
  ],
  "CREDIT" : "VIDVOX"
}
*/

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec4 rand4(vec4 co)	{
	vec4	returnMe = vec4(0.0);
	returnMe.r = rand(co.rg);
	returnMe.g = rand(co.gb);
	returnMe.b = rand(co.ba);
	returnMe.a = rand(co.rb);
	return returnMe;
}

vec3 hsv2rgb(vec3 c)	{
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

const float pi = 3.14159265359;


bool pointInRect(vec2 pt, vec4 r)
{
	bool	returnMe = false;
	if ((pt.x >= r.x)&&(pt.y >= r.y)&&(pt.x <= r.x + r.z)&&(pt.y <= r.y + r.w))
		returnMe = true;
	return returnMe;
}

void main()	{
	vec2	loc = isf_FragNormCoord.xy;
	vec4	returnMe = IMG_THIS_PIXEL(lastState);
	float speed = manual ? seedShift : floor(TIME * seedShift * 100.);
	vec4	seeds1 = speed * vec4(0.2123,0.34517,0.53428,0.7431);
	vec4	seeds2 = speed * vec4(0.7431,0.53428,0.2123,0.34517);

	vec4	randCoords = rand4(seeds1);
	vec4	randCoords2 = rand4(seeds2);
	randCoords.zw *= maxUpdateSize;
	randCoords2.zw *= maxUpdateSize;
	if (randCoords.x + randCoords.z > 1.0)
		randCoords.z = 1.0 - randCoords.x;
	if (randCoords.y + randCoords.w > 1.0)
		randCoords.w = 1.0 - randCoords.y;

	if (randCoords2.x + randCoords2.z > 1.0)
		randCoords2.z = 1.0 - randCoords2.x;
	if (randCoords2.y + randCoords2.w > 1.0)
		randCoords2.w = 1.0 - randCoords2.y;
		
	bool	isInShape = pointInRect(loc,randCoords);
	bool	isInShape2 = pointInRect(loc,randCoords2);
	
	returnMe -= 0.1 * fadeSpeed;

	if (isInShape || isInShape2)	{
		float		mixAmount = maxBlendAmount * rand(vec2(TIME,0.32234));
		vec4		newColor = IMG_THIS_PIXEL(inputImage);
		newColor.a = 1.0;
		returnMe = mix(newColor,returnMe,mixAmount);
	}
	
	gl_FragColor = returnMe;
}
