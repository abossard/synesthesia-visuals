// This tab is solely for rendering the functions.

#define SMOOTH_SIZE (5. / iResolution.y)

vec3 dfVisualize(float v)
{
    vec3 colorNegative = vec3(.2, .6, .6);
    vec3 colorPositive = vec3(.6, .6, .2);
    vec3 colorVoid = vec3(1, 1, 1);
    
    vec3 col = mix(
        mix(colorNegative, colorPositive, step(0., v)),
        colorVoid,
        smoothstep(0., 0.3, min(abs(v), .23)));
    col *= .3 + .7 * smoothstep(0., SMOOTH_SIZE, abs(fract(v * 10. + .5) -.5) / 10.);
    return col;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = (2. * fragCoord - iResolution.xy) / iResolution.y;
    
    uv *= 1.8;
    uv.y += iTime;
    
    float v = yinyangDots_surface(uv);
    
	vec3 col = dfVisualize(v);    

	vec2 rs = vec2(yinyangCurve_surface(uv), yinyang_arcLength(uv));
    
    rs.y = fract(rs.y + iTime) - .5;
    v = length(vec2(abs(rs.x), max(abs(rs.y) - .3, 0.))) - .05;
    
   	col = mix(col, vec3(.0, .0, .0), smoothstep(SMOOTH_SIZE, 0., v));
    
    col = sqrt(col);
    fragColor = vec4(col, 1.0);
}
