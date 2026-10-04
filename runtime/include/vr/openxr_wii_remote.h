// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace mkw::vr {

// The tracked VR controllers presented to the game as a Wii Remote with a
// Nunchuk, the way DolphinXR's "OpenXR Wii Remote" source does it: the right
// controller is the remote (buttons, accelerometer and IR pointer), the left
// one is the Nunchuk (stick, C/Z and its own accelerometer).
//
// The OpenXR pacing thread builds one OpenXRWiiRemoteSample per XR frame and
// publishes it here; the KPAD/WPAD HLE on the guest thread reads the latest one
// whenever the game polls. Nothing in this header depends on OpenXR, so the
// guest side compiles (and simply never sees a remote) in builds without it.

enum class OpenXRControllerMode : uint8_t {
    // Wii Remote + Nunchuk through KPAD, with motion and pointing.
    WiiRemote,
    // One ordinary gamepad, read through PAD as a GameCube controller.
    Gamepad,
    // Nothing to the game: the virtual gamepad is unplugged, so the controllers
    // hold no port. They still open the settings panel.
    None,
};

struct OpenXRWiiRemoteSample {
    uint32_t hold = 0;                              // WPAD_BUTTON_* bits, Nunchuk C/Z included
    std::array<float, 3> acc{0.0f, -1.0f, 0.0f};    // remote accelerometer in g, KPAD frame
    std::array<float, 2> stick{};                   // Nunchuk stick, -1..1, +y up
    std::array<float, 3> nunchuk_acc{0.0f, -1.0f, 0.0f};
    // IR pointer in KPADStatus terms: pos is -1..1 across the game picture with
    // +y down, horizon is the remote's x axis on the screen ((1, 0) held level,
    // (0, 1) rolled a quarter turn clockwise), distance in metres.
    bool pointer_valid = false;
    std::array<float, 2> pointer{};
    std::array<float, 2> horizon{1.0f, 0.0f};
    float distance_meters = 0.0f;
};

// Live switch between the presentations; the settings bar and the launch
// configuration both go through it.
void OpenXRSetControllerMode(OpenXRControllerMode mode) noexcept;
OpenXRControllerMode OpenXRGetControllerMode() noexcept;

// Guest side. True when `sdl_joystick_id` is the OpenXR virtual gamepad and the
// controllers are currently presented as a Wii Remote.
bool OpenXRWiiRemoteOwnsGamepad(uint32_t sdl_joystick_id) noexcept;
// True when `sdl_joystick_id` is the VR controllers' virtual gamepad, in either
// presentation.
bool OpenXRIsControllerGamepad(uint32_t sdl_joystick_id) noexcept;
// Latest published sample; false before the first one or after withdrawal.
bool OpenXRReadWiiRemote(OpenXRWiiRemoteSample& sample) noexcept;
// WPADControlMotor for the emulated remote.
void OpenXRSetWiiRemoteRumble(bool active) noexcept;

// XR side.
void OpenXRPublishWiiRemote(uint32_t sdl_joystick_id, const OpenXRWiiRemoteSample& sample) noexcept;
void OpenXRWithdrawWiiRemote() noexcept;
bool OpenXRWiiRemoteRumbleRequested() noexcept;

