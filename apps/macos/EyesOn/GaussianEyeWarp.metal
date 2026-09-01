#include <CoreImage/CoreImage.h>
#include <metal_stdlib>
using namespace metal;

// Gaussian warp kernel for CIWarpKernel.
//
// For each output pixel at `p`, returns the SOURCE coordinate to sample from.
// The warp simulates natural eye rotation:
//   - At eyeCenter: weight = 1 → samples from pupilCenter → iris appears centered ✓
//   - At corners (far from eyeCenter): weight ≈ 0 → no displacement ✓
//   - Between: smooth Gaussian falloff → natural "eye rotation" look ✓
//
// Parameters (all in CIImage pixel coordinates, origin bottom-left):
//   pupilCenter — current iris centre
//   eyeCenter   — target iris position (eye socket centre)
//   sigma       — Gaussian width in pixels (~0.4 × eye width)
//   strength    — correction fraction [0, 1]

[[stitchable]] float2 gaussianEyeWarp(
    float2 pupilCenter,
    float2 eyeCenter,
    float  sigma,
    float  strength,
    coreimage::destination dest
) {
    float2 p       = dest.coord();
    float2 delta   = p - eyeCenter;
    float  distSq  = delta.x * delta.x + delta.y * delta.y;
    float  weight  = exp(-distSq / (2.0f * sigma * sigma)) * strength;

    // Source coordinate: pull content from the direction of pupilCenter
    return p + (pupilCenter - eyeCenter) * weight;
}
