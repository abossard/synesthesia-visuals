#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// playing around with ray marching distance fields and lighting - @P_Malin
// forked to add a 'thanks!' for writing educational, readable code! - @danbri

struct C_Ray
{
	vec3 vOrigin;
	vec3 vDir;
};

struct C_HitInfo
{
	float fDistance;
	float fObjectId;
	vec3 vPos;
};
	
void GetCameraRay( out C_Ray ray)
{	
	vec2 vUV = ( gl_FragCoord.xy / resolution.xy );
	vec2 vViewCoord = vUV * 2.0 - 1.0;
	
	float fRatio = resolution.x / resolution.y;
	
	vViewCoord.y /= fRatio;

	ray.vOrigin = vec3(0.0, 0.0, 0.0);
	ray.vDir = normalize( vec3(vViewCoord, 1.0) );
}

vec2 DistCombineUnion( const in vec2 v1, const in vec2 v2 )
{
	vec2 result = v2;
	if(v1.x < v2.x)
		return v1;
	else
		return v2;
}

float GetDistanceSphere( const in vec3 vPos, const in vec3 vSphereOrigin, const in float fSphereRadius )
{
	return length(vPos - vSphereOrigin) - fSphereRadius;
}

float GetDistancePlane( const in vec3 vPos, const in vec3 vPlaneNormal, const in float fPlaneDist )
{
	return dot(vPos, vPlaneNormal) + fPlaneDist;
}

float GetDistanceBumpyFloor( const in vec3 vPos, const in float fHeight )
{
	return vPos.y - fHeight + (sin((vPos.x + time) * 10.0) * 0.01 + 0.01) + (sin((vPos.z) * 10.0) * 0.01 + 0.01);
}


vec2 GetDistanceScene( const in vec3 vPos )
{
	vec2 vDistPlane1 = vec2(GetDistanceBumpyFloor( vPos, -1.0 ), 1.0);
	vec2 vDistSphere1 = vec2(GetDistanceSphere( vPos, vec3( 1.75 + sin(time), -0.25, 5.0 + cos(time)), 0.75 ), 2.0);
	vec2 vDistSphere2 = vec2(GetDistanceSphere( vPos, vec3(-1.75 - sin(time), -0.25, 5.0 - cos(time)), 0.75 ), 3.0);
	
	vec2 vResult = DistCombineUnion(vDistSphere1, vDistSphere2);
	vResult = DistCombineUnion(vResult, vDistPlane1);
	return vResult;
}

vec3 GetSceneNormal( const in vec3 vPos )
{
	float fDelta = 0.001;
	
	float fDx = GetDistanceScene( vPos + vec3(fDelta, 0.0, 0.0) ).x - GetDistanceScene( vPos + vec3(-fDelta, 0.0, 0.0) ).x;
	float fDy = GetDistanceScene( vPos + vec3(0.0, fDelta, 0.0) ).x - GetDistanceScene( vPos + vec3(0.0, -fDelta, 0.0) ).x;
	float fDz = GetDistanceScene( vPos + vec3(0.0, 0.0, fDelta) ).x - GetDistanceScene( vPos + vec3(0.0, 0.0, -fDelta) ).x;
	
	vec3 vNormal = vec3( fDx, fDy, fDz );

	return normalize( vNormal );
}

void Raymarch( const in C_Ray ray, out C_HitInfo result )
{
	const float fMaxDist = 30.0;
	const float fEpsilon = 0.01;
	
	result.fDistance = 0.0;
	result.fObjectId = 0.0;
		
 	for(int i=0;i<128;i++)		
	{
		result.vPos = ray.vOrigin + ray.vDir * result.fDistance;
		vec2 vSceneDist = GetDistanceScene( result.vPos );
		if(vSceneDist.x <= fEpsilon)
		{
			result.fObjectId = vSceneDist.y;
			break;
		}
		
		result.fDistance += vSceneDist.x;
		
		if(result.fDistance > fMaxDist)
		{
			result.vPos = ray.vOrigin + ray.vDir * result.fDistance;
			result.fDistance = fMaxDist;
			result.fObjectId = 0.0;
			break;
		}
	}

}

