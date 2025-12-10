/*

	Traced Tunnel
	-------------

	This initially started as a simple textured square tube, but then I took
	a look at W23's "Past Racer" example and wanted to emulate the awesome
	reflective... pseudo-pathtraced style of that. NuSan also has a really
	nice example on here, based on the same, that provided inspiration as well --
    That one is well worth a look as the coloring is beautiful.

	I wrote this from scratch, but have used elements from the aforementioned
    examples. I love the camera "tick" function in Nusan's example, so stuck 
    with that, and I like the way W23 gave certain random tiles more of an 
    opaque factor than others, so continued with that theme.

	In regard to my own elements, I abandoned the box formula for four simple
	plane traces, since I needed a bit more control. I've also put in squarish 
    polar mapped textures to give more of a wrapped feel. Other than that, I 
    haven't brought anything particularly new to the table.

	I initially went to the trouble to raytrace octagonal walls, only to 
    discover that light bounces off rectangular walls in a cleaner -- and more 
    interesting --  way, so reverted back to the original arrangement.

    This contains elements of path tracing, but I won't go as far as to call it
	that, so I'll simply call it a reflective ray scattering demonstration. I've 
    basically patched in code here and there, but here's a quick explanation as 
    to what's happening:

    I think most know how to raytrace a square tunnel with a single pass or 
    more -- Raytrace, retrieve the hit point, then use that to color the pixel.
    With extra reflective passes, you calculate the reflected unit direction 
    ray at the hit point (ref = relflect(r, n)), raytrace to the surface again 
    from there, retrieve the color at the new hit point, then combine it with 
    the previous color -- How you do that is up to you; addition, mixing, or 
    whatever you choose. If you want more bounces, continue the process. Simple.
    
    However, pure reflections don't really reflect (no pun intended) the way real 
    surfaces behave. As you could imagine, they're rough at a microscopic level,
	so don't perfectly reflect rays in one direction; There's some randomness
	to it. Essentially, rough surfaces scatter the reflective rays in a way that 
    give the appearance of graded opaqueness, and smoother polished surfaces look 
    more reflective. There's more to it, but that's the gist of it.

    To put this into practice, you simply add some randomness to the reflected 
    ray, which is based on the roughness of the surface. In a similar way to W23 
    and NuSan's examples, I've textured square grids to the walls of the tunnel, 
    then randomly assigned roughness levels to each. This causes each grid cell 
    to look opaque, completely reflective, or somewhere in-between. The
    reflected rays on the right-angled geometry gives a see-through impression, 
    but that's not the case.
	

	Inspired largely by the following:

    // The simple renderer is great, but it's the camera work that I love most.
    past racer by jetlag - w23
	https://www.shadertoy.com/view/Wts3W7

    // Simple, but georgeous lighting and colors.
	Corridor Travel - NuSan
    https://www.shadertoy.com/view/3sXyRN

*/


// Pure reflections looks pretty cool, and clean, but lack the subtlety of a
// randomly reflected ray.
// #define PURE_REFLECTION

// Full rotational movement.
//#define CAM_ROTATION

// Camera swing.
#define CAM_SWING

// Depth of field.
#define DEPTH_OF_FIELD

// Motion blur: Temporal blending of samples.
//#define MOTION_BLUR



// Sample number: Higher is better, but slower. Eight is enough. :)
const int sampleNum = 12;


// 2D rotation.
mat2 r2(float a){ return mat2(cos(a), sin(a), -sin(a), cos(a)); }

// Random functions: All based on IQ's originals.

// vec2 to float hash.
float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(425.215, 714.388)))*45758.5453);
}

// vec2 to vec2 hash.
vec2 hash22(vec2 p) {
  return fract(sin(vec2(dot(p, vec2(72.927, 98.283)), dot(p, vec2(41.295, 57.263))))
                  *vec2(43758.5453, 23421.6361));
}

// vec2 to vec3 hash.
vec3 hash23(vec2 p){
    return fract(sin(vec3(dot(p, vec2(12.989, 78.233)), dot(p, vec2(51.898, 56.273)),
                      dot(p, vec2(41.898, 57.263)))) *vec3(43758.5453, 23421.6361, 65426.6357));
}

// Also from NuSan's example. I tried other variations, but
// this just seems to work better.
float tick(float t, float d) {
  
  float m = fract(t/d);
  m = smoothstep(0., 1., m);
  m = smoothstep(0., 1., m);
  return (floor(t/d) + m)*d;
}

// NuSan's cool camera tick function.
float tickTime(float t){ return t*2. + tick(t, 4.)*.25; }


