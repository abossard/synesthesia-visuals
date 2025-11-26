// Chimera's Breath
// by nimitz 2018 (twitter: @stormoid)
// https://www.shadertoy.com/view/4tGfDW
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// Contact the author for other licensing options

/*
	Simulation code is in the "common" tab (and extra defines)

	The main interest here is the addition of vorticity confinement with the curl stored in
	the alpha channel of the simulation texture (which was not used in the paper)
	this in turns allows for believable simulation of much lower viscosity fluids.
	Without vorticity confinement, the fluids that can be simulated are much more akin to
	thick oil.
	
	Base Simulation based on the 2011 paper: "Simple and fast fluids"
	(Martin Guay, Fabrice Colin, Richard Egli)
	(https://hal.inria.fr/inria-00596050/document)

	The actual simulation only requires one pass, Buffer A, B and C	are just copies 
	of each other to increase the simulation speed (3 simulation passes per frame)
	and Buffer D is drawing colors on the simulated fluid 
	(could be using particles instead in a real scenario)
*/

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec4 col = textureLod(iChannel0, fragCoord/iResolution.xy, 0.);
    if (fragCoord.y < 1. || fragCoord.y >= (iResolution.y-1.))
        col = vec4(0);
    fragColor = col;
}
