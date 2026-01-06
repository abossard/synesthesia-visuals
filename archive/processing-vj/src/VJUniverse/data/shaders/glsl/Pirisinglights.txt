#ifdef GL_ES
precision mediump float;
#endif

// suspended illumination by kapsy1312.tumblr.com

uniform float time;
uniform vec2 resolution;

void main( void ) {
    
    float sum = .5;
    float size = resolution.x / 2.0;
    float g = .85;
    int num = 30;
	
	float t = time/3.0;
	
    for (int i = 0; i < 10; ++i) {
        vec2 position = resolution / 2.0;
        position.x += sin(t / 1.0 + 1.0 * float(i)) * resolution.x * 0.25;
        position.y += tan(t / 1.0 + (1.0 + sin(t) * 0.2) * float(i)) * resolution.y * 0.3;
        
        float dist = length(gl_FragCoord.xy - position);
        
        sum += size / pow(dist, g);
    }
    
    //vec4 color = vec4(0,0,1,1);
    float val = sum / float(num);
    vec4 color = vec4(val*0.8, val*0.2, val*0.4, 1);
    
    gl_FragColor = vec4(color);
}