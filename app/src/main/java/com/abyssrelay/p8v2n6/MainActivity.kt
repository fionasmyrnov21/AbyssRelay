package com.abyssrelay.p8v2n6

import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin

/** Native Android host. Gameplay is packaged from the versioned Godot project. */
class MainActivity : GodotActivity() {
    private var lifecycleBridge: RelayLifecycle? = null

    override fun getHostPlugins(engine: Godot): Set<GodotPlugin> {
        val bridge = lifecycleBridge ?: RelayLifecycle(engine).also { lifecycleBridge = it }
        return super.getHostPlugins(engine) + bridge
    }

    override fun onPause() {
        lifecycleBridge?.pauseBeforeEngineSuspends()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        lifecycleBridge?.resumePaused()
    }

    override fun getCommandLine(): MutableList<String> =
        super.getCommandLine().toMutableList().apply {
            add("--main-pack")
            add("res://abyss.pck")
            add("--rendering-method")
            add("gl_compatibility")
        }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        // Flush before Godot suspends rendering on focus loss, rather than
        // enqueueing the save after its render thread has already paused.
        if (!hasFocus) lifecycleBridge?.pauseBeforeEngineSuspends()
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            lifecycleBridge?.resumePaused()
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            WindowCompat.getInsetsController(window, window.decorView).apply {
                hide(WindowInsetsCompat.Type.systemBars())
                systemBarsBehavior =
                    WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        }
    }

}
