package com.abyssrelay.p8v2n6

import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.godotengine.godot.variant.Callable
import java.util.concurrent.atomic.AtomicBoolean

/** Persists a completed-frame snapshot even when Android has paused the renderer. */
class RelayLifecycle(godot: Godot) : GodotPlugin(godot) {
    @Volatile private var controllerId: Long = 0
    @Volatile private var latestEnvelope = ""
    private val pauseRequested = AtomicBoolean(false)

    override fun getPluginName() = "RelayLifecycle"

    @UsedByGodot
    fun register_controller(instanceId: Long) { controllerId = instanceId }

    @UsedByGodot
    fun cache_snapshot(envelope: String) { latestEnvelope = envelope }

    @UsedByGodot
    fun write_snapshot(name: String, envelope: String): Boolean {
        val directory = activity?.filesDir ?: return false
        if (name == "relay_auto.json") latestEnvelope = envelope
        return SnapshotFiles.write(directory, name, envelope)
    }

    fun pauseBeforeEngineSuspends() {
        val id = controllerId
        if (id == 0L || !pauseRequested.compareAndSet(false, true)) return
        // Do not wait for a paused GL thread. The immutable envelope is refreshed
        // every second and immediately after player commands on the render thread.
        val snapshot = latestEnvelope
        if (snapshot.isNotEmpty()) {
            Log.i("AbyssRelay", "Background snapshot persisted: ${write_snapshot("relay_auto.json", snapshot)}")
        }
        godot.runOnRenderThread { Callable.call(id, "_android_prepare_pause") }
    }

    fun resumePaused() {
        pauseRequested.set(false)
        val id = controllerId
        if (id != 0L) godot.runOnRenderThread { Callable.call(id, "_android_did_resume") }
    }

    override fun onMainDestroy() { controllerId = 0 }
}
