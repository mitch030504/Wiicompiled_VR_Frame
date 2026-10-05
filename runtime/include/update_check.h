// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <string>

// Settings > Updates: whether a newer release of the game exists, and, on a Frame that holds its own
// build, updating to it without leaving the headset.
//
// Both answers come from Launcher/steam-frame-install.sh, which already knows how to compare
// versions and how to build: `--check` reports, `--update` installs. The update reports its progress
// through a status file rather than Steam notifications, which the Frame's Steam does not show.
// The install writes update.conf beside the player's configuration when it put a build on this
// machine, so the Update button appears only where it can actually work; installed from a PC, the
// tab says to update there.
namespace update_check {

enum class State {
    // This install cannot update itself: it was built on a PC, which is where updates are run.
    PcInstall,
    // It can, and nothing has been asked of it yet this session.
    Idle,
    Checking,
    UpToDate,
    Available,
    // An update is running beside the game, as a service of its own: it carries on if the game is
    // closed, and then opens it again when it is done.
    Updating,
    Failed,
};

struct Status {
    State state = State::PcInstall;
    // The release this build came from, or empty when it was built from a source tree.
    std::string installedRelease;
    // One line under the state: which release is available, what failed, or what step is running.
    std::string detail;
    // An update has installed a different build since this one started: it takes effect when the
    // game is started again.
    bool restartNeeded = false;
};

// What the Updates tab draws. Cheap enough to call every frame: a check or update in flight is
// answered from memory, and otherwise the files behind it are re-read at most once a second.
Status Current();

// Whether there is an Updates tab to show at all: this install can update itself, or it at least
// knows which release it is running. Neither is true of a build that came from somewhere else.
inline bool Relevant(const Status& status) {
    return status.state != State::PcInstall || !status.installedRelease.empty();
}

// Asks the install script whether a newer release exists, in the background. Returns at once.
void StartCheck();

// Starts the update in the background: its own systemd user service runs the install script, which
// reports each step to the file Current() reads, so the game can stay open and show the progress.
// On false, `error` says why, for display.
bool StartUpdate(std::string& error);

} // namespace update_check
