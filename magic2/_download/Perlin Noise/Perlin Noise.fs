
/*{
	"DESCRIPTION": "",
	"CREDIT": "",
	"ISFVSN": "2",
      "CATEGORIES": [
        "Noise"
      ],
	"INPUTS": [
		{
			"NAME": "scale",
			"TYPE": "float",
			"DEFAULT": 0.5,
			"MIN": 0.0,
			"MAX": 1.0
		}
	]
	
}*/

vec4 permute(in vec4 x){
    return mod(x*x*34.+x,289.);
    
}
float snoise(vec3 v){
  const vec2 C = vec2(0.16666666666,0.33333333333);
  const vec4 D = vec4(0,.5,1,2);
  vec3 i  = floor(C.y*(v.x+v.y+v.z) + v);
  vec3 x0 = C.x*(i.x+i.y+i.z) + (v - i);
  vec3 g = step(x0.yzx, x0);
  vec3 l = (1. - g).zxy;
  vec3 i1 = min( g, l );
  vec3 i2 = max( g, l );
  vec3 x1 = x0 - i1 + C.x;
  vec3 x2 = x0 - i2 + C.y;
  vec3 x3 = x0 - D.yyy;
  i = mod(i,289.);
  vec4 p = permute( permute( permute(
	  i.z + vec4(0., i1.z, i2.z, 1.))
	+ i.y + vec4(0., i1.y, i2.y, 1.))
	+ i.x + vec4(0., i1.x, i2.x, 1.));
  vec3 ns = .142857142857 * D.wyz - D.xzx;
  vec4 j = -49. * floor(p * ns.z * ns.z) + p;
  vec4 x_ = floor(j * ns.z);
  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = floor(j - 7. * x_ ) * ns.x + ns.yyyy;
  vec4 h = 1. - abs(x) - abs(y);
  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );
  vec4 sh = -step(h, vec4(0));
  vec4 a0 = b0.xzyw + (floor(b0)*2.+ 1.).xzyw*sh.xxyy;
  vec4 a1 = b1.xzyw + (floor(b1)*2.+ 1.).xzyw*sh.zzww;
  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);
  vec4 norm = inversesqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;
  vec4 m = max(.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.);
  return .5 + 12. * dot( m * m * m, vec4( dot(p0,x0), dot(p1,x1),dot(p2,x2), dot(p3,x3) ) );
}


void main()	{
	vec2 pos = isf_FragNormCoord.xy - 0.5;
    pos *= 20. * scale;
    float noise = snoise(vec3(-pos.x, pos.y, TIME));
	gl_FragColor = vec4(vec3(noise), 1.0);
}
