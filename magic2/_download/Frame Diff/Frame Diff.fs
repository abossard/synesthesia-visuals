/*
{
  "CATEGORIES" : [
    "Feedback"
  ],
  "DESCRIPTION" : "Automatically converted from https:\/\/www.shadertoy.com\/view\/XtcSWM by aferriss.  Moving texture coordinates in a circle based on hue.",
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "gain",
      "TYPE" : "float",
      "DEFAULT": 0.95
    }
  ],
  "PASSES" : [
    {
      "TARGET" : "BufferA",
      "PERSISTENT" : true
    },
    {
      "TARGET" : "BufferB",
      "PERSISTENT" : true
    },
    {

    }
  ],
  "ISFVSN" : "2"
}
*/


void main() {
	if (PASSINDEX == 0)	{
                // Get the current and previous frame's pixel values
        vec4 currentPixel = IMG_THIS_PIXEL(inputImage);
        vec4 previousPixel = IMG_THIS_PIXEL(BufferB);

        // Calculate the absolute difference between the current and previous frame
        vec4 difference = abs(currentPixel - previousPixel);

        // Convert the RGB difference to a grayscale intensity to represent motion
        float motionIntensity = dot(difference.rgb, vec3(0.299, 0.587, 0.114)); // Luma calculation for grayscale

        // Output the motion intensity
       float diff = motionIntensity * gain * 2.;
       
        gl_FragColor = mix(vec4(0,0.0,0.0,1.0), currentPixel, min(1.0, diff));

	}
	else if (PASSINDEX == 1) {
        gl_FragColor = IMG_THIS_PIXEL(inputImage);

	}
	else if (PASSINDEX == 2) {
        gl_FragColor = IMG_THIS_PIXEL(BufferA);

	}
}
