// SPDX-License-Identifier: GPL-3.0-or-later

#include "update_check.h"

#include "runtime_config.h"

#include <array>
#include <charconv>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <string_view>
#include <system_error>
#include <thread>

// Updating itself is the Frame's build, installed by Launcher/steam-frame-install.sh: a desktop
// Linux game that holds its own build directory. Everywhere else the tab only reports the release
// it is running, which needs none of the machinery below.
#if defined(__linux__) && !defined(__ANDROID__)
#define MKW_UPDATE_CHECK_SUPPORTED 1
#include <sys/wait.h>
#else
#define MKW_UPDATE_CHECK_SUPPORTED 0
#endif

namespace update_check {
namespace {

// Written by Launcher/steam-frame-install.sh when it built on this machine, naming itself and the
// service that runs it. Its absence is what tells the tab this install is updated from a PC.
constexpr std::string_view kConfigFileName = "update.conf";
// An update's progress, and a check's answer. Separate files, so a check never overwrites the
// result of the update that opened the game.
constexpr std::string_view kStatusFileName = "update-status";
constexpr std::string_view kCheckStatusFileName = "update-status-check";
// What the Update button leaves for the update to pick up.
constexpr std::string_view kRequestFileName = "update-request";
// Stamped beside the executable by the install; absent for a build from a source tree.
constexpr std::string_view kReleaseTagFileName = ".release-tag";

// A finished update's status belongs on screen when the game opens right afterwards, which is what
// the update does. Older than this it is history, and the tab starts clean.
constexpr auto kStatusLifetime = std::chrono::hours(1);
// A running update rewrites its status at every step and every percent of its build, so one that
// has said nothing for this long was stopped without a chance to say so (the Frame lost power).
constexpr auto kRunningStatusLifetime = std::chrono::hours(2);
// The tab is drawn every frame; the files behind it are not read anywhere near that often.
constexpr auto kReadInterval = std::chrono::seconds(1);

std::string Trimmed(std::string_view text) {
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string_view::npos) {
        return {};
    }
    return std::string(text.substr(first, text.find_last_not_of(" \t\r\n") - first + 1));
}

std::string ReadFirstLine(const std::filesystem::path& file) {
    std::ifstream stream(file);
    std::string line;
    if (!stream || !std::getline(stream, line)) {
        return {};
    }
    return Trimmed(line);
}

struct Config {
    std::filesystem::path script;
    // The install's work directory, which holds the build the update reuses. The script defaults to
    // the same place, but an install given --work-dir does not live there.
    std::filesystem::path workDir;
    std::string service;

