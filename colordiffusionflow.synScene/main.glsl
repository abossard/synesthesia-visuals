

///////////////////////////////////////////
// ColorDiffusionFlow  by mojovideotech
//
// based on :
// glslsandbox.com/\e#35553.0
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
///////////////////////////////////////////


#ifdef GL_ES
precision mediump float;
#endif
 
#define 	pi   	3.141592653589793 	// pi

vec4 renderMain() { 
 	vec4 out_FragColor = vec4(0.0);

	float T = TIME * rate1;
	float TT = TIME * rate2;
	vec2 p=(2.*_uv);
	for(int i=1;i<11;i++) {
    	vec2 newp=p;
		float ii = float(i);  
    	newp.x+=depthX/ii*sin(ii*pi*p.y+T*nudge+cos((TT/(5.0*ii))*ii));
    	newp.y+=depthY/ii*cos(ii*pi*p.x+TT+nudge+sin((T/(5.0*ii))*ii));
		float timeline = log(max(TIME + 1.0, 1.0))/loopcycle;
		p=newp+timeline;
  }
  vec3 col=vec3(cos(p.x+p.y+3.0*color1)*0.5+0.5,sin(p.x+p.y+6.0*cycle1)*0.5+0.5,(sin(p.x+p.y+9.0*color2)+cos(p.x+p.y+12.0*cycle2))*0.25+.5);
  out_FragColor=vec4(col*col, 1.0);

return out_FragColor; 
 } 
