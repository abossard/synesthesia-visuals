/*
{
  "CATEGORIES" : [
    "Distortion Effect"
  ],
  "DESCRIPTION" : "Simple Displace",
  "ISFVSN" : "2",
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "displaceImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "xAmount",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.8,
      "MIN" : 0
    },
    {
      "NAME" : "yAmount",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0.5,
      "MIN" : 0
    }
    ]
}
*/

float lum(vec3 color) {
    return color.r*.2+color.g*.7+color.b*.1;
}

void main() {
	vec2 st = isf_FragNormCoord.xy;
    
    float displace = lum(IMG_NORM_PIXEL(displaceImage,st).rgb);	

	st.y += (displace/10.) * yAmount;
	st.x += (displace/10.) * xAmount;
	gl_FragColor = IMG_NORM_PIXEL(inputImage, st);

}
