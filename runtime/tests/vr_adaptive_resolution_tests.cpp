// SPDX-License-Identifier: GPL-3.0-or-later
#include "vr/adaptive_resolution.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

using mkw::vr::AdaptiveResolution;

namespace {

void Check(bool condition, const char* what) {
    if (!condition) {
        std::fprintf(stderr, "vr_adaptive_resolution_tests: %s\n", what);
        std::exit(1);
    }
}

void CheckNear(float value, float expected, const char* what) {
    Check(std::fabs(value - expected) <= 1.0e-5f, what);
}

} // namespace

int main() {
    {
        AdaptiveResolution adaptive;
        CheckNear(adaptive.Observe(40.0f, 60.0f, false), 1.0f, "off stays at full size");
        CheckNear(adaptive.Observe(60.0f, 60.0f, true), 1.0f, "on time at full size stays there");
    }
    {
        AdaptiveResolution adaptive;
        CheckNear(adaptive.Observe(45.0f, 60.0f, true), 0.9f, "a short second lowers a step");
        CheckNear(adaptive.Observe(45.0f, 60.0f, true), 0.8f, "another lowers another");
        CheckNear(adaptive.Observe(45.0f, 60.0f, true), 0.7f, "and another");
        CheckNear(adaptive.Observe(10.0f, 60.0f, true), 0.7f, "never below the minimum");
        CheckNear(adaptive.Observe(60.0f, 60.0f, true), 0.7f, "one second on time is not enough");
        CheckNear(adaptive.Observe(60.0f, 60.0f, true), 0.7f, "two are not enough");
        CheckNear(adaptive.Observe(60.0f, 60.0f, true), 0.8f, "three raise a step");
        CheckNear(adaptive.Observe(55.0f, 60.0f, true), 0.8f, "between the thresholds holds");
        CheckNear(adaptive.Observe(60.0f, 60.0f, true), 0.8f, "and restarts the on-time count");
        CheckNear(adaptive.Observe(60.0f, 60.0f, true), 0.8f, "still counting");
        CheckNear(adaptive.Observe(60.0f, 60.0f, true), 0.9f, "three more raise again");
        for (int second = 0; second < 30; ++second) adaptive.Observe(60.0f, 60.0f, true);
        Check(adaptive.Scale() == 1.0f, "back at exactly full size");
        CheckNear(adaptive.Observe(0.0f, 60.0f, true), 1.0f, "a second with no measurement changes nothing");
        CheckNear(adaptive.Observe(30.0f, 0.0f, true), 1.0f, "nor one with no target");
        adaptive.Observe(30.0f, 60.0f, true);
        CheckNear(adaptive.Observe(30.0f, 60.0f, false), 1.0f, "turning it off restores full size");
    }
    Check(AdaptiveResolution::Scaled(2064, 1.0f) == 2064, "full size is unchanged");
    Check(AdaptiveResolution::Scaled(2000, 0.7f) == 1400, "scaled size");
    Check(AdaptiveResolution::Scaled(2, 0.7f) == 2, "never below two pixels");
    std::puts("vr_adaptive_resolution_tests: ok");
    return 0;
}