// The geometry and signal conditioning behind a sample, kept free of OpenXR
// types so it can be checked headlessly (tests/vr_wii_remote_tests.cpp).
//
// Conventions are OpenXR's: right-handed, +Y up, metres. A controller's aim
// pose points down its -Z axis with +X to the right and +Y up; a screen faces
// its +Z axis with +X to the right and +Y up across the picture.
namespace wii_remote {

// WPAD_BUTTON_* bits as KPADStatus.hold carries them.
inline constexpr uint32_t kButtonLeft = 0x0001, kButtonRight = 0x0002, kButtonDown = 0x0004,
                          kButtonUp = 0x0008, kButtonPlus = 0x0010, kButtonTwo = 0x0100,
                          kButtonOne = 0x0200, kButtonB = 0x0400, kButtonA = 0x0800,
                          kButtonMinus = 0x1000, kButtonZ = 0x2000, kButtonC = 0x4000,
                          kButtonHome = 0x8000;

inline constexpr float kStandardGravity = 9.80665f;
// The remote's ADXL330 saturates a little past +-3 g.
inline constexpr float kAccelRangeG = 3.6f;
// Analog inputs count as a press past this, like Dolphin's button threshold.
inline constexpr float kPressThreshold = 0.5f;
// How far past the picture's edge (in half extents) the pointer is still
// reported. A real remote's camera (42 x 31.5 degrees) keeps seeing the sensor
// bar well beyond the screen, so it does not drop the cursor at the border.
inline constexpr float kPointerMarginU = 1.9f;
inline constexpr float kPointerMarginV = 1.5f;
// An excursion past those margins, or a lost hit, must last this long before
// the pointer is hidden: pose spikes during fast wrist motion otherwise drop it.
inline constexpr int64_t kPointerHideDelayNs = 100'000'000;

using Vec3 = std::array<float, 3>;
using Quat = std::array<float, 4>; // x, y, z, w

struct Pose {
    Vec3 position{};
    Quat orientation{0.0f, 0.0f, 0.0f, 1.0f};
};

inline float Dot(const Vec3& a, const Vec3& b) noexcept {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

// q * v * conjugate(q) for a unit quaternion.
inline Vec3 Rotate(const Quat& q, const Vec3& v) noexcept {
    const Vec3 t{2.0f * (q[1] * v[2] - q[2] * v[1]), 2.0f * (q[2] * v[0] - q[0] * v[2]),
                 2.0f * (q[0] * v[1] - q[1] * v[0])};
    return {v[0] + q[3] * t[0] + (q[1] * t[2] - q[2] * t[1]),
            v[1] + q[3] * t[1] + (q[2] * t[0] - q[0] * t[2]),
            v[2] + q[3] * t[2] + (q[0] * t[1] - q[1] * t[0])};
}

inline Quat Conjugate(const Quat& q) noexcept {
    return {-q[0], -q[1], -q[2], q[3]};
}

// A flat rectangle: the part of a virtual screen the game's picture covers.
struct Screen {
    Pose pose;
    float half_width = 0.0f;
    float half_height = 0.0f;
};

struct ScreenHit {
    bool valid = false;
    float u = 0.0f; // -1..1 across the picture, +right; beyond +-1 off the edge
    float v = 0.0f; // -1..1, +up
    float distance_meters = 0.0f;
};

// Where the aim ray meets the screen's plane, the same absolute mapping as
// DolphinXR's ComputeVirtualScreenHit: aiming at a point puts the pointer
// there, with nothing to recenter.
inline ScreenHit RaycastScreen(const Pose& aim, const Screen& screen) noexcept {
    ScreenHit hit{};
    if (!(screen.half_width > 0.0f) || !(screen.half_height > 0.0f)) {
        return hit;
    }
    const Quat inverse = Conjugate(screen.pose.orientation);
    const Vec3 offset{aim.position[0] - screen.pose.position[0], aim.position[1] - screen.pose.position[1],
                      aim.position[2] - screen.pose.position[2]};
    const Vec3 origin = Rotate(inverse, offset);
    const Vec3 direction = Rotate(inverse, Rotate(aim.orientation, {0.0f, 0.0f, -1.0f}));
    // Only from in front of the picture, and only towards it.
    if (!(origin[2] > 0.0f) || !(direction[2] < -1.0e-6f)) {
        return hit;
    }
    const float t = -origin[2] / direction[2];
    hit.valid = true;
    hit.u = (origin[0] + t * direction[0]) / screen.half_width;
    hit.v = (origin[1] + t * direction[1]) / screen.half_height;
    // Perpendicular distance: rotating the controller must not move it.
    hit.distance_meters = origin[2];
    return hit;
}

// KPADStatus.pos for a hit: the SDK's pointer runs from (-1, -1) at the
// picture's top left to (1, 1) at its bottom right.
inline std::array<float, 2> KpadPosition(const ScreenHit& hit) noexcept {
    return {hit.u, -hit.v};
}

// KPADStatus.horizon: the remote's right axis as it lies on the screen, in the
// pointer's +y-down frame.
inline std::array<float, 2> Horizon(const Pose& aim, const Screen& screen) noexcept {
    const Vec3 right = Rotate(Conjugate(screen.pose.orientation), Rotate(aim.orientation, {1.0f, 0.0f, 0.0f}));
    const float length = std::sqrt(right[0] * right[0] + right[1] * right[1]);
    if (!(length > 1.0e-3f)) {
        return {1.0f, 0.0f};
    }
    return {right[0] / length, -right[1] / length};
}

// KPAD accelerometer reading for a controller whose aim orientation is
// `orientation` while it accelerates at `world_acceleration` (m/s^2).
//
// An accelerometer measures specific force, acceleration minus gravity, so a
// remote at rest reads 1 g upwards. KPAD's frame is x right across the face, y
// through the back of the remote and z towards the player (Wii axes
// (-x, -z, y)), which on an aim pose is (x, -y, z): at rest, level, that is
// (0, -1, 0), and DolphinXR's (-x, z, y) Wii-frame mapping lands on the same.
inline Vec3 KpadAcceleration(const Quat& orientation, const Vec3& world_acceleration) noexcept {
    const Vec3 specific_force{world_acceleration[0], world_acceleration[1] + kStandardGravity,
                              world_acceleration[2]};
    const Vec3 local = Rotate(Conjugate(orientation), specific_force);
    const auto axis = [](float value) {
        return std::clamp(value / kStandardGravity, -kAccelRangeG, kAccelRangeG);
    };
    return {axis(local[0]), axis(-local[1]), axis(local[2])};
}

// Differentiates a controller's linear velocity into the acceleration its
// accelerometer would add to gravity, mirroring DolphinXR's
// OpenXRVelocityHistory: the runtime's velocity is averaged with one derived
// from the pose, because some runtimes smooth theirs heavily and a flick loses
// its peak. Time is XrTime nanoseconds, so wall-clock jitter never enters dt.
class MotionTracker {
public:
    // `orientation` is the aim pose, `position`/`velocity` the grip's. Returns
    // the KPAD reading; with no orientation it repeats the last one.
    Vec3 Update(const Quat* orientation, const Vec3* position, const Vec3* velocity, int64_t time_ns) noexcept {
        if (orientation == nullptr) {
            Reset();
            return m_last;
        }
        const float dt = m_has_position ? static_cast<float>(time_ns - m_time_ns) * 1.0e-9f : 0.0f;
        const bool dt_usable = dt > 0.001f;

        bool have_velocity = velocity != nullptr;
        Vec3 current = have_velocity ? *velocity : Vec3{};
        if (position != nullptr && m_has_position && dt_usable) {
            const Vec3 from_pose{((*position)[0] - m_position[0]) / dt, ((*position)[1] - m_position[1]) / dt,
                                 ((*position)[2] - m_position[2]) / dt};
            for (size_t i = 0; i < 3; ++i) {
                current[i] = have_velocity ? 0.5f * (current[i] + from_pose[i]) : from_pose[i];
            }
            have_velocity = true;
        }

        Vec3 acceleration{};
        if (have_velocity && m_has_velocity && dt_usable) {
            for (size_t i = 0; i < 3; ++i) {
                acceleration[i] = (current[i] - m_velocity[i]) / dt;
            }
        }

        if (position != nullptr) {
            m_position = *position;
            m_time_ns = time_ns;
            m_has_position = true;
        } else {
            m_has_position = false;
            m_has_velocity = false;
        }
        if (have_velocity) {
            m_velocity = current;
            m_has_velocity = true;
        } else if (!m_has_position) {
            m_has_velocity = false;
        }

        m_last = KpadAcceleration(*orientation, acceleration);
        return m_last;
    }

    void Reset() noexcept {
        m_has_position = false;
        m_has_velocity = false;
    }

    // Back to a remote lying still, for when the controllers go idle.
    void Rest() noexcept {
        Reset();
        m_last = {0.0f, -1.0f, 0.0f};
    }

private:
    bool m_has_position = false;
    bool m_has_velocity = false;
    Vec3 m_position{};
    Vec3 m_velocity{};
    int64_t m_time_ns = 0;
    Vec3 m_last{0.0f, -1.0f, 0.0f};
};

// Hides the pointer the way a real remote loses the sensor bar, without
// dropping it on every tracking hiccup: brief excursions and lost hits hold or
// pin the last position, and only a sustained one hides it.
class PointerFilter {
public:
    ScreenHit Update(const ScreenHit& hit, int64_t time_ns) noexcept {
        const bool on_screen = hit.valid && std::fabs(hit.u) <= kPointerMarginU &&
                               std::fabs(hit.v) <= kPointerMarginV;
        if (on_screen) {
            m_off_screen = false;
            m_held = hit;
            return hit;
        }
        if (!m_off_screen) {
            m_off_screen = true;
            m_off_since_ns = time_ns;
        }
        if (!m_held.valid || time_ns - m_off_since_ns >= kPointerHideDelayNs) {
            m_held.valid = false;
            return {};
        }
        if (!hit.valid) {
            return m_held;
        }
        ScreenHit pinned = hit;
        pinned.u = std::clamp(hit.u, -kPointerMarginU, kPointerMarginU);
        pinned.v = std::clamp(hit.v, -kPointerMarginV, kPointerMarginV);
        return pinned;
    }

    void Reset() noexcept {
        m_held = {};
        m_off_screen = false;
    }

private:
    ScreenHit m_held{};
    bool m_off_screen = false;
    int64_t m_off_since_ns = 0;
};

// The part of an aspect-ratio-preserving fit a `content` aspect takes inside a
// `container` aspect, as fractions of the container's width and height.
inline std::array<float, 2> FitFraction(float content_aspect, float container_aspect) noexcept {
    if (!(content_aspect > 0.0f) || !(container_aspect > 0.0f)) {
        return {1.0f, 1.0f};
    }
    return content_aspect >= container_aspect ? std::array<float, 2>{1.0f, container_aspect / content_aspect}
                                              : std::array<float, 2>{content_aspect / container_aspect, 1.0f};
}

// Half extents, in metres, of the game picture on the menu quad. The quad is
// `quad_width` across with the eye texture's aspect; Aurora fits the desktop
// snapshot into that texture and the game picture into the snapshot, both
// letterboxed, so a 4:3 picture in a 16:9 window keeps its pillarboxes.
inline std::array<float, 2> MenuPictureHalfExtents(float quad_width, float eye_aspect, float snapshot_aspect,
                                                   float picture_aspect) noexcept {
    const float quad_half_width = 0.5f * quad_width;
    const float quad_half_height = eye_aspect > 0.0f ? quad_half_width / eye_aspect : quad_half_width;
    const std::array<float, 2> snapshot = FitFraction(snapshot_aspect, eye_aspect);
    const std::array<float, 2> picture = FitFraction(picture_aspect, snapshot_aspect);
    return {quad_half_width * snapshot[0] * picture[0], quad_half_height * snapshot[1] * picture[1]};
}

// One controller's digital and analog inputs.
struct HandInputs {
    bool primary = false;   // A / X
    bool secondary = false; // B / Y
    bool menu = false;
    bool thumbstick_click = false;
    float trigger = 0.0f;
    float squeeze = 0.0f;
    float stick_x = 0.0f;
    float stick_y = 0.0f; // +up
    // A D-pad, which only the Steam Frame's left controller has
    // (valve/frame_controller_valve).
    bool dpad_up = false;
    bool dpad_down = false;
    bool dpad_left = false;
    bool dpad_right = false;
};

// Adapted from DolphinXR's default "OpenXR Wii Remote" profile
// (Data/Sys/Profiles/Wiimote):
//   right A -> A, right trigger -> B, right B -> C, right stick up/down -> 1/2,
//   left X and left menu -> +,
//   left trigger -> Z, left stick -> Nunchuk stick.
// + is on left X as well because the PlayStation VR2's controllers give no
// usable left menu, and - has no button because Mario Kart Wii never reads it.
// HOME has no button; left Y opens the settings panel (openxr_settings_panel.h).
// The grips press nothing: they take hold of the wheel (openxr_driving.h), and C
// is the game's look-behind, which a hand on the wheel would otherwise hold down.
// A controller D-pad (the Steam Frame's left one) is the remote's D-pad; the
// Frame's left View button is the left menu and its left shoulder the left Y.
inline uint32_t RemoteButtons(const HandInputs& left, const HandInputs& right) noexcept {
    uint32_t hold = 0;
    const auto press = [&hold](bool held, uint32_t bit) {
        if (held) {
            hold |= bit;
        }
    };
    press(right.primary, kButtonA);
    press(right.trigger > kPressThreshold, kButtonB);
    press(right.secondary, kButtonC);
    press(right.stick_y > kPressThreshold, kButtonOne);
    press(right.stick_y < -kPressThreshold, kButtonTwo);
    press(left.primary || left.menu, kButtonPlus);
    press(left.trigger > kPressThreshold, kButtonZ);
    press(left.dpad_up || right.dpad_up, kButtonUp);
    press(left.dpad_down || right.dpad_down, kButtonDown);
    press(left.dpad_left || right.dpad_left, kButtonLeft);
    press(left.dpad_right || right.dpad_right, kButtonRight);
    return hold;
}

// The left thumbstick as the Nunchuk's, kept inside its circular gate.
inline std::array<float, 2> NunchukStick(const HandInputs& left) noexcept {
    float x = left.stick_x;
    float y = left.stick_y;
    const float length = std::sqrt(x * x + y * y);
    if (length > 1.0f) {
        x /= length;
        y /= length;
    }
    return {x, y};
}

} // namespace wii_remote

} // namespace mkw::vr
