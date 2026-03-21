/*{
  "DESCRIPTION": "Your shader description",
  "CREDIT": "by you",
  "CATEGORIES": [
    "Stylize"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "LABEL": "WIDTH",
      "NAME": "WIDTH",
      "TYPE": "float",
      "DEFAULT": 0.01,
      "MIN": 0,
      "MAX": 1
    }
  ]
}*/

// Ported from "Jean Claude VanEdgeDetection" by Oodar: https://www.shadertoy.com/view/4dyGzd

vec3 iResolution = vec3(RENDERSIZE, 1.);

mat3 kernelX;
mat3 kernelY;

vec4 toGrey( in vec4 col )
{
    float g = (0.3 * col.x) + (0.6 * col.y) + (0.11 * col.z);
    return vec4(g, g, g, 1.0);
}

float getGrey( in vec4 col )
{
    return (0.3 * col.x) + (0.6 * col.y) + (0.11 * col.z);
}

vec2 getUVCoord(in vec2 fragCoord)
{
    return fragCoord.xy / iResolution.xy;
}



void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    float WIDTH = WIDTH*100.;
    kernelX[0] = vec3(-WIDTH/2.0, -WIDTH, -WIDTH/2.0);
	kernelX[1] = vec3(0.0, 0.0, 0.0);
	kernelX[2] = vec3(WIDTH/2.0, WIDTH, WIDTH/2.0);

	kernelY[0] = vec3(-WIDTH/2.0, 0.0, WIDTH/2.0);
	kernelY[1] = vec3(-WIDTH, 0.0, WIDTH);
	kernelY[2] = vec3(-WIDTH/2.0, 0.0, WIDTH/2.0);
    
	vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 topLeft = getUVCoord(vec2(fragCoord.x - 1.0, fragCoord.y - 1.0));
    vec2 midLeft = getUVCoord(vec2(fragCoord.x - 1.0, fragCoord.y));
    vec2 botLeft = getUVCoord(vec2(fragCoord.x - 1.0, fragCoord.y + 1.0));
    
    vec2 midTop = vec2(uv.x, uv.y - 1.0);
    vec2 mid = uv;
    vec2 midBot = vec2(uv.x, uv.y + 1.0);
    
    vec2 topRight = getUVCoord(vec2(fragCoord.x + 1.0, fragCoord.y - 1.0));
    vec2 midRight = getUVCoord(vec2(fragCoord.x + 1.0, fragCoord.y));
    vec2 botRight = getUVCoord(vec2(fragCoord.x + 1.0, fragCoord.y + 1.0));
    
    float magX = 0.0;
    float magY = 0.0;
    
    // apply kernel in x direction
    magX += getGrey(IMG_NORM_PIXEL(inputImage, topLeft, 0.0)) * kernelX[0][0];
    magX += getGrey(IMG_NORM_PIXEL(inputImage, midLeft, 0.0)) * kernelX[0][1];
    magX += getGrey(IMG_NORM_PIXEL(inputImage, botLeft, 0.0)) * kernelX[0][2];
    
    magX += getGrey(IMG_NORM_PIXEL(inputImage, topRight, 0.0)) * kernelX[2][0];
    magX += getGrey(IMG_NORM_PIXEL(inputImage, midRight, 0.0)) * kernelX[2][1];
    magX += getGrey(IMG_NORM_PIXEL(inputImage, botRight, 0.0)) * kernelX[2][2];
    
    
    // apply kernel in y direction
    magY += getGrey(IMG_NORM_PIXEL(inputImage, topLeft, 0.0)) * kernelY[0][0];
    magY += getGrey(IMG_NORM_PIXEL(inputImage, midLeft, 0.0)) * kernelY[0][1];
    magY += getGrey(IMG_NORM_PIXEL(inputImage, botLeft, 0.0)) * kernelY[0][2];
    
    magY += getGrey(IMG_NORM_PIXEL(inputImage, topRight, 0.0)) * kernelY[2][0];
    magY += getGrey(IMG_NORM_PIXEL(inputImage, midRight, 0.0)) * kernelY[2][1];
    magY += getGrey(IMG_NORM_PIXEL(inputImage, botRight, 0.0)) * kernelY[2][2];
    
    //fragColor = toGrey(IMG_NORM_PIXEL(iChannel0, topLeft, 0.0));
    float mag = sqrt((magX*magX) + (magY * magY));
    
    fragColor = vec4(mag, mag, mag, 1.0);
}

void main(void) {
    mainImage(gl_FragColor, gl_FragCoord.xy);
}