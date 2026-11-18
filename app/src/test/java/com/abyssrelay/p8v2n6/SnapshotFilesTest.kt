package com.abyssrelay.p8v2n6

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

class SnapshotFilesTest {
    @Test fun replacementRetainsPreviousCompleteSnapshot() {
        val dir = Files.createTempDirectory("abyss-save-test").toFile()
        try {
            assertTrue(SnapshotFiles.write(dir, "relay_auto.json", "first complete snapshot"))
            assertTrue(SnapshotFiles.write(dir, "relay_auto.json", "вторая запись: 深海"))
            assertEquals("вторая запись: 深海", File(dir, "relay_auto.json").readText())
            assertEquals("first complete snapshot", File(dir, "relay_auto.json.bak").readText())
            assertFalse(File(dir, "relay_auto.json.tmp").exists())
        } finally { dir.deleteRecursively() }
    }

    @Test fun rejectsPathsOutsideKnownSaveSlots() {
        val dir = Files.createTempDirectory("abyss-path-test").toFile()
        try {
            assertFalse(SnapshotFiles.write(dir, "../escape.json", "invalid"))
            assertFalse(SnapshotFiles.write(dir, "settings.json", "invalid"))
            assertTrue(SnapshotFiles.write(dir, "relay_1.json", "valid"))
        } finally { dir.deleteRecursively() }
    }

    @Test fun writeFailureIsReportedWithoutClaimingSuccess() {
        val blocked = Files.createTempFile("abyss-blocked", ".tmp").toFile()
        try { assertFalse(SnapshotFiles.write(blocked, "relay_auto.json", "data")) }
        finally { blocked.delete() }
    }
}
