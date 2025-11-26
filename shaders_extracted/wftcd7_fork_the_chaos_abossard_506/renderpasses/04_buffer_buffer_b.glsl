// Physics Iteration

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    physicsIteration(fragColor, fragCoord, iResolution.xy, iChannel0);
}
