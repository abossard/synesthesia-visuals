// IMAGE

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    ivec2 v = ivec2(floor(fragCoord));
    ivec2 c = ivec2(floor(iResolution.xy/2.0));
    v = (v-c)/SCALE+c;
    vec4 a = texelFetch(iChannel0, v, 0);
    //fragColor = vec4(a.w > 0.5 ? vec3(0.5) : a.z > 0.0 ? mix(vec3(0,1,1),vec3(0,0,0.5),a.z) : vec3(0),1);
    //fragColor = vec4(a.w > 0.5 ? vec3(0.5) : a.z > 0.0 ? pow(vec3(.1, .7, .8), vec3(4.*a.z)) : vec3(0),1); // palette: https://www.shadertoy.com/view/MlcGD7 natural colors (fire, water,...) by FabriceNeyret2
    fragColor = vec4(a.w > 0.5 ? mix(vec3(0.3),vec3(0.5),hash(vec2(v))) : a.z > 0.0 ? pow(vec3(.1, .7, .8), vec3(4.*a.z)) : vec3(0),1); // palette: https://www.shadertoy.com/view/MlcGD7 natural colors (fire, water,...) by FabriceNeyret2
}

