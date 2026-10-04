// SPDX-License-Identifier: GPL-3.0-or-later
#include "runtime_config.h"
#include <cstdlib>
#include <sstream>
#include <string>
#include <string_view>

static void Require(bool condition) {
    if (!condition) std::abort();
}

static RuntimeUserConfig Parse(const std::string& text) {
    std::istringstream input(text);
    return RuntimeConfigFile::ParseConfig(input);
}

int main() {
    for (std::string_view hand : {"left", "right", "off"}) {
        Require(Parse("[vr]\ncockpit_item_hand = \"" + std::string(hand) + "\"\n")
                    .vrCockpitItemHand == std::string(hand));
    }
    Require(std::string_view(RuntimeConfigFile::kVrCockpitItemHandDefault) == "left");
    Require(!Parse("[vr]\n").vrCockpitItemHand.has_value());
    Require(!Parse("[vr]\ncockpit_item_hand = 1\n").vrCockpitItemHand.has_value());
    Require(RuntimeConfigFile::kVrCockpitItemThrowDefault);
    Require(Parse("[vr]\ncockpit_item_throw = false\n").vrCockpitItemThrow == false);
    Require(Parse("[vr]\ncockpit_item_throw = true\n").vrCockpitItemThrow == true);
    Require(!Parse("[vr]\n").vrCockpitItemThrow.has_value());
    // [vr] placeholder_steering_wheel: the separate VR wheel or handlebar is opt-in.
    Require(!RuntimeConfigFile::kVrPlaceholderSteeringWheelDefault);
    Require(Parse("[vr]\nplaceholder_steering_wheel = true\n").vrPlaceholderSteeringWheel == true);
    Require(Parse("[vr]\nplaceholder_steering_wheel = false\n").vrPlaceholderSteeringWheel == false);
    Require(!Parse("[vr]\n").vrPlaceholderSteeringWheel.has_value());
    // [vr] foveation: the Quest's foveated rendering level, index-matched to
    // aurora_set_stereo_foveation.
    for (std::string_view level : RuntimeConfigFile::kVrFoveationLevels) {
        Require(Parse("[vr]\nfoveation = \"" + std::string(level) + "\"\n").vrFoveation == std::string(level));
    }
    Require(!Parse("[vr]\nfoveation = \"ultra\"\n").vrFoveation.has_value());
    Require(!Parse("[vr]\nfoveation = 2\n").vrFoveation.has_value());
    Require(!Parse("[vr]\n").vrFoveation.has_value());
#if defined(__ANDROID__)
    Require(std::string_view(RuntimeConfigFile::kVrFoveationDefault) == "medium");
#else
    Require(std::string_view(RuntimeConfigFile::kVrFoveationDefault) == "off");
#endif
    Require(RuntimeConfigFile::VrFoveationLevelIndex("off") == 0);
    Require(RuntimeConfigFile::VrFoveationLevelIndex("low") == 1);
    Require(RuntimeConfigFile::VrFoveationLevelIndex("medium") == 2);
    Require(RuntimeConfigFile::VrFoveationLevelIndex("high") == 3);
    Require(RuntimeConfigFile::VrFoveationLevelIndex("ultra") == 0);

    // [vr] refresh_rate: Hz asked of the runtime, 0 leaving its own. The Steam Frame
    // starts at 120, twice the game's 60.
    Require(Parse("[vr]\nrefresh_rate = 120\n").vrRefreshRate == 120u);
    Require(Parse("[vr]\nrefresh_rate = 0\n").vrRefreshRate == 0u);
    Require(Parse("[vr]\nrefresh_rate = 144\n").vrRefreshRate == 144u);
    Require(!Parse("[vr]\nrefresh_rate = 30\n").vrRefreshRate.has_value());
    Require(!Parse("[vr]\nrefresh_rate = 500\n").vrRefreshRate.has_value());
    Require(!Parse("[vr]\nrefresh_rate = -1\n").vrRefreshRate.has_value());
    Require(!Parse("[vr]\nrefresh_rate = \"120\"\n").vrRefreshRate.has_value());
    Require(!Parse("[vr]\n").vrRefreshRate.has_value());
#if defined(MKW_HEADSET_STEAM_FRAME)
    Require(RuntimeConfigFile::kVrRefreshRateDefault == 120u);
    Require(std::string_view(MKW_VR_REFRESH_RATE_DEFAULT_TEXT) == "120");
#else
    Require(RuntimeConfigFile::kVrRefreshRateDefault == 0u);
    Require(std::string_view(MKW_VR_REFRESH_RATE_DEFAULT_TEXT) == "0");
#endif

    // [vr] hand_tracking: the cockpit hands follow the headset's hand tracking.
    Require(Parse("[vr]\nhand_tracking = true\n").vrHandTracking == true);
    Require(Parse("[vr]\nhand_tracking = false\n").vrHandTracking == false);
    Require(!Parse("[vr]\n").vrHandTracking.has_value());
    Require(!Parse("[vr]\nhand_tracking = 1\n").vrHandTracking.has_value());
    Require(!RuntimeConfigFile::kVrHandTrackingDefault);

    // [vr] object_culling: false draws what the game camera culls. The PC
    // defaults to that; the Quest keeps the game's culling.
    Require(Parse("[vr]\nobject_culling = true\n").vrObjectCulling == true);
    Require(Parse("[vr]\nobject_culling = false\n").vrObjectCulling == false);
    Require(!Parse("[vr]\n").vrObjectCulling.has_value());
    Require(!Parse("[vr]\nobject_culling = 0\n").vrObjectCulling.has_value());
#if defined(__ANDROID__)
    Require(RuntimeConfigFile::kVrObjectCullingDefault);
    Require(std::string_view(MKW_VR_OBJECT_CULLING_DEFAULT_TOML) == "true");
#else
    Require(!RuntimeConfigFile::kVrObjectCullingDefault);
    Require(std::string_view(MKW_VR_OBJECT_CULLING_DEFAULT_TOML) == "false");
#endif

    // [vr] immersive_window and flat_screen: one race view in two keys, Flat
    // Screen mode winning, so a file that predates the window reads as before.
    using RuntimeConfigFile::VrRaceView;
    using RuntimeConfigFile::VrRaceViewOf;
    Require(Parse("[vr]\nimmersive_window = true\n").vrImmersiveWindow == true);
    Require(!Parse("[vr]\n").vrImmersiveWindow.has_value());
    Require(VrRaceViewOf(Parse("[vr]\n")) == VrRaceView::Immersive);
    Require(VrRaceViewOf(Parse("[vr]\nflat_screen = false\n")) == VrRaceView::Immersive);
    Require(VrRaceViewOf(Parse("[vr]\nflat_screen = true\n")) == VrRaceView::FlatScreen);
    Require(VrRaceViewOf(Parse("[vr]\nimmersive_window = true\n")) == VrRaceView::ImmersiveWindow);
    Require(VrRaceViewOf(Parse("[vr]\nflat_screen = true\nimmersive_window = true\n")) == VrRaceView::FlatScreen);
    Require(VrRaceViewOf(Parse("[vr]\nflat_screen = false\nimmersive_window = false\n")) == VrRaceView::Immersive);
    return 0;
}
