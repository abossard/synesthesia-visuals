// added a bit of burning color

#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


// Trapped by curiouschettai

void main( void ) {  
	vec2 uPos = ( gl_FragCoord.xy / resolution.y );//normalize wrt y axis
	uPos -= vec2((resolution.x/resolution.y)/2.0, 0.5);//shift origin to center
	
	float multiplier = 0.0005; // Grosseur
	const float step = 0.006; //segmentation
	const float loop = 100.0; //Longueur
	const float timeSCale = 0.5; // Vitesse
	
	vec3 blueGodColor = vec3(0.0);
	for(float i=1.0;i<loop;i++){		
		float t = time*timeSCale-step*i;
		vec2 point = vec2(0.75*sin(t), 0.5*sin(t));
		point += vec2(0.75*cos(t*4.0), 0.5*sin(t*3.0));
		point /= 2.0;
		float componentColor= multiplier/((uPos.x-point.x)*(uPos.x-point.x) + (uPos.y-point.y)*(uPos.y-point.y))/i;
		blueGodColor += vec3(componentColor/3.0, componentColor/3.0, componentColor);
	}
	
	
	vec3 color = vec3(0,0,0);
	color += pow(blueGodColor,vec3(0.1,0.3,0.8));
   
	
	gl_FragColor = vec4(color, 1.0);
}