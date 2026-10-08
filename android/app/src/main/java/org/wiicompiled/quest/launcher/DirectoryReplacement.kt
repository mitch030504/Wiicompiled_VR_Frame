package org.wiicompiled.quest.launcher

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.Properties

/** A persisted commit decision keeps all old folders until every new folder is installed. */
object DirectoryReplacement {
    private fun backup(destination: File) = File(destination.parentFile, "${destination.name}.replaced")

    fun recover(journal: File) {
        if (!journal.exists()) return
        val state = Properties().apply { journal.inputStream().use { load(it) } }
        val committed = state.getProperty("committed") == "true"
        val count = state.getProperty("count").toInt()
        for (i in count - 1 downTo 0) {
            val destination = File(state.getProperty("destination.$i"))
            val staging = File(state.getProperty("staging.$i"))
            val old = backup(destination)
            if (committed) {
                if (old.exists() && !old.deleteRecursively()) throw IOException("Cannot remove $old")
            } else if (old.exists()) {
                if (destination.exists() && !destination.deleteRecursively()) throw IOException("Cannot remove $destination during rollback")
                if (!old.renameTo(destination)) throw IOException("Cannot restore $destination; recovery copy remains at $old")
            } else if (state.getProperty("existed.$i") == "false" && !staging.exists()) {
                if (destination.exists() && !destination.deleteRecursively()) throw IOException("Cannot roll back $destination")
            }
        }
        if (!journal.delete()) throw IOException("Cannot remove transaction journal $journal")
    }

    fun replaceAll(replacements: List<Pair<File, File>>, journal: File): String? {
        try {
            recover(journal)
            val state = Properties()
            state.setProperty("count", replacements.size.toString())
            replacements.forEachIndexed { i, (destination, staging) ->
                val singleJournal = File(destination.parentFile, ".${destination.name}.replacement")
                if (singleJournal != journal) recover(singleJournal)
                val old = backup(destination)
                // Recover installs made before transaction journals existed.
                if (!destination.exists() && old.exists() && !old.renameTo(destination)) throw IOException("Cannot restore $destination from $old")
                if (old.exists() && !old.deleteRecursively()) throw IOException("Cannot remove $old")
                if (!staging.isDirectory) throw IOException("Missing staged folder $staging")
                state.setProperty("destination.$i", destination.absolutePath)
                state.setProperty("staging.$i", staging.absolutePath)
                state.setProperty("existed.$i", destination.exists().toString())
            }
            writeJournal(journal, state)
            try {
                for ((destination, staging) in replacements) {
                    val old = backup(destination)
                    if (destination.exists() && !destination.renameTo(old)) throw IOException("Cannot replace $destination")
                    if (!staging.renameTo(destination)) throw IOException("Cannot install $destination")
                }
                state.setProperty("committed", "true")
                writeJournal(journal, state)
            } catch (failure: Exception) {
                try {
                    recover(journal)
                } catch (rollback: Exception) {
                    throw IOException("${failure.message}; rollback failed: ${rollback.message}. Keep $journal and the .replaced folders for recovery.", failure)
                }
                throw failure
            }
            // A committed journal makes cleanup retryable without undoing a successful install.
            try {
                recover(journal)
            } catch (cleanup: Exception) {
                return "The new files are installed, but cleanup must be retried: ${cleanup.message}"
            }
            return null
        } catch (failure: Exception) {
            return failure.message ?: "Could not replace the installed folders."
        }
    }

    private fun writeJournal(journal: File, state: Properties) {
        journal.parentFile?.mkdirs()
        val temporary = File(journal.parentFile, "${journal.name}.tmp")
        FileOutputStream(temporary).use { output ->
            state.store(output, null)
            output.fd.sync()
        }
        if (!temporary.renameTo(journal)) throw IOException("Cannot write transaction journal $journal")
    }
}
