#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

uniform float x,y;

//few years old shader that came about after being shown the massive clod. -george toledo

float f(vec3 o){	
	float a=(cos(o.x)+o.y*1.)*.2;
	o=vec3(cos(a)-sin(a),sin(a)*cos(a),o.z);
	return dot(cos(o)*cos(o),vec3(2.))-1.5;
}

vec3 s(vec3 o,vec3 d){
	float t=0.,a,b;
	for(int i=0;i<500;i++){
		if(f(o+d*t)<1.){
			a=t;
			b=t+1.;
			for(int i=0; i<1;i++){
				t=((a+b)*.5);
				if(f(o+d*t)<0.)b=t;
				else a=t;
			}
			vec3 e=vec3(1.,1.,1.),p=o+d*t,n=-normalize(vec3(f(p+e),f(p+e.yxy),f(p+e.yyx))+vec3((sin(p*3.14)))*95.0);
			return vec3(mix( ((max(-dot(n,vec3(1.0)),-1.) + 0.15*max(-dot(n,vec3(1.,1.,0.)),0.)))*(mod(length(p.xy)*.2,1.)<1.0?vec3(.1,.1,.5):vec3(.79,.3,.4)),vec3(1.,.1,.1),vec3(pow(t/50.,1.))));
		}
		t+=3.2
	;
	}
	return vec3(1.,1.,1.);
}

void main(){
	
	float t=dot(gl_FragColor.xyz,vec3(1.,1.,1.))*5.;
	gl_FragColor=vec4(s(vec3(cos(time*1.)*.1,sin(time)*1.2,time), normalize(vec3((gl_FragCoord.xy-vec2(resolution.x,resolution.y)/1.75)/vec2(resolution.x),.1))),1.);
}