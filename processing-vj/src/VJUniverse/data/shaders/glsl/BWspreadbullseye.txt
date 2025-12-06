#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float rings = 4.0; //Para que entren 4 anillos verticalmente
float b = 0.0005;//Radio de los bordes entre los límites de los anillos

void main() {
	
	vec2 position = ( gl_FragCoord.xy / resolution.xy );//Convierte nuestras coordenadas en (0..1, 0...1)
        float aspect = resolution.x / resolution.y;
	position.x *= aspect;
	float dist = distance(position, vec2(aspect/2., 0.5));//dist=Distancia del centro al pixel
	float mr=0.5;//sqrt((aspect*aspect+1.)*0.25); //Radio maximo, en este caso es la mitad de la altura.
	float conv=(rings*2.+1.)/mr;
	//transportamos dist a otro sistema real(donde vale v), donde cada entero representa el límite entre dos anillos.
	float v=dist*conv-time;
	float ringr=floor(v);//ringr es el borde del anillo mas grande que no supera a dist
	//ahora buscamos el anillo mas cercano(simulando round) y lo llevamos al sistema original
	//Luego hacemos smoothstep de acuerdo a cuan lejos estamos del anillo mas cercano
	float color=smoothstep(-b, b, abs(dist- (ringr+float(fract(v)>0.5)+time)/conv) );
	if(mod(ringr,2.)==1.)
		color=1.-color;//si estamos del otro lado, invertimos el color
	gl_FragColor = vec4( color, color, color, 1.0 );//Para implementar otros pares de colores usar mix()

}