    bool Usable() const { return !script.empty() && !service.empty(); }
};

Config ReadConfig() {
    Config config;
#if !MKW_UPDATE_CHECK_SUPPORTED
    return config;
#else
    std::ifstream stream(RuntimeConfigFile::ApplicationDataDirectory() / kConfigFileName);
    if (!stream) {
        return config;
    }
    std::string line;
    while (std::getline(stream, line)) {
        const auto separator = line.find('=');
        if (line.empty() || line.front() == '#' || separator == std::string::npos) {
            continue;
        }
        const std::string key = Trimmed(std::string_view(line).substr(0, separator));
        const std::string value = Trimmed(std::string_view(line).substr(separator + 1));
        if (key == "script") {
            config.script = value;
        } else if (key == "work_dir") {
            config.workDir = value;
        } else if (key == "service") {
            config.service = value;
        }
    }
    std::error_code ec;
    if (!config.script.empty() && !std::filesystem::is_regular_file(config.script, ec)) {
        // The work directory was removed, so there is nothing here to update from any more.
        config.script.clear();
    }
    return config;
#endif
}

std::string InstalledRelease() {
    if (const auto executableDirectory = RuntimeConfigFile::ExecutableDirectory()) {
        return ReadFirstLine(*executableDirectory / kReleaseTagFileName);
    }
    return {};
}

// What this session has been told, which outranks the files until the game is next started: a check
// or update it asked for, and what came back.
std::mutex g_mutex;
bool g_sessionStateSet = false;
State g_sessionState = State::Idle;
std::string g_sessionDetail;
// What was last read from disk, and when, so drawing the tab does not re-read it every frame.
std::chrono::steady_clock::time_point g_lastRead;
bool g_haveRead = false;
bool g_haveFileState = false;
State g_fileState = State::Idle;
std::string g_fileDetail;
bool g_canUpdate = false;
// The release this process was started from, read once: an update replaces the stamp on disk while
// the old build is still the one running. The stamp as it is now tells whether that has happened.
std::string g_runningRelease;
bool g_haveRunningRelease = false;
std::string g_releaseOnDisk;

void SetSessionState(State state, std::string detail) {
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_sessionStateSet = true;
    g_sessionState = state;
    g_sessionDetail = std::move(detail);
}

std::string ShellQuoted(const std::string& text) {
    std::string quoted = "'";
    for (const char character : text) {
        if (character == '\'') {
            quoted += "'\\''";
        } else {
            quoted += character;
        }
    }
    quoted += '\'';
    return quoted;
}

// Runs `command`, returning its exit status and keeping the last line of its output for a message.
int Run(const std::string& command, std::string& lastLine) {
    lastLine.clear();
#if !MKW_UPDATE_CHECK_SUPPORTED
    (void)command;
    return -1;
#else
    FILE* pipe = popen(command.c_str(), "r");
    if (pipe == nullptr) {
        return -1;
    }
    std::array<char, 512> buffer{};
    while (std::fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
        if (const std::string line = Trimmed(buffer.data()); !line.empty()) {
            lastLine = line;
        }
    }
    const int status = pclose(pipe);
    if (status == -1 || !WIFEXITED(status)) {
        return -1;
    }
    return WEXITSTATUS(status);
#endif
}

// Reads a "<state>\t<unix time>\t<text>" line the script wrote. False when there is none, it is too
// old to be about now, or it cannot be understood.
bool ReadStatusFile(const std::filesystem::path& file, State& state, std::string& detail) {
    const std::string line = ReadFirstLine(file);
    if (line.empty()) {
        return false;
    }
    const auto firstTab = line.find('\t');
    const auto secondTab = line.find('\t', firstTab + 1);
    if (firstTab == std::string::npos || secondTab == std::string::npos) {
        return false;
    }
    const std::string written = line.substr(0, firstTab);
    long long seconds = 0;
    const char* const secondsBegin = line.data() + firstTab + 1;
    if (std::from_chars(secondsBegin, line.data() + secondTab, seconds).ec != std::errc{}) {
        return false;
    }
    const auto age = std::chrono::system_clock::now() -
                     std::chrono::system_clock::time_point(std::chrono::seconds(seconds));
    const auto lifetime = written == "running" ? kRunningStatusLifetime : kStatusLifetime;
    if (age > lifetime || age < -lifetime) {
        return false;
    }
    if (written == "running") {
        state = State::Updating;
    } else if (written == "available") {
        state = State::Available;
    } else if (written == "uptodate" || written == "done") {
        state = State::UpToDate;
    } else if (written == "failed") {
        state = State::Failed;
    } else {
        return false;
    }
    detail = line.substr(secondTab + 1);
    return true;
}

} // namespace

Status Current() {
    const std::lock_guard<std::mutex> lock(g_mutex);
    // Drawn every frame, so the files behind it are read on a timer instead.
    const auto now = std::chrono::steady_clock::now();
    if (!g_haveRead || now - g_lastRead > kReadInterval) {
        g_releaseOnDisk = InstalledRelease();
        if (!g_haveRunningRelease) {
            g_runningRelease = g_releaseOnDisk;
            g_haveRunningRelease = true;
        }
        g_lastRead = now;
        g_haveRead = true;
        g_canUpdate = ReadConfig().Usable();
        g_fileState = State::Idle;
        g_fileDetail.clear();
        g_haveFileState = ReadStatusFile(RuntimeConfigFile::ApplicationDataDirectory() / kStatusFileName,
                                         g_fileState, g_fileDetail);
    }

    Status status;
    status.installedRelease = g_runningRelease;
    status.restartNeeded = g_releaseOnDisk != g_runningRelease;
    if (!g_canUpdate) {
        status.state = State::PcInstall;
        return status;
    }
    // An update's own reports outrank what this session last said: one started here (the session
    // says Updating until the update writes its first step), or one this game was reopened after.
    const bool followUpdate = !g_sessionStateSet || g_sessionState == State::Updating;
    if (followUpdate && g_haveFileState) {
        status.state = g_fileState;
        status.detail = g_fileDetail;
    } else if (g_sessionStateSet) {
        status.state = g_sessionState;
        status.detail = g_sessionDetail;
    } else {
        status.state = State::Idle;
    }
    return status;
}

