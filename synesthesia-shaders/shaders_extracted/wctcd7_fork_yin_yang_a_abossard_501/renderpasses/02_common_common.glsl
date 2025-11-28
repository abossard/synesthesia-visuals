// Created by srtuss; 2019-09-28
//
// Functions for computing the accurate distance-field and arc-length
// of a Yin-Yang shaped curve. Might have to some interesting uses,
// for animations or adding details to your scenes!
//

#define PI (3.1415926535897932384626433832795)

// Distance-field function of just the curve, without the holes:
float yinyangCurve_surface(vec2 uv)
{
    float k = step(0., uv.x) * 2.;
    return (length(vec2(uv.x, mod(uv.y + k, 4.) - 2.)) - 1.) * (k - 1.);
}

// Distance-field function of the curve, with holes:
float yinyangDots_surface(vec2 uv)
{
    float v = yinyangCurve_surface(uv);
    float holeSize = .3;
    uv.y = mod(uv.y + 1., 4.) - 1.;
    return min(max(v, -length(uv) + holeSize), length(uv - vec2(0., 2.)) - holeSize);
}

// Arc-length function of the curve:
// returns arc-length in radians
float yinyang_arcLength(vec2 uv)
{
    float k = step(0., uv.x);
    uv.y += k * 2.;
    float id = floor(uv.y / 4. - 1.) * -2. + k - 3.5;
   	uv = vec2(uv.x * (k * 2. - 1.), mod(uv.y, 4.) - 2.);
    return atan(uv.x, uv.y) + id * PI;
}
