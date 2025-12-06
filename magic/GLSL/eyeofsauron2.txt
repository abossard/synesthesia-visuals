

#ifdef GL_ES
precision highp float;
#endif

uniform vec2 resolution;
uniform float time;

mat2 m = mat2( 0.80,  0.60, -0.60,  0.80 );

vec4 mod289(vec4 x)
{
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x)
{
    return mod289(((x*34.0)+1.0)*x);
}
 
vec4 taylorInvSqrt(vec4 r)
{
    return 1.79284291400159 - 0.85373472095314 * r;
}
 
vec2 fade(vec2 t) {
    return t*t*t*(t*(t*6.0-15.0)+10.0);
}

float cnoise(vec2 P)
{
    vec4 Pi = floor(P.xyxy) + vec4(0.0, 0.0, 1.0, 1.0);
    vec4 Pf = fract(P.xyxy) - vec4(0.0, 0.0, 1.0, 1.0);
    Pi = mod289(Pi); // To avoid truncation effects in permutation
    vec4 ix = Pi.xzxz;
    vec4 iy = Pi.yyww;
    vec4 fx = Pf.xzxz;
    vec4 fy = Pf.yyww;
     
    vec4 i = permute(permute(ix) + iy);
     
    vec4 gx = fract(i * (1.0 / 41.0)) * 2.0 - 1.0 ;
    vec4 gy = abs(gx) - 0.5 ;
    vec4 tx = floor(gx + 0.5);
    gx = gx - tx;
     
    vec2 g00 = vec2(gx.x,gy.x);
    vec2 g10 = vec2(gx.y,gy.y);
    vec2 g01 = vec2(gx.z,gy.z);
    vec2 g11 = vec2(gx.w,gy.w);
     
    vec4 norm = taylorInvSqrt(vec4(dot(g00, g00), dot(g01, g01), dot(g10, g10), dot(g11, g11)));
    g00 *= norm.x;  
    g01 *= norm.y;  
    g10 *= norm.z;  
    g11 *= norm.w;  
     
    float n00 = dot(g00, vec2(fx.x, fy.x));
    float n10 = dot(g10, vec2(fx.y, fy.y));
    float n01 = dot(g01, vec2(fx.z, fy.z));
    float n11 = dot(g11, vec2(fx.w, fy.w));
     
    vec2 fade_xy = fade(Pf.xy);
    vec2 n_x = mix(vec2(n00, n01), vec2(n10, n11), fade_xy.x);
    float n_xy = mix(n_x.x, n_x.y, fade_xy.y);
    return 2.3 * n_xy;
}

float hash( float n )
{
    return fract(sin(n)*43758.5453);
}

float noise( in vec2 x )
{
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f*f*(3.0-2.0*f);
    float n = p.x + p.y*57.0;
    float res = mix(mix( hash(n+  0.0), hash(n+  1.0),f.x), mix( hash(n+ 57.0), hash(n+ 58.0),f.x),f.y);
    return res;
}

float fbm( vec2 p )
{
    float f = 0.0;
    f += 0.50000*noise( p ); p = m*p*2.02;
    f += 0.25000*noise( p ); p = m*p*2.03;
    f += 0.12500*noise( p ); p = m*p*2.01;
    f += 0.06250*noise( p ); p = m*p*2.04;
    //f += 0.03125*noise( p );
    return f/0.9375;
}

float length2( vec2 p )
{
    float ax = abs(p.x);
    float ay = abs(p.y);
    return pow( pow(ax,4.0) + pow(ay,4.0), 1.0/4.0 );
}


