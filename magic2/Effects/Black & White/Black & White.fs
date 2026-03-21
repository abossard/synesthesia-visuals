/*{
  "CREDIT": "by Isak B",
  "DESCRIPTION": "Simple Black & White shader",
  "CATEGORIES": [
    "Color Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "amount",
      "TYPE": "float",
      "DEFAULT": 1
    }
  ]
}*/
const vec3 lumcoeff = vec3(0.3, 0.7, 0.1);

void main() {
	vec4 original = IMG_THIS_PIXEL(inputImage);
	vec3 desaturated = vec3(dot(original.rgb, lumcoeff));
	gl_FragColor = vec4(mix(original.rgb, desaturated, amount), original.a);
}