/*{
	"CREDIT": "by isakburstrom",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"Glitch"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "glitchAmount",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "trackingAmount",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
		},
		{
			"NAME": "trackingSize",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
		}
	]
}*/
#define TRACKING_SPEED 0.2

const float range = 0.05;
	
float rand(vec2 co)
{
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

float verticalBar(float pos, float uvY, float offset)
{
    float edge0 = (pos - range);
    float edge1 = (pos + range);

    float x = smoothstep(edge0, pos, uvY) * offset;
    x -= smoothstep(pos, edge1, uvY) * offset;
    return x;
}

//2D (returns 0 - 1)
float random2d(vec2 n) { 
    return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float randomRange (in vec2 seed, in float min, in float max) {
		return min + random2d(seed) * (max - min);
}

// return 1 if v inside 1d range
float insideRange(float v, float bottom, float top) {
   return step(bottom, v) - step(top, v);
}

   
vec2 glitchBlocks(vec2 uv ) {
	//inputs
	float AMT = glitchAmount * 0.25; //0 - 1 glitch amount
	float SPEED = 0.2 + 0.4 * glitchAmount; //0 - 1 speed
    float _time = floor(TIME * SPEED * 60.0);    

    //randomly offset slices horizontally
    float maxOffset = AMT/2.0;
    for (float i = 0.0; i < 10.0; i += 1.0) {
    	if(i > 10.0 * AMT) {
    		return uv;
    	}
        float sliceY = random2d(vec2(_time , 2345.0 + float(i)));
        float sliceH = random2d(vec2(_time , 9035.0 + float(i))) * 0.25;
        float hOffset = randomRange(vec2(_time , 9625.0 + float(i)), -maxOffset, maxOffset);
        vec2 uvOff = uv;
        uvOff.x += hOffset;
        if (insideRange(uv.y, sliceY, fract(sliceY+sliceH)) == 1.0 ){
        	return uvOff;
        }
    }
    
	return uv;
}

void main() {
	vec2 uv = isf_FragNormCoord;
	
	float TRACKING_HEIGHT = 0.15 * trackingSize;
	float TRACKING_SEVERITY = 0.025 * trackingAmount;
    // Tracking
    float t = TIME * TRACKING_SPEED;
    float fractionalTime = (t - floor(t)) * 1.3 - TRACKING_HEIGHT;
    if(fractionalTime + TRACKING_HEIGHT >= uv.y && fractionalTime <= uv.y)
    {
        uv.x -= fractionalTime * TRACKING_SEVERITY;
    }
    
    
	gl_FragColor = IMG_NORM_PIXEL(inputImage, glitchBlocks(uv));
}