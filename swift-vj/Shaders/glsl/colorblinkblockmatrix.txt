#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

//Cube Control vars
float spacing = 5.;
float count = 5.;

float roundBox( vec3 p)
{
	vec3 b = vec3(1.);
	return length(max(abs(p)-b,0.0))-0.5;
}

float opUnion(float d1, float d2)
{
	return min(d1, d2);
}

float boundingBox(vec3 p)
{
	vec3 b = vec3(spacing/2.*(count))-0.5;
	return length(max(abs(p)-b,0.0))-0.5;
}

float grid(vec3 p)
{
	float s = 1.0;
	float halfSpacing = spacing/2.;
	if (boundingBox(p) < 0.0001)
	{
		s= roundBox(vec3(mod(p.x+halfSpacing, spacing)-halfSpacing,
						 mod(p.y+halfSpacing, spacing)-halfSpacing,
						 mod(p.z+halfSpacing, spacing)-halfSpacing));
	}
	return s;
}

vec2 rotate(vec2 p, float a)
{
	return vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
}

vec3 calcNormal(vec3 p)
{
	vec3 n;
	
	
	float e = 0.08;
	n.x = grid(vec3(p.x + e, p.y, p.z));
	n.y = grid(vec3(p.x, p.y + e, p.z));
	n.z = grid(vec3(p.x, p.y, p.z + e));
	
	/* --More Corect, but slower--
	float e = 0.001;
	n.x = grid(vec3(p.x + e, p.y, p.z)) - grid(vec3(p.x - e, p.y, p.z));
	n.y = grid(vec3(p.x, p.y + e, p.z)) - grid(vec3(p.x, p.y - e, p.z));
	n.z = grid(vec3(p.x, p.y, p.z + e)) - grid(vec3(p.x, p.y, p.z - e));
	*/
	
	return normalize(n);

}

//get a cube index to highlight
vec3 chooseIndex(float offset)
{
	float t = (time+offset)*count;
	float tOverCount = t/count;
	
	int xChoice = int(mod(t, count));
	int yChoice = int(mod(tOverCount, count));
	int zChoice = int(mod((tOverCount)/count, count));

	return vec3( xChoice, yChoice, zChoice );
}

//get the index of the cube that p intersects with
vec3 cubeIndex(vec3 p)
{
	float halfSpacing = spacing/2.;
	
	int x = int( (p.x/spacing) - count/2. ) + int(count-1.);
	int y = int( (p.y/spacing) - count/2. ) + int(count-1.);
	int z = int( (p.z/spacing) - count/2. ) + int(count-1.);

	return vec3(x,y,z);
}

void main(void)
{
	spacing= spacing/1.0+sin(time)*1.5;
	
	vec2 uv = -1.0 + 2.0*gl_FragCoord.xy / resolution.xy;
	
	float pan = 0.1 + (mouse.x*200. / resolution.y - 0.5) * -3.14;
	
	vec3 CAM_UP = vec3(0.0, 1.0, 0.0);
	
	vec3 CAM_POS = vec3(15.0, 15.0, -30.0);
	vec3 CAM_LOOKPOINT = vec3(0.0, 0.0, 1.0);

	CAM_POS.xz = rotate(CAM_POS.xz, pan);
	
	
	vec3 lookDirection = normalize(CAM_LOOKPOINT - CAM_POS);
	vec3 viewPlaneU = cross(CAM_UP, lookDirection);
	vec3 viewPlaneV = cross(lookDirection, viewPlaneU);
	
	vec3 viewCenter = CAM_POS + lookDirection;
	vec3 fragWorldPos = viewCenter + (uv.x * viewPlaneU * resolution.x/resolution.y) + (uv.y * viewPlaneV);
	vec3 fragWorldToCamPos = normalize(fragWorldPos - CAM_POS);

	vec3 LIGHT_DIR = normalize(CAM_POS);
	vec3 LIGHT_COL = vec3(1.8);
	
	vec3 col = vec3(0.0);
	
	float f = 0.0;
	float s = 0.01;
	vec3 p = CAM_POS + fragWorldToCamPos*f;
	
	for (int i = 0; i < 65; i++)
	{
		if ( s < 0.01 )
		{
			vec3 cIndex = cubeIndex(p);
			col = normalize(cIndex)/2.;
			
			if (cIndex == chooseIndex(0.0) || cIndex == chooseIndex(5.5) 
			   || cIndex == chooseIndex(12.3))
			{
				col = vec3(0.9);
			}
			
			col = vec3(0.2)+col*LIGHT_COL*max(0.0,(dot(LIGHT_DIR,(calcNormal(p)))));
		}
		
		s=grid(p);
		f+=s;
		p = CAM_POS + fragWorldToCamPos * f;
	}
	
	gl_FragColor = vec4(col, 1.0);
}