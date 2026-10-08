package org.wiicompiled.quest.launcher

import android.content.Context
import java.io.File
import org.wiicompiled.quest.GameStorage
import org.wiicompiled.quest.BuildConfig

/** Checks and swaps shared by every [GameSetup] task. */
object GameFiles {

    val checks = DiscChecks(BuildConfig.DISC_GAME_ID, BuildConfig.DISC_DOL_SHA256, BuildConfig.DISC_REL_SHA256)

    /**
     * InstallerEngine.ValidateExtractedGame (the PC installer): the files the runtime needs, with
     * the pinned hashes. Null when [root] is a usable DATA folder.
     */
    fun validateData(root: File): String? {
        val dol = File(root, DiscChecks.DOL_PATH)
        val rel = File(root, DiscChecks.REL_PATH)
        if (!dol.isFile || !rel.isFile || !File(root, DiscChecks.FST_PATH).isFile) {
            return "The game files are missing required Mario Kart Wii files."
        }
        return checks.revisionError(dol.readBytes(), rel.readBytes())
    }

    /**
     * Moves [staging] to [destination], keeping the old destination until the new one is in
     * place. Null on success, otherwise the message to show.
     */
    fun replace(destination: File, staging: File): String? = DirectoryReplacement.replaceAll(
        listOf(destination to staging), File(destination.parentFile, ".${destination.name}.replacement"),
    )

    fun recover(context: Context) {
        val games = File(context.filesDir, "game")
        DirectoryReplacement.recover(File(games, ".import-transaction"))
        for (parent in listOf(games, GameStorage.gameRoot(context))) {
            parent.listFiles { file -> file.name.startsWith(".") && file.name.endsWith(".replacement") }
                ?.forEach { DirectoryReplacement.recover(it) }
        }
    }

    fun gigabytes(bytes: Long) = "%.1f GB".format(bytes / 1_000_000_000.0)
}
