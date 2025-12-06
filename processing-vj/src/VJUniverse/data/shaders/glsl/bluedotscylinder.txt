// Playing around with Lissajous curves.
#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

const int num = 200;

void main( void ) {
    float sum = 0.0;
    float size = resolution.x / 400.0;
    for (int i = 0; i < num; ++i) {
        vec2 position = resolution / 2.0;
	float t = (float(i) + time) / 5.0;
	float c = float(i) * 4.0;
        position.x += sin(8.0 * t + c) * resolution.x * 0.2;
        position.y += sin(t) * resolution.y * 0.48;

        sum += size / length(gl_FragCoord.xy - position);
    }
    gl_FragColor = vec4(0, sum * 0.2, sum, 1);
}