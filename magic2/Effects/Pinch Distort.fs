/*{
  "CREDIT": "by VIDVOX",
  "CATEGORIES": [
    "Distortion Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "amount",
      "LABEL": "Amount",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 1,
      "DEFAULT": 0
    },
    {
      "NAME": "expand",
      "LABEL": "Expand",
      "TYPE": "bool",
      "DEFAULT": 0
    }
  ],
  "PASSES": [
    {
      "TARGET": "edgeBuffer"
    },
    {
      "TARGET": "blurBuffer"
    },
    {}
  ]
}*/


varying vec2 left_coord;
varying vec2 right_coord;
varying vec2 above_coord;
varying vec2 below_coord;

varying vec2 lefta_coord;
varying vec2 righta_coord;
varying vec2 leftb_coord;
varying vec2 rightb_coord;



//	reverse engineered from Pinch.qtz

//	first do this series of FX to determine the amount of displacement
//		mirror-edge
//		edge detection
//		blur
//		invert (if expanding)
//		contrast reduction
//	then use the result to figure out how much to distort by



float gray(vec4 n)
{
	return (n.r + n.g + n.b)/3.0;
}



void main() {		
	//	on the first pass just do the edge detection
	if (PASSINDEX == 0)	{
		float intensity = 25.0;
	
		vec4 color = IMG_THIS_PIXEL(inputImage);
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
		
		gx = (-1.0 * gray(colorLA)) + (-2.0 * gray(colorL)) + (-1.0 * gray(colorLB)) + (1.0 * gray(colorRA)) + (2.0 * gray(colorR)) + (1.0 * gray(colorRB));
		gy = (1.0 * gray(colorLA)) + (2.0 * gray(colorA)) + (1.0 * gray(colorRA)) + (-1.0 * gray(colorRB)) + (-2.0 * gray(colorB)) + (-1.0 * gray(colorLB));

		float bright = pow(gx*gx + gy*gy, 0.5);
		vec4 final = color * bright;
	
		final = final * intensity;
		final.a = 1.0;
	
		gl_FragColor = final;	
	}
	//	then on the 2nd pass first do a blur, then invert if needed, then use the result for the distortion
	else if (PASSINDEX == 1)	{
		vec4 color = IMG_THIS_PIXEL(edgeBuffer);
		vec4 colorL = IMG_NORM_PIXEL(edgeBuffer, left_coord);
		vec4 colorR = IMG_NORM_PIXEL(edgeBuffer, right_coord);
		vec4 colorA = IMG_NORM_PIXEL(edgeBuffer, above_coord);
		vec4 colorB = IMG_NORM_PIXEL(edgeBuffer, below_coord);

		vec4 colorLA = IMG_NORM_PIXEL(edgeBuffer, lefta_coord);
		vec4 colorRA = IMG_NORM_PIXEL(edgeBuffer, righta_coord);
		vec4 colorLB = IMG_NORM_PIXEL(edgeBuffer, leftb_coord);
		vec4 colorRB = IMG_NORM_PIXEL(edgeBuffer, rightb_coord);

		vec4 blurVector = clamp((color + colorL + colorR + colorA + colorB + colorLA + colorRA + colorLB + colorRB) / 9.0, 0.0, 1.0);
		
		gl_FragColor = blurVector;
	}
	else	{
		vec4 color = IMG_THIS_PIXEL(blurBuffer);
		vec4 colorL = IMG_NORM_PIXEL(blurBuffer, left_coord);
		vec4 colorR = IMG_NORM_PIXEL(blurBuffer, right_coord);
		vec4 colorA = IMG_NORM_PIXEL(blurBuffer, above_coord);
		vec4 colorB = IMG_NORM_PIXEL(blurBuffer, below_coord);

		vec4 colorLA = IMG_NORM_PIXEL(blurBuffer, lefta_coord);
		vec4 colorRA = IMG_NORM_PIXEL(blurBuffer, righta_coord);
		vec4 colorLB = IMG_NORM_PIXEL(blurBuffer, leftb_coord);
		vec4 colorRB = IMG_NORM_PIXEL(blurBuffer, rightb_coord);

		vec4 blurVector = clamp((color + colorL + colorR + colorA + colorB + colorLA + colorRA + colorLB + colorRB) / 9.0, 0.0, 1.0);
		
		if (!expand)	{
			blurVector.rgb = 1.0 - blurVector.rgb;
		}
		
		//	apply contrast, up to 0.8
		blurVector.rgb = ((vec3(2.0) * (blurVector.rgb - vec3(0.5))) * vec3(amount * 0.8) / vec3(2.0)) + vec3(0.5);
		
		float distortAmount = (gray(blurVector) - 0.5);
		vec2 loc = isf_FragNormCoord;
		//	the distortion vector should be in the direction from the center point
		vec2 distortVector = distortAmount * (isf_FragNormCoord - vec2(0.5)) / distance(loc, vec2(0.5));
		
		//vec4 sample0 = IMG_NORM_PIXEL(inputImage, clamp(loc + distortVector * amount,0.0,1.0));
		//vec4 sample1 = IMG_NORM_PIXEL(inputImage, clamp(loc + 1.02 * distortVector * amount * amount,0.0,1.0));
		//gl_FragColor = (sample0 * 3.0 + sample1) / 4.0;
		
		distortVector = loc + distortVector * amount;
		
		if ((distortVector.x >= 0.0) && (distortVector.x <= 1.0) && (distortVector.y >= 0.0) && (distortVector.y <= 1.0))	{
			gl_FragColor = IMG_NORM_PIXEL(inputImage,distortVector);
		}
		else	{
			gl_FragColor = IMG_NORM_PIXEL(inputImage, loc + distortVector / 8.0);
		}
	}

}