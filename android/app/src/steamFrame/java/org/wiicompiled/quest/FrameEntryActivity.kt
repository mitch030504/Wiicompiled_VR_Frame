package org.wiicompiled.quest

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import org.wiicompiled.quest.launcher.LauncherActivity
import org.wiicompiled.quest.launcher.ModLibrary

/**
 * The Steam Frame's library entry. Lepton starts the one real activity that is both MAIN and
 * LAUNCHER, in VR when it carries a VR category, and ignores activity-aliases, so neither of the
 * Quest flavours' entries works there. This one shows nothing: the setup panel (LauncherActivity)
 * always opens, and when the selected game can start as it is, the game opens on top of it, so the
 * headset goes straight into VR and quitting the game comes back to the panel.
 */
class FrameEntryActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val launcher = Intent(this, LauncherActivity::class.java)
        if (readyToPlay()) {
            Log.i(TAG, "Starting the game over the setup panel")
            startActivities(arrayOf(launcher, Intent(this, QuestActivity::class.java)))
        } else {
            Log.i(TAG, "The game is not ready to start; opening the setup panel")
            startActivity(launcher)
        }
        finish()
    }

    /**
     * What Home's Play needs (LauncherActivity), short of the steps only the panel performs: the
     * game files and the selected game built for this app, Retro Rewind's pack, and no enabled mods
     * to copy into the pack's Patches folder first.
     */
    private fun readyToPlay(): Boolean = runCatching {
        val profile = GameProfile.selected(this)
        GameStorage.discStatus(this) == GameStorage.DiscStatus.Ready &&
            GameLibrary.status(this, profile) == GameLibrary.Status.Ready &&
            GameStorage.modContentReady(this, profile) &&
            (!profile.modPack || ModLibrary.load(GameStorage.modsDirectory(this)).none { it.enabled })
    }.getOrElse {
        Log.w(TAG, "Could not check the installed game", it)
        false
    }

    private companion object {
        // The launcher's tag, so the usual `adb logcat -s WiiCompiledLauncher` shows the routing.
        const val TAG = "WiiCompiledLauncher"
    }
}
