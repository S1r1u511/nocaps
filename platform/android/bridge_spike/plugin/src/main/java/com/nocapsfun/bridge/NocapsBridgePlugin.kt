package com.nocapsfun.bridge

import android.content.Intent
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

class NocapsBridgePlugin(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName() = "NocapsBridge"

    override fun getPluginSignals(): Set<SignalInfo> =
        setOf(SignalInfo("echo_result", String::class.java))

    @UsedByGodot
    fun echo(value: String) {
        runOnHostThread {
            emitSignal("echo_result", value)
        }
    }

    /**
     * Opens the native share sheet with [text] (the crew invite). Plain-text
     * ACTION_SEND through createChooser; no permissions and no queries needed.
     */
    @UsedByGodot
    fun share_text(text: String) {
        val host = activity ?: return
        runOnUiThread {
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            host.startActivity(Intent.createChooser(send, null))
        }
    }
}
