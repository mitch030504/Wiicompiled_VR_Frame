// SPDX-License-Identifier: GPL-3.0-or-later
//
// The VR controllers' Wii Remote presentation, tested without a headset: the
// KPAD accelerometer frame, the absolute pointer against a virtual screen, the
// picture's place on the menu quad, the off-screen debounce and the button
// profile. Every expectation is stated in the Wii's own terms, so a sign error
// in the geometry shows up as the wrong button face, tilt or cursor edge.

#include "vr/openxr_wii_remote.h"

#include <cmath>
#include <iostream>

namespace {

using namespace mkw::vr::wii_remote;

int g_failures = 0;

void Check(bool condition, const char* what) {
    if (!condition) {
        ++g_failures;
        std::cerr << "FAILED: " << what << '\n';
    }
}

void CheckNear(float actual, float expected, const char* what, float tolerance = 1.0e-3f) {
    if (!(std::fabs(actual - expected) <= tolerance)) {
        ++g_failures;
        std::cerr << "FAILED: " << what << " (expected " << expected << ", got " << actual << ")\n";
    }
}

constexpr float kHalfTurn = 3.14159265f;
constexpr float kQuarterTurn = 0.5f * kHalfTurn;

Quat AxisAngle(float x, float y, float z, float radians) {
    const float s = std::sin(0.5f * radians);
    return {x * s, y * s, z * s, std::cos(0.5f * radians)};
}

// Aim poses as a player holds the controller. Forward is -Z, up +Y, right +X.
constexpr Quat kLevel{0.0f, 0.0f, 0.0f, 1.0f};
Quat PitchedUp(float radians) { return AxisAngle(1.0f, 0.0f, 0.0f, radians); }
Quat YawedLeft(float radians) { return AxisAngle(0.0f, 1.0f, 0.0f, radians); }
// Seen from behind the controller, looking where it points.
Quat RolledClockwise(float radians) { return AxisAngle(0.0f, 0.0f, 1.0f, -radians); }

void TestRestingAccelerometer() {
    const Vec3 zero{};
    // KPAD's rest reading with the buttons up.
    Vec3 acc = KpadAcceleration(kLevel, zero);
    CheckNear(acc[0], 0.0f, "level remote: x");
    CheckNear(acc[1], -1.0f, "level remote: gravity through the back of the remote");
    CheckNear(acc[2], 0.0f, "level remote: z");

    // Pointing at the floor, the remote's back end (KPAD +z, towards the
    // player) is the side facing up.
    acc = KpadAcceleration(PitchedUp(-kQuarterTurn), zero);
    CheckNear(acc[1], 0.0f, "pointing down: y");
    CheckNear(acc[2], 1.0f, "pointing down: gravity along z");

    // Pointing at the ceiling it is the tip that faces up.
    acc = KpadAcceleration(PitchedUp(kQuarterTurn), zero);
    CheckNear(acc[2], -1.0f, "pointing up: gravity along -z");

    // Rolled a quarter turn clockwise the remote's left edge (KPAD -x) faces up.
    acc = KpadAcceleration(RolledClockwise(kQuarterTurn), zero);
    CheckNear(acc[0], -1.0f, "rolled clockwise: gravity along -x");
    CheckNear(acc[1], 0.0f, "rolled clockwise: y");

    // Buttons facing the floor.
    acc = KpadAcceleration(RolledClockwise(kHalfTurn), zero);
    CheckNear(acc[1], 1.0f, "upside down: gravity along +y");
}

void TestAccelerometerRange() {
    // A 10 g upward jolt saturates like the ADXL330 instead of reporting 11 g.
    const Vec3 acc = KpadAcceleration(kLevel, {0.0f, 10.0f * kStandardGravity, 0.0f});
    CheckNear(acc[1], -kAccelRangeG, "saturates at the sensor's range");
}

void TestMotionTracker() {
    MotionTracker tracker;
    const Quat orientation = kLevel;
    // Rising at 1 g: p = a t^2 / 2, v = a t, sampled at 90 Hz.
    const float a = kStandardGravity;
    const int64_t step_ns = 11'111'111;
    Vec3 acc{};
    for (int i = 0; i < 6; ++i) {
        const float t = static_cast<float>(i) * static_cast<float>(step_ns) * 1.0e-9f;
        const Vec3 position{0.0f, 0.5f * a * t * t, 0.0f};
        const Vec3 velocity{0.0f, a * t, 0.0f};
        acc = tracker.Update(&orientation, &position, &velocity, i * step_ns);
        if (i == 0) {
            CheckNear(acc[1], -1.0f, "first sample has no history: gravity only");
        }
    }
    // Gravity plus the climb: 2 g through the back of the remote.
    CheckNear(acc[1], -2.0f, "steady 1 g climb reads 2 g", 1.0e-2f);

    // Holding still again settles back to rest.
    const Vec3 still_position{0.0f, 1.0f, 0.0f};
    const Vec3 still_velocity{};
    tracker.Reset();
    for (int i = 0; i < 4; ++i) {
        acc = tracker.Update(&orientation, &still_position, &still_velocity, (10 + i) * step_ns);
    }
    CheckNear(acc[1], -1.0f, "at rest after a reset", 1.0e-3f);

    // Losing tracking repeats the last reading instead of inventing one.
    const Vec3 held = tracker.Update(nullptr, nullptr, nullptr, 20 * step_ns);
    CheckNear(held[1], acc[1], "untracked controller holds its last reading");
}

Screen ScreenAhead(float distance, float half_width, float half_height) {
    Screen screen;
    screen.pose.position = {0.0f, 0.0f, -distance};
    screen.half_width = half_width;
    screen.half_height = half_height;
    return screen;
}

void TestRaycast() {
    const Screen screen = ScreenAhead(2.0f, 1.2f, 0.675f);

    Pose aim;
    ScreenHit hit = RaycastScreen(aim, screen);
    Check(hit.valid, "aiming at the screen's centre hits");
    CheckNear(hit.u, 0.0f, "centre: u");
    CheckNear(hit.v, 0.0f, "centre: v");
    CheckNear(hit.distance_meters, 2.0f, "centre: distance");

    // Absolute: sliding the hand to the right edge puts the pointer there.
    aim.position = {1.2f, 0.0f, 0.0f};
    hit = RaycastScreen(aim, screen);
    CheckNear(hit.u, 1.0f, "hand at the right edge: u");

    // Tilting up to the top edge: KPAD's y is -1 at the top.
    aim.position = {};
    aim.orientation = PitchedUp(std::atan(0.675f / 2.0f));
    hit = RaycastScreen(aim, screen);
    CheckNear(hit.v, 1.0f, "tilted to the top edge: v");
    CheckNear(KpadPosition(hit)[1], -1.0f, "top edge is KPAD y -1");

    // Turning left moves the pointer left.
    aim.orientation = YawedLeft(std::atan(0.6f / 2.0f));
    hit = RaycastScreen(aim, screen);
    CheckNear(hit.u, -0.5f, "turned left: u");
    CheckNear(KpadPosition(hit)[0], -0.5f, "turned left: KPAD x");

    // Rotating the controller does not change the distance.
    CheckNear(hit.distance_meters, 2.0f, "distance is perpendicular");

    // Pointing away, or standing behind the screen, is no hit at all.
    aim.orientation = YawedLeft(kHalfTurn);
    Check(!RaycastScreen(aim, screen).valid, "pointing away misses");
    aim.orientation = kLevel;
    aim.position = {0.0f, 0.0f, -3.0f};
    Check(!RaycastScreen(aim, screen).valid, "behind the screen misses");

    // A screen off to the side, facing the player: only the pose matters.
    Screen side;
    side.pose.position = {-2.0f, 0.0f, 0.0f};
    side.pose.orientation = YawedLeft(kQuarterTurn); // its +Z faces +X, back at the player
    side.half_width = 1.0f;
    side.half_height = 1.0f;
    Pose towards_side;
    towards_side.orientation = YawedLeft(kQuarterTurn); // aim -Z becomes -X
    hit = RaycastScreen(towards_side, side);
    Check(hit.valid, "turned towards a side screen hits");
    CheckNear(hit.u, 0.0f, "side screen: u");
    towards_side.position = {0.0f, 0.5f, 0.0f};
    hit = RaycastScreen(towards_side, side);
    CheckNear(hit.v, 0.5f, "side screen: raised hand raises the pointer");
}

void TestHorizon() {
    const Screen screen = ScreenAhead(2.0f, 1.0f, 1.0f);
    Pose aim;
    std::array<float, 2> horizon = Horizon(aim, screen);
    CheckNear(horizon[0], 1.0f, "level remote: horizon x");
    CheckNear(horizon[1], 0.0f, "level remote: horizon y");
    // The SDK's (0, 1) for a quarter turn clockwise.
    aim.orientation = RolledClockwise(kQuarterTurn);
    horizon = Horizon(aim, screen);
    CheckNear(horizon[0], 0.0f, "rolled clockwise: horizon x");
    CheckNear(horizon[1], 1.0f, "rolled clockwise: horizon y");
}

void TestPointerFilter() {
    PointerFilter filter;
    const int64_t ms = 1'000'000;
    ScreenHit on{true, 0.25f, -0.5f, 1.5f};
    ScreenHit result = filter.Update(on, 0);
    Check(result.valid && result.u == 0.25f, "on screen passes through");

    // A tracking blip holds the last position.
    result = filter.Update(ScreenHit{}, 10 * ms);
    Check(result.valid && result.u == 0.25f, "lost hit holds the pointer");
    // An excursion past the margin pins at the margin.
    result = filter.Update(ScreenHit{true, 3.0f, 0.0f, 1.5f}, 50 * ms);
    Check(result.valid, "short excursion stays visible");
    CheckNear(result.u, kPointerMarginU, "short excursion pins at the margin");
    // Sustained, it is hidden like a remote that lost the sensor bar.
    result = filter.Update(ScreenHit{true, 3.0f, 0.0f, 1.5f}, 110 * ms);
    Check(!result.valid, "sustained excursion hides the pointer");
    result = filter.Update(ScreenHit{}, 120 * ms);
    Check(!result.valid, "stays hidden");
    // Coming back shows it straight away.
    result = filter.Update(on, 130 * ms);
    Check(result.valid, "returning to the screen shows it again");

    // Never having been on screen, a lost hit is simply no pointer.
    PointerFilter fresh;
    Check(!fresh.Update(ScreenHit{}, 0).valid, "no pointer before the first hit");
    // Just inside the margins still counts as on screen.
    Check(fresh.Update(ScreenHit{true, 1.8f, -1.4f, 1.0f}, ms).valid, "inside the margins is tracked");
}

void TestMenuPicture() {
    // 16:9 game in a 16:9 window on a square eye texture: full width.
    std::array<float, 2> extents = MenuPictureHalfExtents(2.4f, 1.0f, 16.0f / 9.0f, 16.0f / 9.0f);
    CheckNear(extents[0], 1.2f, "16:9 picture: half width");
    CheckNear(extents[1], 0.675f, "16:9 picture: half height");
    // 4:3 game pillarboxed inside that window.
    extents = MenuPictureHalfExtents(2.4f, 1.0f, 16.0f / 9.0f, 4.0f / 3.0f);
    CheckNear(extents[0], 0.9f, "4:3 picture in 16:9 window: half width");
    CheckNear(extents[1], 0.675f, "4:3 picture in 16:9 window: half height");
    // A wide eye texture pillarboxes a square snapshot by width instead.
    extents = MenuPictureHalfExtents(2.0f, 2.0f, 1.0f, 1.0f);
    CheckNear(extents[0], 0.5f, "square picture on a wide quad: half width");
    CheckNear(extents[1], 0.5f, "square picture on a wide quad: half height");
}

void TestButtons() {
    HandInputs left;
    HandInputs right;
    Check(RemoteButtons(left, right) == 0, "nothing held");

    right.primary = true;
    right.trigger = 0.6f;
    right.secondary = true;
    Check(RemoteButtons(left, right) == (kButtonA | kButtonB | kButtonC),
          "right A, trigger and B are A, B and C");

    right = {};
    right.stick_y = 0.9f;
    Check(RemoteButtons(left, right) == kButtonOne, "right stick up is 1");
    right.stick_y = -0.9f;
    Check(RemoteButtons(left, right) == kButtonTwo, "right stick down is 2");
    right.stick_y = 0.3f;
    Check(RemoteButtons(left, right) == 0, "a light push is no press");
    right.stick_y = 0.0f;
    right.stick_x = -0.9f;
    Check(RemoteButtons(left, right) == 0, "right stick left is unbound");
    right.stick_x = 0.9f;
    Check(RemoteButtons(left, right) == 0, "right stick right is unbound");

    right = {};
    left.primary = true;
    Check(RemoteButtons(left, right) == kButtonPlus, "left X is +, and nothing presses -");
    left = {};
    left.menu = true;
    Check(RemoteButtons(left, right) == kButtonPlus, "left menu is + too");
    left.primary = true;
    Check(RemoteButtons(left, right) == kButtonPlus, "left X and menu together are one +");
    left = {};
    left.trigger = 0.7f;
    Check(RemoteButtons(left, right) == kButtonZ, "left trigger is Z");
    // Left Y is the settings panel's button, the grips take hold of the steering
    // wheel, and nothing presses HOME.
    left = {};
    left.secondary = true;
    left.squeeze = 0.8f;
    right.squeeze = 0.8f;
    right.thumbstick_click = true;
    left.thumbstick_click = true;
    Check(RemoteButtons(left, right) == 0, "left Y, the grips and the stick clicks are unbound");
    left = {};
    right = {};
    left.menu = true;
    Check((RemoteButtons(left, right) & kButtonHome) == 0, "left menu is no longer HOME");

    // The Steam Frame's left D-pad is the remote's, one bit per direction.
    left = {};
    left.dpad_up = true;
    Check(RemoteButtons(left, right) == kButtonUp, "D-pad up is the remote's up");
    left = {};
    left.dpad_down = true;
    left.dpad_left = true;
    Check(RemoteButtons(left, right) == (kButtonDown | kButtonLeft), "D-pad down and left together");
    left = {};
    right.dpad_right = true;
    Check(RemoteButtons(left, right) == kButtonRight, "a D-pad on either hand counts");
    right = {};

    left.stick_x = 1.0f;
    left.stick_y = 1.0f;
    const std::array<float, 2> stick = NunchukStick(left);
    CheckNear(std::hypot(stick[0], stick[1]), 1.0f, "diagonal stays inside the gate");
    CheckNear(stick[0], stick[1], "diagonal keeps its direction");
}

} // namespace

int main() {
    TestRestingAccelerometer();
    TestAccelerometerRange();
    TestMotionTracker();
    TestRaycast();
    TestHorizon();
    TestPointerFilter();
    TestMenuPicture();
    TestButtons();
    if (g_failures != 0) {
        std::cerr << g_failures << " check(s) failed\n";
        return 1;
    }
    std::cout << "vr_wii_remote_tests: all checks passed\n";
    return 0;
}
