#ifdef GL_ES
precision mediump float;
#endif

uniform vec2 mouse;
uniform vec2 resolution;
uniform float time;

/* Made by Krisztián Szabó */
/* mod DamianPrg */
void main(){
	/* The light's positions */
	vec2 light_pos = resolution*mouse;
	/* The radius of the light */
	float radius = 1.0;
	/* Intensity range: 0.0 - 1.0 */
	float intensity = 0.2;
	
	/* Distance between the fragment and the light */
	float dist = distance(gl_FragCoord.xy, light_pos);
	
	/* Basic light color, change it to your likings */
	vec3 light_color = vec3(0.2, 1.0, .0);
	/* Alpha value of the fragment calculated based on intensity and distance */
	float alpha = 1.0 / (dist*intensity);
	
	/* The final color, calculated by multiplying the light color with the alpha value */
	vec4 final_color = vec4(light_color, 1.0)*vec4(alpha, alpha, alpha, 1.0);
	
	final_color.rgb *= atan(dist)+sin(dist+time*50.0);
	final_color.rgb *= 2.0;
	
	//final_color.rgb *= atan(dist)+cos(dist);
	
	gl_FragColor = final_color;
	
	/* If you want to apply radius to the effect comment out the gl_FragColor line and remove comments from below: */
	

	
}