// Camera movement. Adapted from NuSan's example.
void cam(inout vec3 p, float tm, float tTime) {
  
    if (auto_camera > 0.5) {
        // p.xy *= r2(tm/4.);
        // p.xz *= r2(tm/2.);
    
        // #ifdef CAM_SWING
  	     p.xz *= r2(sin(syn_Time*0.15*.3)*.4);
  	     p.xy *= r2(sin(syn_Time*0.15*.1)*2.);
        // #endif
    }

}

vec3 rotateX(vec3 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return vec3(p.x, c*p.y+s*p.z, -s*p.y+c*p.z);
}

vec3 rotateY(vec3 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return vec3(c*p.x-s*p.z, p.y, s*p.x+c*p.z);
}

vec3 rotateZ(vec3 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return vec3(c*p.x+s*p.y, -s*p.x+c*p.y, p.z);
}

// Plane intersection: Old formula, and could do with some tidying up.
// The tiny "9e-7" figure is something I hacked in to stop near plane 
// artifacts from appearing. I don't like it at all, but not a single 
// formula I found deals with the problem. There definitely has to be
// a better way, so if someone knows of a more robust formula, I'd 
// love to use it.
float rayPlane(vec3 ro, vec3 rd, vec3 n, float d){
    rd = rotateZ(rd, rotate_planes*PI);

    float t = 1e8;
    //float retval = 0.; // Inside or outside the object. Not used here.

	float ndotdir = dot(rd, n);
    
	if (ndotdir < 0.){
	
		float dist = (-d - dot(ro, n) + 9e-7)/ndotdir;	// + 9e-7
   		
		if (dist>0. && dist<t){ 
            t = dist; 
            //retval = 1.;
		}
	}
    
    return t;

}

float udBox(in vec2 p, in vec2 b){
	return mix(length(max(abs(p) - b + .1, 0.)) - .1, length(p)-0.5+(max(small_circles, 1.0)-1), min(small_circles, 1.0));
}

// Used for polar mapping various shapes.
float uvShape(vec2 p){
    // Polar mapping a square wall.
    p = abs(p);
    return max(p.x, p.y);
    
    // Mapping hexagon walls.
    //p *= r2(-3.14159/12.);
    //p = abs(p);
    //return max(p.x*.8660254 + p.y*.5, p.y);
    
}

vec4 texMirror(sampler2D samplerIn, vec2 uvIn){
  if (mod(uvIn.x, 2.0) > 1.0){
    uvIn.x = 1.0-uvIn.x;
  }
  if (mod(uvIn.y, 2.0) > 1.0){
    uvIn.y = 1.0-uvIn.y;
  }
  return texture(samplerIn, uvIn);
}

