#ifdef GL_ES
precision mediump float;
#endif

//pretending maths
//Rohan Karnik 
//rohan.n.karnik@gmail.com
//Stolen From Chris Birke shamelessly 

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float sdf(vec2 pos, float phi){		
	return length(vec3(pos, phi));
}

float flow(vec4 pos){
	float ft0, ft1, ft2, ft3;
	
	ft0  = pos.y - pos.x;
	ft0 *= pos.z - pos.x;
	ft0 *= pos.w - pos.x;
	
	ft1  = pos.x - pos.y;
	ft1 *= pos.z - pos.y;
	ft1 *= pos.w - pos.y;
	
	ft2  = pos.x - pos.z;
	ft2 *= pos.y - pos.z;
	ft2 *= pos.w - pos.z;
	
	ft3  = pos.x - pos.w;
	ft3 *= pos.y - pos.w;
	ft3 *= pos.w - pos.w;
	
	float a = 31.0;
	float e = 63.0;
	float po = 521.0;
	float fa = resolution.y - time ;
	float fe = resolution.y + time + po;
	
	
	return cos(a * (ft0 - ft1 - ft2 - ft3) - fa) * sin(e * (ft0 - ft1 - ft2 - ft3) + fe);
}

float edge(float dist, vec2 p0, vec2 p1, float w){
	if (dist >= 0.01){
		return (w / abs(p0.x * p1.y - p0.y * p1.x)) * 0.04;
	}
	return 0.0;
}

void main( void ) {
	
	vec2 coord = gl_FragCoord.xy / resolution.xy;
	
	//Some random positions
	vec2 pos0 = coord - mouse;
	vec2 pos1 = coord - vec2(0.1, 0.3) - mouse * 0.3;
	vec2 pos2 = coord - vec2(0.8, 0.9) + mouse * 0.3;
	vec2 pos3 = coord - vec2(0.3, 0.2) - mouse * 0.1;
	
	//Distance To Point
	float phi = .6;
	float s0 = sdf(pos0, phi); 
	float s1 = sdf(pos1, phi); 
	float s2 = sdf(pos2, phi); 
	float s3 = sdf(pos3, phi); 
	
	float s = s0 * s1 * s2 * s3;
		
	vec4 field = vec4(s0, s1, s2, s3);

	//Edges
	float w = 0.1;
	float edges0;
	float edges1;
	float edges2;
	float edges3;
	
	edges0  = edge(field.x, pos0, pos1, w);
	edges0 += edge(field.x, pos0, pos2, w);
	edges0 += edge(field.x, pos0, pos3, w);
	
	edges1  = edge(field.y, pos1, pos0, w);
	edges1 += edge(field.y, pos1, pos2, w);
	edges1 += edge(field.y, pos1, pos3, w);
	
	edges2  = edge(field.z, pos2, pos0, w);
	edges2 += edge(field.z, pos2, pos1, w);
	edges2 += edge(field.z, pos2, pos3, w);
	
	edges3  = edge(field.w, pos3, pos0, w);
	edges3 += edge(field.w, pos3, pos1, w);
	edges3 += edge(field.w, pos3, pos2, w);
	
	float edges = (edges0 * edges1 * edges2 * edges3) / s;
	
	//Flow
	float flow0 = flow(vec4(edges0, edges1, edges2, edges3));
	float flow1 = flow(vec4(edges1, edges2, edges3, edges0));
	float flow2 = flow(vec4(edges2, edges3, edges0, edges1));
	float flow3 = flow(vec4(edges3, edges0, edges1, edges2));
	float flows = flow0 + flow1 + flow2 + flow3;
	vec4 flowField = vec4(flow0, flow1, flow2, flow3);
	
	
	//Some Circles
	float b = 0.00005;
	w = .6001;
	float c0 = smoothstep(w, w-b, s0); 
	float c1 = smoothstep(w, w-b, s1); 
	float c2 = smoothstep(w, w-b, s2); 
	float c3 = smoothstep(w, w-b, s3); 
	vec4 circles = vec4(c0, c1, c2, c3) + c3;
	float mask = length(circles);
	
	gl_FragColor = min(vec4(1.0), flowField * field + edges) - mask + circles;
}