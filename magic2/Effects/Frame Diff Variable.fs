/*{
	"CREDIT": "by joshpbatty",
	"DESCRIPTION": "Feedback GLSL",
	"CATEGORIES": [
		"Joshua Batty"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{
			"NAME": "color",
			"TYPE": "float",
			"DEFAULT": 1.0
		},
		{
			"NAME": "motionThreshold",
			"TYPE": "float",
			"DEFAULT": 0.25
		},
		{
			"NAME": "sludge",
			"TYPE": "float",
			"DEFAULT": 0.95
		}
	],
	"PASSES": [
    {
      "TARGET": "previousFrame",
      "PERSISTENT": true
    }, { 
    }
	]
}*/

void main() {
	
	vec4 currentPixel = IMG_THIS_PIXEL(inputImage);
	vec4 previousPixel = IMG_THIS_PIXEL(previousFrame);
	if (PASSINDEX == 0) {
		float modVal = pow(sludge, 0.5);
		gl_FragColor = mix(currentPixel,previousPixel,modVal);
	}
	 else  {
        
        // Calculate the absolute difference between the current and previous frame
        vec4 difference = abs(currentPixel - previousPixel);
        
        // Calculate motion intensity
        float motionIntensity = dot(difference.rgb, vec3(0.299, 0.587, 0.114)); // Convert to grayscale
        
        // Apply threshold
        motionIntensity = step(motionThreshold, motionIntensity);
        vec3 outColor = mix(currentPixel.rgb, vec3(1.0), 1.0-color);
        // Output the motion detection result
        gl_FragColor = vec4(vec3(motionIntensity * outColor), 1.0);	 
	     
	 }
}