vec3 GetObjectDiffuse( in float fObjId, in vec3 vPos )
{
	if(fObjId < 0.5)
	{
		return vec3(0.3, 0.8, 0.9);
	}

	if(fObjId < 1.5)
	{
		float fBlend = mod(floor(fract(vPos.x + time) *2.0) + floor(fract(vPos.z) * 2.0), 2.0);
		return vec3(1.0,0.0, 0.0) * fBlend + vec3(0.0,0.0, 1.0) * (1.0 - fBlend);
	}
		
	return vec3( mod(fObjId, 2.0), mod(fObjId / 2.0, 2.0), mod(fObjId/4.0, 2.0));
}

vec3 GetSkyGradient( const in vec3 vDir )
{
	float fBlend = vDir.y * 0.5 + 0.5;
	return vec3(0.0, 0.0, 1.0) * fBlend + vec3(0.4, 1.0, 1.0) * (1.0 - fBlend);

}

float GetShadow( const in C_Ray ray, const in C_HitInfo intersection, const in vec3 vLightDir, const in float fLightDistance )
{
	float fSepration = 0.1;
	C_Ray shadowRay;
	shadowRay.vDir = vLightDir;
	shadowRay.vOrigin = intersection.vPos + shadowRay.vDir * fSepration;

	C_HitInfo shadowIntersect;
	Raymarch(shadowRay, shadowIntersect);
			
	if((shadowIntersect.fDistance >= 0.0) && (shadowIntersect.fDistance <= fLightDistance))
	{
		return 0.0;
	}
	
	return 1.0;
	
}

float Schlick4( const in vec3 vNormal, const in vec3 vView, const in float fR0)
{
	float fDot = dot(vNormal, -vView);
	fDot = max((1.0 - fDot), 0.0);
	float fDot2 = fDot * fDot;
	float fDot4 = fDot2 * fDot2;
	return fR0 + (1.0 - fR0) * fDot4;
}

vec3 GetLightPos()
{
	return vec3(0.0 + sin(time), 1.0 + cos(time * 1.231), 5.0);
}

vec3 GetLightCol()
{
	return vec3(3.0, 3.0, 1.0);
}

vec3 GetDiffuseLight(const in C_Ray ray, const in C_HitInfo intersection, const in vec3 vLightDir, const in vec3 vNormal)
{
	
	float fDiffuseIntensity = max(0.0, dot(vLightDir, vNormal));
	
	return GetLightCol() * fDiffuseIntensity;
}

vec3 GetPhong(const in C_Ray ray, const in C_HitInfo intersection, const in vec3 vLightDir, const in vec3 vNormal)
{	
	vec3 vHalf = normalize(vLightDir - ray.vDir);
	float fNdotH = max(0.0, dot(vHalf, vNormal));

	return GetLightCol() * pow(fNdotH, 100.0) * 5.0;
}

vec3 GetAmbientLight(const in vec3 vNormal)
{
	return GetSkyGradient(vNormal);
	//return vec3(0.1, 0.3, 0.5);
}

float GetAmbientOcclusion(const in C_Ray ray, const in C_HitInfo intersection, const in vec3 vNormal)
{
	vec3 vPos = intersection.vPos;

	float fAo = 1.0;
	
	float fDist = 0.0;
	for(int i=0; i<5; i++)
	{
		fDist += 0.1;

		vec2 vSceneDist = GetDistanceScene(vPos + vNormal * fDist);
		
		fAo *= 1.0 - max(0.0, (fDist - vSceneDist.x) * 0.2 / fDist );
		
	}
	
	return fAo;
}

void ApplyAtmosphere(inout vec3 col, const in C_Ray ray, const in C_HitInfo intersection)
{
	// glare from light
	vec3 vToLight = GetLightPos() - ray.vOrigin;
	float fDot = dot(vToLight, ray.vDir);
	fDot = clamp(fDot, 0.0, intersection.fDistance);
	
	vec3 vClosestPoint = ray.vOrigin + ray.vDir * fDot;
	float fDist = length(vClosestPoint - GetLightPos());
	col += GetLightCol() * 0.1/ (fDist * fDist);

	// fog
	float fFogDensity = 0.015;
	float fFogAmount = exp(intersection.fDistance * -fFogDensity);
	vec3 cFog = vec3(0.5, 0.8, 1.0);
	col = col * fFogAmount + cFog * (1.0 - fFogAmount);


}

