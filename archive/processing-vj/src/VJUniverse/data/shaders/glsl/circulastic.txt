#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

#define CIRCLE_STROKE_WIDTH  0.1
#define CIRCLE_RADIUS        0.3
#define MODULATION 	     10.0

void main( void ) {

	float aspectRatio = resolution.x / resolution.y;
	
	vec2 center = vec2( 0.5, 0.5 );
	center.x += 0.25 * cos( 0.5 * time ) * aspectRatio;
	center.y += 0.25 * sin( 0.5 * time );
	
	vec2 unitPosition = ( gl_FragCoord.xy / resolution.xy ) - center;
	unitPosition.x *= aspectRatio;
	
	vec2 unitMouse = mouse - center;
	unitMouse.x *= aspectRatio;
	
	vec3 color = vec3( 0.0, 0.0, 0.0 );
	
	vec2 distanceToCenterSq = unitPosition * unitPosition;
	float distanceToCenterSqAdd = distanceToCenterSq.x + distanceToCenterSq.y;
	float distanceToCenter = sqrt( distanceToCenterSqAdd );
	distanceToCenter = fract( 10.0 * distanceToCenter );
	
	vec2 mouseDelta = unitMouse - unitPosition;
	vec2 distanceToMouseSq = mouseDelta * mouseDelta;
	float distanceToMouseSqAdd = distanceToMouseSq.x + distanceToMouseSq.y;
	float distanceToMouse = sqrt( distanceToMouseSqAdd );
	distanceToMouse = fract( 10.0 * distanceToMouse );
	
	float avDistance = distanceToCenter * distanceToMouse;
	avDistance *= MODULATION * ( 0.5 * sin( time ) + 1.0 );
	avDistance = fract( avDistance );
	
	float stroke = CIRCLE_RADIUS - CIRCLE_STROKE_WIDTH;
	if( avDistance < CIRCLE_RADIUS && avDistance > stroke ) {
		float r = clamp( 10.0 * distanceToCenterSqAdd, 0.0, 1.0 );
		float g = clamp( 1.0 * distanceToMouseSqAdd, 0.0, 1.0 );
		float b = clamp( 10.0 * avDistance * avDistance, 0.0, 1.0 );
		color = vec3( r, g, b );
	}
	
	gl_FragColor = vec4( color, 1.0 );
	
}