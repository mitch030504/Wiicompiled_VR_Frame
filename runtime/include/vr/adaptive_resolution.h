// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// Adaptive resolution for the immersive eyes ([vr] adaptive_resolution), adapted from
// heurazy/Wiicompiled_VR-PLUS. Once a second the pacing thread reports how many new eye frames
// reached the headset and how many it should have had. A second well short of the target lowers
// the eyes' scale by a step; three seconds in a row at the target raise it again. The steps are
// slow so a single spike never resizes the eyes, which rebuilds their foveation maps.
//
// The eyes are rendered at the scaled size into a corner of the full swapchain image, and the
// projection layer shows that corner, so the compositor does the upscaling and the swapchains are
// never recreated. Nothing here depends on OpenXR (tests/vr_adaptive_resolution_tests.cpp).

#include <algorithm>

namespace mkw::vr {

class AdaptiveResolution {
public:
    static constexpr float kMinimumScale = 0.7f;
    static constexpr float kStep = 0.1f;
    // Below this share of the target a second counts as short, at or above the other as on time.
    static constexpr float kShortShare = 0.85f;
    static constexpr float kOnTimeShare = 0.97f;
    static constexpr unsigned kOnTimeSecondsToRaise = 3;

    float Scale() const noexcept { return scale_; }

    // One second's measurement: `fps` new eye frames against `target_fps`. Off resets to full size.
    float Observe(float fps, float target_fps, bool enabled) noexcept {
        if (!enabled) {
            scale_ = 1.0f;
            on_time_seconds_ = 0;
            return scale_;
        }
        if (!(target_fps > 0.0f) || !(fps > 0.0f)) {
            return scale_;
        }
        if (fps < target_fps * kShortShare) {
            scale_ = std::max(kMinimumScale, scale_ - kStep);
            on_time_seconds_ = 0;
        } else if (fps >= target_fps * kOnTimeShare) {
            if (++on_time_seconds_ >= kOnTimeSecondsToRaise) {
                scale_ = std::min(1.0f, scale_ + kStep);
                on_time_seconds_ = 0;
            }
        } else {
            on_time_seconds_ = 0;
        }
        // Whole steps only, so float drift never leaves the eyes a pixel off full size.
        scale_ = static_cast<float>(static_cast<int>(scale_ / kStep + 0.5f)) * kStep;
        return scale_;
    }

    // The scaled size of an eye `full` pixels across, never below 2.
    static unsigned Scaled(unsigned full, float scale) noexcept {
        if (scale >= 1.0f) {
            return full;
        }
        return std::max(2u, static_cast<unsigned>(static_cast<float>(full) * scale));
    }

private:
    float scale_ = 1.0f;
    unsigned on_time_seconds_ = 0;
};

} // namespace mkw::vr
