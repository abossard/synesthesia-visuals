/*

The Chaos Factory

GPU implementation of Erin Catto's Box2D-lite (https://github.com/erincatto/box2d-lite, MIT License)

Broad phase and revolute joints

Never got any stacking to work, even when accumulating impulses, even across multiple frames 
That's why the demo is as little static as possible...
You can add/push/pull boxes with the top-left selection!

Special thanks to the shadertoy community :
- Dave_Hoskins for its hash functions
- iq for its sdf functions (and many other resources)
- FabriceNeyret2 and P_Malin for text rendering (and many other resources)
- s23b for blueprint-like rendering (please check https://www.shadertoy.com/view/4tySDW)

*/


// Rendering

float sdBox(vec2 p, vec2 b) // https://www.youtube.com/watch?v=62-pRVZuS5c
{
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}

float sdSegment(vec2 p, vec2 a, vec2 b) // https://www.shadertoy.com/view/3tdSDj
{
    vec2 ba = b-a;
    vec2 pa = p-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    
    return length(pa-h*ba);
}

float sdTriangle(  in vec2 p, in float r ) // https://www.shadertoy.com/view/Xl2yDW
{
    const float k = sqrt(3.0);
    p.x = abs(p.x);
    p -= vec2(0.5,0.5*k)*max(p.x+k*p.y,0.0);
    p.x =  p.x - clamp(p.x,-r,r);
    p.y = -p.y - r*(1.0/k);
    return length(p)*sign(p.y);
}

// modified version of sdSegment for a dotted segment
float sdDotted(vec2 p, vec2 a, vec2 b, int sep) // sep is number of separation
{
    float n = 2.*float(sep)+1., dh = 1./n;
    vec2 pa = p-a, ba = b-a;
    
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    float rh = fract(n*h/2.);
    if(rh > .5001)
    {
        float closest_h = floor(n*h)*dh; 
        return min(length(pa-closest_h*ba), length(pa-(closest_h+dh)*ba));
    }
    return length(pa-h*ba);
}

float sdArrow(vec2 p, float l)
{
    return min(sdTriangle(p, .03), sdSegment(p, vec2(0, -l), vec2(0))-0.004);
}

float sdDottedArrow(vec2 p, float l, int sep)
{
    return min(sdTriangle(p, .03), sdDotted(p, vec2(0, -l), vec2(0), sep)-0.004);
}

float sdBody(vec2 p, Body b)
{
    return sdBox(rot(-b.ang)*(p-b.pos), b.size);
}

float sdJoint(vec2 p, Joint j, sampler2D buff)
{
    // load associated bodies
    Body b0 = loadBody(buff, j.b0_id);
    Body b1 = loadBody(buff, j.b1_id);

    // Have the dotted line relative to the joint's softness
    float d = FLT_MAX;
    vec2 off = rot(b0.ang)*j.loc_anc0;
    float sep_size = j.softness * .003;
    int sep0 = int(length(off)/sep_size*.5);
    int sep1 = int(length(b1.pos-b0.pos-off)/sep_size*.5);
    if(b0.inv_mass != 0.) d = min(d, sdDotted(p, b0.pos, b0.pos+off, sep0)-0.003);
    if(b1.inv_mass != 0.) d = min(d, sdDotted(p, b1.pos, b0.pos+off, sep1)-0.003);
    
    return d;
}

float drawChar(vec2 char_p, int char_id) // https://www.shadertoy.com/view/llySRh
{
    if (char_p.x < .0 || char_p.x>1. || char_p.y<0. || char_p.y>1.) return 0.;
    vec2 p = char_p/16.; 
    return textureGrad(iChannel2, p + fract(vec2(char_id,15-char_id/16)/16.), dFdx(p), dFdy(p)).x;
}

