// SPDX-License-Identifier: GPL-3.0-or-later
#include "vr/eye_gaze.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

using mkw::vr::eye_gaze::InEye;
using mkw::vr::eye_gaze::Quaternion;
using mkw::vr::eye_gaze::Tangents;

namespace {

void Check(bool condition, const char* what) {
    if (!condition) {
        std::fprintf(stderr, "vr_eye_gaze_tests: %s\n", what);
        std::exit(1);
    }
}

void CheckNear(float value, float expected, const char* what) {
    Check(std::fabs(value - expected) <= 1.0e-4f, what);
}

constexpr float kDegrees = 3.14159265358979f / 180.0f;

// A turn by `degrees` about the unit axis (x, y, z).
Quaternion Turn(float degrees, float x, float y, float z) {
    const float half = 0.5f * degrees * kDegrees;
    return {x * std::sin(half), y * std::sin(half), z * std::sin(half), std::cos(half)};
}

} // namespace

int main() {
    // Looking straight ahead through an eye looking straight ahead: its forward direction.
    Tangents t = InEye({}, {});
    Check(t.valid, "straight ahead is valid");
    CheckNear(t.x, 0.0f, "straight ahead: x");
    CheckNear(t.y, 0.0f, "straight ahead: y");

    // A turn about +Y by a positive angle looks left (-X), about +X looks up (+Y).
    t = InEye(Turn(20.0f, 0.0f, 1.0f, 0.0f), {});
    Check(t.valid, "20 degrees left is valid");
    CheckNear(t.x, -std::tan(20.0f * kDegrees), "20 degrees left: x");
    CheckNear(t.y, 0.0f, "20 degrees left: y");
    t = InEye(Turn(15.0f, 1.0f, 0.0f, 0.0f), {});
    CheckNear(t.x, 0.0f, "15 degrees up: x");
    CheckNear(t.y, std::tan(15.0f * kDegrees), "15 degrees up: y");

    // An eye canted outwards sees the same gaze off its own centre.
    t = InEye({}, Turn(10.0f, 0.0f, 1.0f, 0.0f));
    CheckNear(t.x, std::tan(10.0f * kDegrees), "a left-canted eye sees straight ahead to its right");
    t = InEye(Turn(10.0f, 0.0f, 1.0f, 0.0f), Turn(10.0f, 0.0f, 1.0f, 0.0f));
    CheckNear(t.x, 0.0f, "gaze along the canted eye: x");
    CheckNear(t.y, 0.0f, "gaze along the canted eye: y");

    // The head's own turn cancels out: only the gaze relative to the eye counts.
    const Quaternion head = Turn(70.0f, 0.0f, 1.0f, 0.0f);
    const Quaternion look = Turn(70.0f + 12.0f, 0.0f, 1.0f, 0.0f);
    t = InEye(look, head);
    CheckNear(t.x, -std::tan(12.0f * kDegrees), "a turned head: x");

    // Sideways or behind is no point of the image; an unnormalised quaternion still works.
    Check(!InEye(Turn(85.0f, 0.0f, 1.0f, 0.0f), {}).valid, "85 degrees off is invalid");
    Check(!InEye(Turn(180.0f, 0.0f, 1.0f, 0.0f), {}).valid, "behind is invalid");
    Quaternion scaled = Turn(15.0f, 1.0f, 0.0f, 0.0f);
    scaled = {scaled.x * 3.0f, scaled.y * 3.0f, scaled.z * 3.0f, scaled.w * 3.0f};
    t = InEye(scaled, {});
    CheckNear(t.y, std::tan(15.0f * kDegrees), "unnormalised quaternion");
    Check(InEye({0.0f, 0.0f, 0.0f, 0.0f}, {}).valid, "a zero quaternion reads as identity");

    std::printf("vr_eye_gaze_tests: all checks passed\n");
    return 0;
}
