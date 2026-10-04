// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cmath>

// Eye-tracked foveation ([vr] eye_tracked_foveation): where the player looks, as each eye's image
// measures it. Kept free of OpenXR types so it can be checked headlessly (tests/vr_eye_gaze_tests.cpp).
//
// Conventions are OpenXR's: right-handed, +Y up, and a pose looks down its -Z axis.
namespace mkw::vr::eye_gaze {

struct Quaternion {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    float w = 1.0f;
};

// Tangents of an eye's view, x right and y up, as its frustum (XrFovf) measures them.
struct Tangents {
    float x = 0.0f;
    float y = 0.0f;
    bool valid = false;
};

// Beyond this angle from an eye's forward direction a gaze is no point of its image (cos 80 deg).
inline constexpr float kMinForwardCosine = 0.17364818f;

// The gaze pose's look direction in one eye's view, from both orientations in the same space. The
// eyes' views can be canted outwards, so each eye gets its own tangents.
inline Tangents InEye(Quaternion gaze, Quaternion eye) noexcept {
    const auto normalized = [](Quaternion q) {
        const float length = std::sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
        if (!(length > 1.0e-6f)) {
            return Quaternion{};
        }
        return Quaternion{q.x / length, q.y / length, q.z / length, q.w / length};
    };
    // q * v * conjugate(q).
    const auto rotate = [](const Quaternion& q, float vx, float vy, float vz, float out[3]) {
        const float tx = 2.0f * (q.y * vz - q.z * vy);
        const float ty = 2.0f * (q.z * vx - q.x * vz);
        const float tz = 2.0f * (q.x * vy - q.y * vx);
        out[0] = vx + q.w * tx + (q.y * tz - q.z * ty);
        out[1] = vy + q.w * ty + (q.z * tx - q.x * tz);
        out[2] = vz + q.w * tz + (q.x * ty - q.y * tx);
    };
    gaze = normalized(gaze);
    eye = normalized(eye);
    float look[3];
    rotate(gaze, 0.0f, 0.0f, -1.0f, look);
    float seen[3];
    rotate(Quaternion{-eye.x, -eye.y, -eye.z, eye.w}, look[0], look[1], look[2], seen);
    if (!(-seen[2] > kMinForwardCosine)) {
        return {};
    }
    return {seen[0] / -seen[2], seen[1] / -seen[2], true};
}

} // namespace mkw::vr::eye_gaze