float drawCharIt(vec2 char_p, int char_id) // https://www.shadertoy.com/view/ldfcDr
{
    char_p.x += (1.-char_p.y)*0.3f;
    return drawChar(char_p, char_id);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    fragColor = vec4(0);

    float px = rcp(min(iResolution.x, iResolution.y));
    vec2 uv = VIEW(fragCoord);
    
    Globals g = loadGlobals(iChannel0);
    
    // Bodies and background
    float body_d = FLT_MAX;
    float outline_d = FLT_MAX; // to get outline inside overlapping moving boxes
    int closest_b_id = -1;
    Body closest_b = loadBody(iChannel0, 0);
    for(int b_id = 0; b_id < g.n_body; b_id++)
    {
        if(isInvisibleBody(b_id)) continue;
        Body b = loadBody(iChannel0, b_id);
        if(dot2(uv-b.pos) > dot2(b.size)) continue; // helps framerate a bit with lots of bodies
        float b_d = sdBody(uv, b);
        if(b_d < body_d)
        {
            body_d = b_d;
            closest_b = b;
            closest_b_id = b_id;
        }
        
        outline_d = min(abs(outline_d), abs(b_d));
    }
    
    vec3 col = vec3(0, .35, .58) - .07 * saturate(dot2(uv*.5)); // background
    if(body_d > 0.0)
    {
        // background grids
        vec4 grid_uv = vec4(24,24,6,6)*(uv.xyxy-VIEW_ZOOM-iTime*.005*vec4(5,-3,-5,3));
        vec4 grid = smoothstep(1.-max(10.*px,0.01)*vec4(4,4,1,1), vec4(1), sin(PI*grid_uv))*vec4(.5,.5,1,1);
        col = mix(col, vec3(.7), max(grid.x, max(grid.y, max(grid.z, grid.w))));
        
        // Arrows
        float arr_d = FLT_MAX;
        #define ARR_ANIM(P) vec2(0,.05*sin(3.*iTime+1000.*P))
        arr_d = min(arr_d, sdDottedArrow(uv-vec2(1,0)+ARR_ANIM(0.), .3, 3));
        arr_d = min(arr_d, sdDottedArrow(uv-vec2(1.9,-.5)+ARR_ANIM(1.), .3, 3));
        arr_d = min(arr_d, sdDottedArrow(rot(-1.2)*(uv-vec2(0,.75))+ARR_ANIM(2.), .3, 3));
        arr_d = min(arr_d, sdDottedArrow(rot(.8)*(uv-vec2(.3,-.5))+ARR_ANIM(3.), .3, 3));
        arr_d = min(arr_d, sdDottedArrow(rot(PI*.5)*(uv-vec2(-.7,-.83))+ARR_ANIM(3.), .3, 3));
        arr_d = min(arr_d, sdArrow(rot(1.72)*(uv-vec2(-.9,-.15))+ARR_ANIM(4.), .1));
        arr_d = min(arr_d, sdArrow(rot(-1.72)*(uv-vec2(-1.3,-.43))+ARR_ANIM(5.), .1));
        arr_d = min(arr_d, sdArrow(rot(1.72)*(uv-vec2(-1.4,-.61))+ARR_ANIM(6.), .1));
        arr_d = min(arr_d, sdArrow(rot(2.6)*(uv-vec2(-1.83,.7))+ARR_ANIM(7.), .1));
        arr_d = min(arr_d, sdArrow(rot(-2.6)*(uv-vec2(-1.15,.7))+ARR_ANIM(8.), .1));
        if(g.funnel_b_id >= 0) // funnel arrow
        {
            vec2 f_dir = loadBody(iChannel0, g.funnel_b_id).pos - vec2(-1.75,.1);
            arr_d = min(arr_d, sdArrow(rot(PI*0.5-atan(f_dir.y,f_dir.x))*(uv-vec2(-1.75,.1))-vec2(0,.1), .1));
        }
        if(MOUSE_DOWN) // force arrows
        {
            vec2 m = VIEW(iMouse);
            if(g.mode==0) arr_d = min(arr_d, sdDottedArrow(rot(PI*.25)*abs(uv-m)-vec2(0,.2+.1*sin(5.*iTime)), .15, 2));
            if(g.mode==1) arr_d = min(arr_d, sdDottedArrow(rot(PI*1.25)*abs(uv-m)-vec2(0,-.2+.1*sin(5.*iTime)), .15, 2));
        }

        col = mix(col, vec3(.8), 1.0-smoothstep(0.,.008, arr_d));    

    } 
    else // bodies
    {
        if(closest_b.inv_mass == 0.0 && abs(closest_b.ang_vel) < EPS) // solid lines pattern
        {
            float ang = round((4.*closest_b.ang-PI)/(2.*PI))/2.*PI+PI*.25;
            vec2 ruv = vec2(cos(ang) * uv.x, sin(ang) * uv.y);
            col = mix(col, vec3(1), smoothstep(-.07, -0.06, body_d) * smoothstep(1.-max(75.*px,0.1), 1. ,.5+.5*sin(PI*40.*(ruv.x + ruv.y))));
        }
        
        col *= (closest_b_id < FACTORY_FIXED_BODIES) ? 0.8 : 1.2; // bodies color
        // if(closest_b_id == g.funnel_b_id) col = col.zyx; // visualize closest body to the funnel exit
    }
	col = mix( col, vec3(1), 1.0-smoothstep(0.,.008, abs(closest_b_id >= FACTORY_FIXED_BODIES ? outline_d : body_d)) ); // outline

    // Joints
    float joint_d = FLT_MAX;
    int closest_j_id = -1;
    for(int joint_id = 0; joint_id < g.n_joint; joint_id++)
    {
        Joint j = loadJoint(iChannel0, g, joint_id);
        float j_d = sdJoint(uv, j, iChannel0);
        
        if(j_d < joint_d)
        {
            joint_d = j_d;
            closest_j_id = joint_id;
        }
    }
    Joint closest_j = loadJoint(iChannel0, g, closest_j_id);
    col = mix( col, vec3(1), 1.-smoothstep(.0, 0.004, (joint_d)));
    
    // Texts
    #define PRINT_CHR(P,C,D,F) D=max(D,F(P,C));
    #define PRINT_STR(P,A,D,F) for(int i=0;i<A.length();i++,P.x-=.44)D=max(D,F(P,A[i]));
    #define PRINT_INT(P,N,D,F) for(int i=0,n=N;n>0||i==0;i++,n/=10,P.x+=.44)D=max(D,F(P,48+n%10));
    float char_d = 0.;
    vec2 p = vec2(6,6.3)*(uv-vec2(-.6,1.27));
    int title[] = int[](84,104,101,32,67,104,97,111,115,32,70,97,99,116,111,114,121);
    PRINT_STR(p, title, char_d, drawChar)
    p = (p+vec2(8.8, .58))*1.4;
    int subtitle[] = int[](71,80,85,32,105,109,112,108,101,109,101,110,116,97,116,105,111,110,32,111,102,32,66,111,120,50,68,45,108,105,116,101);
    PRINT_STR(p, subtitle, char_d, .8*drawCharIt)
    p = vec2(8,8.3)*(uv-vec2(-1.95,-1.27));
    int hint_0[] = int[](67,108,105,99,107,32,116,111,32,112,117,115,104,32,98,111,120,101,115,33);
    int hint_1[] = int[](67,108,105,99,107,32,116,111,32,112,117,108,108,32,98,111,120,101,115,33);
    int hint_2[] = int[](67,108,105,99,107,32,116,111,32,97,100,100,32,109,111,114,101,33,32,32);
    if(g.mode == 0) PRINT_STR(p, hint_0, char_d, (.5+.5*sin(2.*iTime))*drawChar)
    if(g.mode == 1) PRINT_STR(p, hint_1, char_d, (.5+.5*sin(2.*iTime))*drawChar)
    if(g.mode == 2) PRINT_STR(p, hint_2, char_d, (.5+.5*sin(2.*iTime))*drawChar)
    int boxes[] = int[](66,111,120,101,115,32,58,32);
    p = p-vec2(-8.6,1.15);
    PRINT_STR(p, boxes, char_d, .8*drawCharIt)
    p.x -= float(boxes.length())*.44;
    PRINT_INT(p, bodyMax(g.res), char_d, .8*drawCharIt)
    p.x += .44;
    PRINT_CHR(p, 47, char_d, .8*drawCharIt)
    p.x += .88;
    PRINT_INT(p, g.n_body, char_d, .8*drawCharIt)
    p = vec2(8,8.3)*(uv-vec2(-1.87,.04));
    PRINT_INT(p, g.n_funnel, char_d, drawChar)
    col = mix(col, vec3(1), char_d);    
    
    // Icons
    float icon_d = FLT_MAX;
    p = uv - vec2(-1.7, 1.3);
    #define ANIM_ICON(GM, M) ((GM == M) ? sin(5.*iTime) : 0.0)
    icon_d = min(icon_d, sdArrow(rot(PI*.25)*(abs(p)-vec2(.05+.005*ANIM_ICON(g.mode, 0))), .05));
    icon_d = min(icon_d, sdArrow(rot(PI*1.25)*(abs(p-vec2(.3, 0))-vec2(.035+.005*ANIM_ICON(g.mode, 1))), .05));
    icon_d = min(icon_d, abs(sdBox(rot(-.2)*(p-vec2(.6,-.03)), vec2(.04)))-.004);
    icon_d = min(icon_d, sdBox((1.+.1*ANIM_ICON(g.mode, 2))*(p-vec2(.64,.04)), vec2(.04,.01)));
    icon_d = min(icon_d, sdBox((1.+.1*ANIM_ICON(g.mode, 2))*(p-vec2(.64,.04)), vec2(.01,.04)));
    col = mix(col, vec3(1.,.73, 0.), 1.-step(0., sdBox(p - vec2(float(g.mode) * .3, 0), vec2(.1))));
    p.x = p.x - .3*clamp(round(p.x/.3), 0., 2.);
    icon_d = min(icon_d, abs(sdBox(p, vec2(.09))-.01)-.005);
    col = mix(col, vec3(1), 1.-smoothstep(.0, 0.004, icon_d));    
   
    fragColor = vec4(pow(col,vec3(1.21)),1.0);
}
