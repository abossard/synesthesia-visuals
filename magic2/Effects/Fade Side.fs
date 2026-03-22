/*{
	"CREDIT": "by Joris de Jong",
	"DESCRIPTION": "Vignette Spot",
	"CATEGORIES": [
		"filter"
	],
	"INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
		{ 
			"NAME": "progress", 
			"TYPE": "float", 
			"DEFAULT": 0.5
		},
		{ 
			"NAME": "smoothing", 
			"TYPE": "float", 
			"DEFAULT": 0.2
		},
		{ 
			"NAME": "fromLeft", 
			"TYPE": "bool", 
			"DEFAULT": true
		}
		
	]
}*/

vec2 center = vec2(0.5);


float transition (vec2 uv, float progress, float smoothness) {
  vec2 v = normalize(vec2(fromLeft ? -1. : 1., 0.0));
  v /= abs(v.x)+abs(v.y);
  float d = v.x * center.x + v.y * center.y;
  float m =
    (1.0-step(progress, 0.0)) * // there is something wrong with our formula that makes m not equals 0.0 with progress is 0.0
    (1.0 - smoothstep(-smoothness, 0.0, v.x * uv.x + v.y * uv.y - (d-0.5+progress*(1.+smoothness))));
  return m;
}

void main() {
	float mask = transition(isf_FragNormCoord, progress, smoothing );
	vec4 color = IMG_NORM_PIXEL(inputImage, isf_FragNormCoord.xy);
	gl_FragColor = color * mask;
}
