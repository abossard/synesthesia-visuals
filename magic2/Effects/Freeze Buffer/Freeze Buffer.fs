/*
{
  "CATEGORIES" : [
    "Feedback"
  ],
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "delay",
      "TYPE" : "float",
      "DEFAULT": 1.0  
    }
  ],
  "PASSES" : [
    {
      "TARGET" : "BufferA",
      "PERSISTENT" : true
    },
    {
      "TARGET" : "BufferB"
    }
  ],
  "ISFVSN" : "2"
}
*/

void main() {
    // Use the first pass to capture and store the image.
    if (PASSINDEX == 0) {
        // Check if we are in the right time interval to sample
        if (delay == 0.0 || mod(TIME, delay * 0.5) < 0.01) { // Small epsilon to trigger on the transition
            // Sample the input image and store it in BufferA
            gl_FragColor = IMG_THIS_PIXEL(inputImage);
        } else {
            // Keep the previous frame in the buffer
            gl_FragColor = IMG_NORM_PIXEL(BufferA, isf_FragNormCoord);
        }
    }
    // Use the second pass to display the captured image
    else if (PASSINDEX == 1) {
        // Output the content of BufferA
        gl_FragColor = IMG_THIS_PIXEL(BufferA);
    }
}
