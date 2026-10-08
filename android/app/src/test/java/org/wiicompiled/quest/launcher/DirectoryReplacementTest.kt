package org.wiicompiled.quest.launcher

import java.io.File
import java.nio.file.Files
import java.util.Properties
import org.junit.Assert.*
import org.junit.Test

class DirectoryReplacementTest {
    private fun tree(parent: File, name: String, contents: String): File = File(parent, name).apply {
        mkdirs()
        File(this, "contents").writeText(contents)
    }

    private fun interrupted(journal: File, pairs: List<Pair<File, File>>, existed: List<Boolean>, committed: Boolean = false) {
        val state = Properties().apply {
            setProperty("count", pairs.size.toString())
            setProperty("committed", committed.toString())
            pairs.forEachIndexed { i, (destination, staging) ->
                setProperty("destination.$i", destination.absolutePath)
                setProperty("staging.$i", staging.absolutePath)
                setProperty("existed.$i", existed[i].toString())
            }
        }
        journal.outputStream().use { state.store(it, null) }
    }

    @Test fun restoresLegacyBackupBeforeAnotherAttempt() {
        val root = Files.createTempDirectory("replacement").toFile()
        try {
            val destination = File(root, "DATA")
            tree(root, "DATA.replaced", "old")
            val result = DirectoryReplacement.replaceAll(listOf(destination to File(root, "missing")), File(root, "journal"))
            assertNotNull(result)
            assertEquals("old", File(destination, "contents").readText())
        } finally { root.deleteRecursively() }
    }

    @Test fun rollsBackEveryFolderWhenALaterMoveFails() {
        val root = Files.createTempDirectory("replacement").toFile()
        try {
            val data = tree(root, "DATA", "old data")
            val pack = tree(root, "pack", "old pack")
            val stagedData = tree(root, "new-data", "new data")
            // The nested staging folder is moved away with pack, forcing the second install to fail.
            val stagedPack = tree(pack, "new-pack", "new pack")
            val journal = File(root, "journal")
            assertNotNull(DirectoryReplacement.replaceAll(listOf(data to stagedData, pack to stagedPack), journal))
            assertEquals("old data", File(data, "contents").readText())
            assertEquals("old pack", File(pack, "contents").readText())
            assertFalse(journal.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun interruptedImportRestoresAllOldFolders() {
        val root = Files.createTempDirectory("replacement").toFile()
        try {
            val data = tree(root, "DATA", "new data")
            tree(root, "DATA.replaced", "old data")
            val pack = File(root, "pack")
            tree(root, "pack.replaced", "old pack")
            val stagedPack = tree(root, "new-pack", "new pack")
            val journal = File(root, "journal")
            interrupted(journal, listOf(data to File(root, "new-data"), pack to stagedPack), listOf(true, true))
            DirectoryReplacement.recover(journal)
            assertEquals("old data", File(data, "contents").readText())
            assertEquals("old pack", File(pack, "contents").readText())
            assertTrue(stagedPack.exists())
            assertFalse(journal.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun interruptedFirstInstallRemovesOnlyPublishedFolders() {
        val root = Files.createTempDirectory("replacement").toFile()
        try {
            val data = tree(root, "DATA", "new data")
            val journal = File(root, "journal")
            interrupted(journal, listOf(data to File(root, "new-data")), listOf(false))
            DirectoryReplacement.recover(journal)
            assertFalse(data.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun committedImportKeepsNewFoldersAndFinishesCleanup() {
        val root = Files.createTempDirectory("replacement").toFile()
        try {
            val data = tree(root, "DATA", "new data")
            val old = tree(root, "DATA.replaced", "old data")
            val journal = File(root, "journal")
            interrupted(journal, listOf(data to File(root, "new-data")), listOf(true), committed = true)
            DirectoryReplacement.recover(journal)
            assertEquals("new data", File(data, "contents").readText())
            assertFalse(old.exists())
            assertFalse(journal.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun importRecoversAnEarlierSingleFolderTransaction() {
        val root = Files.createTempDirectory("replacement").toFile()
        try {
            val data = tree(root, "DATA", "unfinished new data")
            tree(root, "DATA.replaced", "old data")
            val single = File(root, ".DATA.replacement")
            interrupted(single, listOf(data to File(root, "previous-stage")), listOf(true))
            val journal = File(root, "import-journal")
            assertNotNull(DirectoryReplacement.replaceAll(listOf(data to File(root, "missing")), journal))
            assertEquals("old data", File(data, "contents").readText())
            assertFalse(single.exists())
            assertFalse(journal.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun successfulImportPublishesEverything() {
        val root = Files.createTempDirectory("replacement").toFile()
        try {
            val data = tree(root, "DATA", "old data")
            val library = tree(root, "library", "old library")
            val stagedData = tree(root, "new-data", "new data")
            val stagedLibrary = tree(root, "new-library", "new library")
            val journal = File(root, "journal")
            assertNull(DirectoryReplacement.replaceAll(listOf(data to stagedData, library to stagedLibrary), journal))
            assertEquals("new data", File(data, "contents").readText())
            assertEquals("new library", File(library, "contents").readText())
            assertFalse(journal.exists())
            assertFalse(File(root, "DATA.replaced").exists())
        } finally { root.deleteRecursively() }
    }
}
