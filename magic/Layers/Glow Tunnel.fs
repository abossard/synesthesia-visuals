/*
{
  "CATEGORIES" : [
    "Generator",
    "INKA",
    "XXX"
  ],
  "DESCRIPTION" : "Tunnel effect with dynamic circles and customizable controls, using the geometry and positioning from the first shader. Fades the rings both in the middle and at the very edges.",
  "INPUTS" : [
    {
      "NAME": "line",
      "TYPE": "float",
      "DEFAULT": 0.02,
      "MIN": 0.01,
      "MAX": 0.1
    },
    {
      "NAME": "brightness",
      "TYPE": "float",
      "DEFAULT": 0.5,
      "MIN": 0.1,
      "MAX": 1.0
    },
    {
      "NAME": "depth",
      "TYPE": "float",
      "DEFAULT": 2.0,
      "MIN": 0.0,
      "MAX": 5.0
    },
    {
      "NAME" : "speed",
      "TYPE" : "float",
      "MAX" : 1,
      "MIN" : 0,
      "DEFAULT": 0.2
    },
    {
      "NAME" : "moveX",
      "TYPE" : "float",
      "DEFAULT": 0.0,
      "MAX" : 1,
      "MIN" : -1
    },
    {
      "NAME" : "moveY",
      "TYPE" : "float",
      "DEFAULT": 0.25,
      "MAX" : 1,
      "MIN" : -1
    },
    {
		"NAME": "color",
		"TYPE": "color",
		"DEFAULT": [
			0.6,
			0.2,
			0.2,
			1.0
		]
	}
  ],
  "ISFVSN" : "2"
}
*/

// Constants
#define TAU 6.2831853071795865

// Parameters
#define TUNNEL_LAYERS 10

// Square of x
float sq(float x)
{
    return x * x;
}

// Tunnel/Camera path
vec2 TunnelPath(float x)
{
    vec2 offs = vec2(0, 0);
    
    offs.x = 0.3 * TAU * x * moveX;
    offs.y = 0.15 * TAU * x * moveY;
    
    return offs;
}

// Smooth fade function to fade in the middle and at the edges
float fadeMiddleAndEdges(float len, float maxLen)
{
    float middleFade = smoothstep(0.0, 0.5 * maxLen, len);
    float edgeFade = smoothstep(1.0, 0.5 * maxLen, len);
    return middleFade * (1.0 - edgeFade);
}

float vignetted(vec2 normalizedTexcoord, float inversion, float vignetteedge, float vignetteMix)
{
	normalizedTexcoord = 2.0 * normalizedTexcoord - 1.0; // - 1.0 to 1.0
	float r = length(normalizedTexcoord);
	return 1.0 - (smoothstep(inversion, 1.0 - inversion, pow(clamp(r - vignetteMix, 0.0, 1.0), 1.0 + vignetteedge * 10.0)));

}


void main() {
    vec2 uv = isf_FragNormCoord.xy - 0.5;
    uv.x *= RENDERSIZE.x / RENDERSIZE.y; // Aspect-ratio correction

    vec3 c = vec3(0.0);
    float camZ = TIME * speed;
    vec2 camOffs = TunnelPath(camZ);

    for (int i = 0; i < TUNNEL_LAYERS; i++) {
        float pz = 1.0 - (float(i) / float(TUNNEL_LAYERS));
        
        // Scroll the points towards the screen
        pz -= mod(camZ, 1.0 / float(TUNNEL_LAYERS));
        
        // Layer x/y offset
        vec2 offs = TunnelPath(camZ + pz) - camOffs;
        
        // Radius of the current ring
        float ringRad = 1.0 / sq(pz * depth + 0.9);

        // Compute dynamic outline of the ring
        float len = length(uv + offs);
        float outline = line / abs(len - (ringRad / (1.0 + pz)));


        // Accumulate the color with brightness, depth-based fading, and custom fade factor
        c += color.rgb * outline * brightness * (1.0 - pz) ;
    }

    gl_FragColor = vec4(c, 1.0);
}