void main(void)
{
	vec2 q = gl_FragCoord.xy/resolution.xy; // Dividimos as coordenadas pela largura e altura para termos q de 0.0 a 1.0
	vec2 p = -1.0 + 2.0*q; // O intervalo de p vai de -1.0 a 1.0, p é a posição do pixel na tela
	p.x *= resolution.x/resolution.y; // Razão da largura pela altura para fazermos um círculo, experimente comentar essa linha
	
	float rOrig = sqrt( dot(p, p) ); // Distância do ponto para o centro da tela
	float a = atan( p.y, p.x ); // Ângulo do ponto
	
	vec3 col = vec3(1.0); // Cor do background
	
	float ss = 0.5 + 1.5*sin(2.0*time);
	float anim = 1.0 + 0.1*ss;
	a += anim;
	rOrig *= anim;
	
	// Ruído do background
	//col = vec3(fbm(4.0*p));
	//col = mix(col, vec3(.8, 0.1, 0.0), noise(1.0*p));
	col = cnoise(p)/0.1*vec3(0.96, 0.65, 0.2);
	col *= mix(col, vec3(1.0, 0.4, 0.2), vec3(cnoise(1.*p*(anim))*3.));
	//col = mix(col, 1.0*vec3(0.95, 0.8, 0.2), fbm(7.0*p));
	
	
	if(rOrig < 0.8)
	{
		// Cor do interior do olho
		col = vec3(0.93, 0.16, 0.1); // Cor azulada
		float f = fbm(1.0*p); // fbm é uma função que retorna um tipo específico de ruído e 1.0 é a frequência, experimente mudar
		col = mix(col, vec3(0.63, 0.16, 0.1), f); // mix serve para você mixar as cores, aqui mixamos "col" com uma cor esverdeada
		
		// Cor do tom amarelado ao redor do olho
		if(rOrig > 0.66)
		{
			f = smoothstep( 0.7, 0.8, rOrig );
			col = mix(col, vec3(fbm(40.*p)*3.)*vec3(0.9, 0.6, 0.2), f);
			//f = smoothstep(0.66, 0.8, rOrig); // smoothstep, mais informações em http://www.opengl.org/sdk/docs/manglsl/xhtml/smoothstep.xml
			// = mix(col, vec3(0.9, 0.6, 0.2), f); // mixamos as cores
		}
		
		// Mudamos o ângulo de acordo com um tipo de ruído
		a += 0.02*fbm( 2.0*p ); // 2.0 é a frequência, experimente
		
		// Adicionamos as linhas brancas e curvas ao olho
		f = smoothstep( 0.7, 1.0, fbm( 1.0*vec2(6.0*rOrig, 20.0*a) ) );
		col = mix(col, vec3(0.0), f);
		
		// Adicionamos um certo tom mais dark ao olho, vá lá e experimente
		f = 1.0 - 0.5*smoothstep( 0.4, 0.9, fbm( vec2(10.0*rOrig, 15.0*a) ));
		col *= f;
		
		
		// Damos "volume" ao olho, preste atenção às bordas
		f = 1.0 - 0.5*smoothstep(0.6, 0.9, rOrig);
		col *= f;
		
		// Criamos o círculo preto no centro do olho, experimente
		p = -1.0 + 2.0*q;
		p.x *= 7.;
		p.y *= .6;
		float r = sqrt(dot(p, p) )*anim;
		
		// Criamos o círculo preto no centro do olho, experimente
		//if(r > 0.3)
		//{
			f = 1.0 - smoothstep(0.25, 0.35, r);
			col += vec3(0.95, 0.9, 0.35)*f*2.0;
		//}
		
		// Criamos a elipse central do olho, experimente
		f = smoothstep(0.2, 0.3, r);
		col *= f;
		
		// Adicionamos um reflexo falso ao olho
		p = -1.0 + 2.0*q;
		p.x *= 1.78;
		f = 1.0 - smoothstep( 0.0, 0.06, length( p - vec2(-0.046, 0.2) ) );
		col += vec3(0.9, 0.6, 0.3)*f*1.9;
		
		// Tiramos o aliasing das bordas com o background, experimente comentar as linhas abaixo
		f = smoothstep(0.65, 0.8, rOrig);
		col = mix(col, vec3(fbm(40.*p)*3.)*vec3(1.0, 0.6, 0.2), 1.0*f);
	}
	
	gl_FragColor = vec4(col, 1.0);	
}