vec4 renderMainImage() {
	vec4 fragColor = vec4(0.0);
	vec2 fragCoord = _xy;

  
    // Aspect correct screen coordinates.
    vec2 uv = (fragCoord - RENDERSIZE.xy*.5)/RENDERSIZE.y;
    

    // Depth of field (DOF) amount, and the DOF distance. In this
    // case, a figure of 3 will bring everything into focus three units 
    // down the tunnel, but camera blur things around it.
    float clarityTime = _pulse(fract(TIME*0.1), 0.1, 0.05);
    float DOF = mix((1.0-syn_Presence)*0.1, 0.001, focused);
    float DOFDist = 3.0-syn_Presence*1.0;
    
    // Global time, and tick time, which in this case is regular time, with
    // a lurching tick on it. I think it's great, but it might not be for
    // those who are prone to motion sickness.
    float tm = syn_BassTime*0.2+TIME*0.1;
    float tickTm = tickTime(tm);
    
    // Initial camera position. The tick time variable gives the camera a
    // slight lurching motion along Z.
    vec3 ca = vec3(0, 0, tickTm);
    
    
    // Initialize the scene color to zero.
     vec3 col = vec3(0);


    // Taking a few samples, which is not much different to standard antialiasing. The main 
    // difference is that you set up your unit direction ray with UV coordinates randomly 
    // sampled around the pixel area. The average of all returned colors gives you a nice 
    // antialiased look... provided you take enough costly samples, of course. In this case, 
    // we're taking just 8 -- Not ideal, but good enough for the purpose of this example.
    for(int j = 0; j<sampleNum; j++) {

        // Pixel offset.
        vec2 offs = hash22(uv + float(j)*74.542 + 35.877) - .5;

        #ifdef MOTION_BLUR
        // Motion blur: Just a simple temporal blending of samples. In case it isn't
        // obvious, you're advancing global time a little with each sample, which results 
        // in frames further in time being blended with the present. You could go 
        // backwards instead, if the idea of looking into the future bothers you. :D
        tm = TIME + float(j)*.05/float(sampleNum);
        tickTm = tickTime(tm);
        #endif
 
        vec3 ro = vec3(0);
        #ifdef DEPTH_OF_FIELD
        // Depth of field. Spreading out the sample, according to screen depth.
        ro.xy += offs*DOF;
        vec3 r = normalize(vec3(_uvc - offs*DOF/DOFDist, FOV+FOV_bump));
        #else
        vec3 r = normalize(vec3(uv - offs/RENDERSIZE.y, 1));
        #endif

        // Camera movement. Rotation, swivle, etc.
        cam(ro, tm, tickTm);
        cam(r, tm, tickTm);
        
        r = rotateX(r, cam_look.y*PI);
        r = rotateY(r, -cam_look.x*PI);

        ro.z += ca.z;

        // Alpha, for blending layers.
        float alpha = 1.;

        // Fog distance.
        float fogD = 1e5;


        // Reflective bounces. Just three here.
        for(int i = 0; i<3; i++) {


            // Tracing the four planes, then determining the closet.
            // I'll tidy this up later.; 
            //
            vec4 pl; // Vector storage for the four planes.
            pl.x = rayPlane(ro, r, vec3(0, 1, 0), 1.); // Bottom.
            pl.y = rayPlane(ro, r, vec3(0, -1, 0), 1.); // Top.
            pl.z = mix(rayPlane(ro, r, vec3(1, 0, 0), 1.), 100.0, flat_space*flat_space); // Left.
            pl.w = mix(rayPlane(ro, r, vec3(-1, 0, 0), 1.), 100.0, flat_space*flat_space); // Right.
           
            // Minimum plane distance.
            float d = min(min(pl.x, pl.y), min(pl.z, pl.w));
    
            // Set the fog distance on the first pass.
            if(i==0) fogD = d;

            // Hit position.
            vec3 p = ro + r*d;
            // Determine the UV coordinates for texturing, and the normal,
            // for lighting and other things.
            //
            // Set the normal and UVs to the bottom or top planes.
            vec3 n = vec3(0,  pl.x<pl.y? 1 : -1, 0);
            vec2 tuv = p.xz + vec2(0, n.y);

            // If we've hit the side walls instead, change the normal and 
            // UVs accordingly.
            if(min(pl.z, pl.w)<min(pl.x, pl.y)) {
             
                n = vec3(pl.z<pl.w? 1 : -1, 0, 0);
                
                tuv = p.yz + vec2(n.x, 0); // Left walls.
            }

            // Texture scaling for texturing.
            float sc = 12.0*pixelation*pixelation;
            tuv *= sc;
            tuv += sc*0.5;
            
            
            // Sample color.
            vec3 sampleCol = vec3(1);
            
            // Grid square ID and local coordinates.
            vec2 id = floor(tuv);
            tuv -= id + .5;
            
            float sqSize = 0.5+0.5*sin(syn_BPMSin2+p.z*0.4);
             /////
            // Use the UV coordinates to create a whitish colored rounded box grid.
            float patDist = udBox(tuv, vec2(.2+sqSize*0.7));
            // Use the square grid shape for shading.
            float sh = clamp(.5 - patDist/.2, 0., 1.);
       
            // Subtle coloring.
            vec3 sqCol = .85 + .3*cos((hash21(id + .2)*2.)*6.2831 + vec3(0, 1, 2));
            sampleCol = mix(vec3(0), sqCol*sh, (1. - smoothstep(0., .005, patDist)));
 
            ////
            // Perform a squarish polar mapping (of sorts), read in to some textures, then
            // color them up, etc.
            //
            // Quantized squarish polar mapping.
            const vec2 txSc = vec2(2, 1./2.); // Texture scale.
            vec3 ip3 = (floor(p*sc) + .0)/sc; // Quantizing... as opposed to continuous values.
            float ang = atan(ip3.x, ip3.y)/6.2831; // Angle of grid cell from the tube center.
            vec2 tnuv = vec2(uvShape(ip3.xy)*ang*txSc.x, ip3.z*txSc.y); // Square polar UVs.
            //
            // Smooth squarish polar mapping.
            const vec2 txSc2 = vec2(1, 1./4.); // Texture scale.
    		vec3 p3 = mix(p, (floor(p*sc) + .0)/sc, .8); // Slightly smooth quantized values.
            float ang2 = atan(p3.x, p3.y)/6.2831; // Angle of grid cell from the tube center.
            vec2 tnuv2 = vec2(uvShape(p3.xy)*ang2*txSc2.x, p3.z*txSc2.y);  // Square polar UVs.

            // Reading the texel values, and manipulating a bit. Note the squaring of the value,
            // (tx *= tx) which is a rough sRGB to linear conversion.
            vec3 tx = texture(image48, fract(tnuv - .5 - vec2(syn_MidHighTime*0.5/(sc)/2., 0)*media_scrolling)).xyz; tx *= tx;

            tx = mix(tx, vec3(dot(tx, vec3(.299, .587, .114))), .75);
            tx = smoothstep(.1, .55, tx);
            // tx = mix(tx, vec3(0.0, 0.75, 1.0), tnuv2.x);
            vec3 tx2 = vec3(0.0);
            if (_isMediaActive()){
                tx2 = texMirror(syn_Media, tnuv2 - .5 - vec2(syn_HighTime*0.5/(sc)/2., 0)*media_scrolling).xyz;
                tx2 = smoothstep(.18, .5, tx2);//*vec3(1.1, 1, .9); 
            } else {
                tx2 = texture(image3, fract(tnuv2 - .5 - vec2(syn_HighTime*0.5/(sc)/2., 0)*media_scrolling)).xyz; tx2 *= tx2;
                tx2 = smoothstep(.18, .5, tx2);//*vec3(1.1, 1, .9); 
            }
            // col = tx;
            // break;
            
            // Apply the textures to the sample color. 
            sampleCol *= tx*tx2*3.*mix(1.0, syn_HighHits, auto_flasher*(0.5+0.5*sin(length(p.xz)*0.25+syn_BassTime*0.4))); 
            
            sampleCol += sampleCol*500.0*scan_x*_pulse(p.x*0.1, scan_x, 0.1);

            sampleCol = mix(sampleCol, 20.0*sampleCol.brg, scan_z*_pulse(1.0-p.z*0.1+ro.z*0.1, scan_z, 0.1));

            // Some fakish point lighting. 
            // Light direction vector. The light is 3 units up from the camera, which
            // coincides with the depth of field distance.
            vec3 ld = normalize(ca + vec3(0, 0, 3) - p);
            float dif = max(dot(ld, n), 0.); // Diffuse.
            float spe = pow(max(dot(reflect(ld, -n), -r), 0.), 8.); // Specular.
            float fre = pow(max(1. - abs(dot(r, n))*.5, 0.), 1.); // Fresnel.
            
            sampleCol *= (dif + vec3(1, .9, .7)*spe*4. + vec3(.5, .7, 1)*fre);
                
            
            // W23's chromatic effect. It looks good in his artsy black and white
            // example, but there's too much color here for it to be effective.
            
            // float patDistL = udBox(tuv - vec2(.05, 0), vec2(.4));
            // float patDistR = udBox(tuv - vec2(0, .05), vec2(.4));
            // sampleCol *= step(0., -vec3(patDistL, patDist, patDistR) - .025);
            
            
            // Applying some fog.
            sampleCol *= vec3(1.35+syn_BassLevel*2.5, 1.35, 1.35)/(1. + fogD*fogD*.05);
         

            
            // Add the sample color to overall accumulated scene color.
            //col += sampleCol*alpha*fre*exp(-fogD*.2);
            col += sampleCol*alpha*fre;
            
            // Reduce the alpha factor by a bit and mix in the Fresnel factor as well.
            alpha *= 0.9;

   
            // Calculate the reflection vector for the next pass.
            
            #ifdef PURE_REFLECTION
            
            // Pure reflection overide. It's definitely cleaner, but less interesting.
            r = reflect(r,n);
            
            #else
            
            // Just some randomized reflection, based on certain heuristics. There are
            // various ways to create a randomized relective vector, but it's mainly
            // common sense. 
            float h = hash21(id)*smoothstep(0., .005, -patDist + .15);
          
            // Purely reflected vector.
            vec3 ref = reflect(r,n);
            // Random vector.
            r = normalize(hash23(uv + float(j)*74.524 + float(i)*35.712) - .5);
            // Mixing the purely reflected vector with the random vector according
            // to some heuristics. In this case, a random opaque factor for the 
            // tile, the tile shade, pattern border, fog... I made it up as I 
            // went along. :)
            r = normalize(mix(ref, r, (hash21(tuv)*.0 + h*.1*sh)*exp(-fogD*.05)));
            
            // Ensuring random reflection. I normally use other logic, but it works
            // well enough in W23 and Nusan's examples, so it'll do. :)
            r = dot(r, n)<0.? -r : r;
            #endif

            // Advance the position to the new hit point. Also be sure to bump
            // the ray off the surface to avoid self collision... If I had a
            // dollar for every time I've forgotten to do this... :)
            ro = p + n*.0011;
        }

    }
    
    // Divide by the total number of samples.
    col /= float(sampleNum);
    

    // Use this to tone down highlight extrema... However, if you like to live on
    // the edge and burn your eyes, then leave it as is. :D
    //col = 1. - exp(-col);
    
    
    // Gamma correction and screen presentation.
    fragColor = vec4(pow(max(col, 0.), vec3(0.4545)), 1);
    
	return fragColor; 
 } 




vec4 renderMain(){
	if(PASSINDEX == 0){
		return renderMainImage();
	}
}