vec3 GetSceneColourSimple( const in C_Ray ray )
{
	C_HitInfo intersection;
	Raymarch(ray, intersection);
		
	vec3 cScene;
	
	if(intersection.fObjectId < 0.5)
	{
		cScene = GetSkyGradient(ray.vDir);
	}
	else
	{
		
		vec3 vNormal = GetSceneNormal(intersection.vPos);
	
		vec3 vLightPos = GetLightPos();
		vec3 vToLight = vLightPos - intersection.vPos;
		vec3 vLightDir = normalize(vToLight);
		float fLightDistance = length(vToLight);

		float fShadowFactor = GetShadow( ray, intersection, vLightDir, fLightDistance );
		vec3 vDiffuseLight = GetDiffuseLight( ray, intersection, vLightDir, vNormal ) * fShadowFactor;
		float fAmbientOcclusion = GetAmbientOcclusion(ray, intersection, vNormal);
		vec3 vAmbientLight = GetAmbientLight(vNormal) * fAmbientOcclusion;

		vec3 cMatDiffuse = GetObjectDiffuse(intersection.fObjectId, intersection.vPos);
		vec3 vDiffuseReflection = cMatDiffuse * (vDiffuseLight + vAmbientLight);
		
		vec3 vSpecularReflection = vec3(0.0);
		
		vSpecularReflection += GetSkyGradient(reflect(ray.vDir, vNormal));
		
		vSpecularReflection += GetPhong( ray, intersection, vLightDir, vNormal ) * fShadowFactor;
		
		float fR0 = 0.25;
	
		float fFresnel = Schlick4(vNormal, ray.vDir, fR0);
		cScene = vDiffuseReflection * (1.0 - fFresnel) + vSpecularReflection * fFresnel;
	
	
	}
	
	ApplyAtmosphere(cScene, ray, intersection);

	return cScene;
}



vec3 GetSceneColour( const in C_Ray ray )
{
	C_HitInfo intersection;
	Raymarch(ray, intersection);
		
	vec3 cScene;
	
	if(intersection.fObjectId < 0.5)
	{
		cScene = GetSkyGradient(ray.vDir);
	}
	else
	{		
		vec3 vNormal = GetSceneNormal(intersection.vPos);
	
		vec3 vLightPos = GetLightPos();
		vec3 vToLight = vLightPos - intersection.vPos;
		vec3 vLightDir = normalize(vToLight);
		float fLightDistance = length(vToLight);

		float fShadowFactor = GetShadow( ray, intersection, vLightDir, fLightDistance );
		vec3 vDiffuseLight = GetDiffuseLight( ray, intersection, vLightDir, vNormal ) * fShadowFactor;
		float fAmbientOcclusion = GetAmbientOcclusion(ray, intersection, vNormal);
		vec3 vAmbientLight = GetAmbientLight(vNormal) * fAmbientOcclusion;
	
	
		vec3 cMatDiffuse = GetObjectDiffuse(intersection.fObjectId, intersection.vPos);
		vec3 vDiffuseReflection = cMatDiffuse * (vDiffuseLight + vAmbientLight);
		vec3 vSpecularReflection = vec3(0.0);
		{
			float fSepration = 0.1;
			C_Ray reflectRay;
			reflectRay.vDir = reflect(ray.vDir, vNormal);
			reflectRay.vOrigin = intersection.vPos + reflectRay.vDir * fSepration;
				
			vSpecularReflection += GetSceneColourSimple(reflectRay);
			
		}
		
		vSpecularReflection += GetPhong( ray, intersection, vLightDir, vNormal ) * fShadowFactor;
		
		float fR0 = 0.25;
		float fFresnel = Schlick4(vNormal, ray.vDir, fR0);
		cScene = vDiffuseReflection * (1.0 - fFresnel) + vSpecularReflection * fFresnel;
	}
	
	ApplyAtmosphere(cScene, ray, intersection);
	
	return cScene;
}

void main( void ) 
{
	C_Ray ray;
	
	GetCameraRay(ray);
	
	vec3 cScene = GetSceneColour( ray );
	
	float fExposure = 1.5;
	vec3 cFinal = cScene * fExposure;
	cFinal = cFinal / (1.0 + cFinal);

	gl_FragColor = vec4( cFinal, 1.0 );
}