void StartCheck() {
    {
        const std::lock_guard<std::mutex> lock(g_mutex);
        if (g_sessionStateSet && (g_sessionState == State::Checking || g_sessionState == State::Updating)) {
            return;
        }
    }
    const Config config = ReadConfig();
    if (!config.Usable()) {
        return;
    }
    SetSessionState(State::Checking, "Asking github.com for the newest release");

    // Detached: it talks to the network and must not hold up a frame, and there is no shutdown
    // ordering to manage because it touches nothing the game owns.
    std::thread([config] {
        const auto statusFile = RuntimeConfigFile::ApplicationDataDirectory() / kCheckStatusFileName;
        std::error_code ec;
        std::filesystem::remove(statusFile, ec);
        std::string command = "WIICOMPILED_UPDATE_STATUS=" + ShellQuoted(statusFile.string()) + ' ' +
                              ShellQuoted(config.script.string()) + " --check";
        if (!config.workDir.empty()) {
            command += " --work-dir " + ShellQuoted(config.workDir.string());
        }
        command += " 2>&1";
        std::string lastLine;
        const int exitStatus = Run(command, lastLine);

        State state = State::Failed;
        std::string detail;
        if (ReadStatusFile(statusFile, state, detail)) {
            SetSessionState(state, detail);
        } else if (exitStatus == 0) {
            // It ran and said nothing this can read, which is still an answer: ask again later.
            SetSessionState(State::Idle, "The check said nothing this version understands");
        } else {
            std::cerr << "[update] the check failed (exit " << exitStatus << "): " << lastLine << std::endl;
            SetSessionState(State::Failed,
                            lastLine.empty() ? "The check could not be run" : lastLine);
        }
        std::filesystem::remove(statusFile, ec);
    }).detach();
}

bool StartUpdate(std::string& error) {
    error.clear();
    const Config config = ReadConfig();
    if (!config.Usable()) {
        error = "This build was installed from a PC, so the update is run there.";
        return false;
    }

    const auto dataDirectory = RuntimeConfigFile::ApplicationDataDirectory();
    std::error_code ec;
    std::filesystem::create_directories(dataDirectory, ec);
    // How the update opens the game again when it is done. Steam names the running title; without
    // one (a build started from a terminal) the update still runs and the game is started by hand.
    std::string steamGameId;
    for (const char* variable : {"SteamGameId", "SteamAppId"}) {
        if (const char* value = std::getenv(variable); value != nullptr && *value != '\0') {
            steamGameId = value;
            break;
        }
    }
    {
        std::ofstream request(dataDirectory / kRequestFileName, std::ios::trunc);
        if (!request) {
            error = "Could not write to " + dataDirectory.string();
            return false;
        }
        request << "# Written by the game's Update button; the update removes it.\n";
        if (!steamGameId.empty()) {
            request << "steam_game_id=" << steamGameId << '\n';
        }
    }
    // The previous update's result must not be read as this one's before it has written anything.
    std::filesystem::remove(dataDirectory / kStatusFileName, ec);
    // The update must outlive the game if the player closes it meanwhile, and Steam ends the game's
    // own processes when it closes, so it runs as a service of its own. --no-block: started, not
    // waited for.
    std::string lastLine;
    const std::string command =
        "systemctl --user start --no-block " + ShellQuoted(config.service) + " 2>&1";
    if (const int exitStatus = Run(command, lastLine); exitStatus != 0) {
        std::filesystem::remove(dataDirectory / kRequestFileName, ec);
        std::cerr << "[update] could not start " << config.service << " (exit " << exitStatus
                  << "): " << lastLine << std::endl;
        error = lastLine.empty() ? "Could not start the update service" : lastLine;
        return false;
    }
    SetSessionState(State::Updating, "Starting the update");
    // Read the files again at once, rather than show the removed status for up to a second.
    const std::lock_guard<std::mutex> lock(g_mutex);
    g_haveRead = false;
    return true;
}

} // namespace update_check

#undef MKW_UPDATE_CHECK_SUPPORTED
