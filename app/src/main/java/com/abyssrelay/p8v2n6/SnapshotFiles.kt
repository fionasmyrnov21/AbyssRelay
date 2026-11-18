package com.abyssrelay.p8v2n6

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** One writer for native lifecycle flushes and engine-requested saves. */
internal object SnapshotFiles {
    private val lock = Any()
    private val names = setOf("relay_auto.json", "relay_1.json", "relay_2.json", "relay_3.json")

    fun write(directory: File, name: String, envelope: String): Boolean = synchronized(lock) {
        if (name !in names) return@synchronized false
        try {
            if (!directory.isDirectory && !directory.mkdirs()) return@synchronized false
            val target = File(directory, name)
            val temporary = File(directory, "$name.tmp")
            val backup = File(directory, "$name.bak")
            FileOutputStream(temporary).use { stream ->
                stream.write(envelope.toByteArray(StandardCharsets.UTF_8))
                stream.fd.sync()
            }
            if (target.exists()) Files.move(target.toPath(), backup.toPath(),
                StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            Files.move(temporary.toPath(), target.toPath(),
                StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            true
        } catch (_: IOException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
