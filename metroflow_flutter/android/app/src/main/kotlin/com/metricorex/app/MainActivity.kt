package com.metricorex.app

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import me.leolin.shortcutbadger.ShortcutBadger

/**
 * MainActivity with two channels:
 *
 * 1. "metricorex/app_badge" — Facebook-style unread badge on the app icon.
 *    ShortcutBadger covers the launchers that matter (Samsung, Xiaomi/HyperOS,
 *    Oppo/OnePlus, Huawei and most stock launchers); every call is
 *    best-effort — launchers that do not support badges just no-op.
 *
 * 2. "metricorex/audio" — REAL call audio output routing (speaker / earpiece /
 *    bluetooth). The previous implementation only toggled
 *    `Helper.setSpeakerphoneOn` through flutter_webrtc, which:
 *      - could NOT select a specific Bluetooth headset (BT only worked when
 *        the OS happened to pick it),
 *      - is deprecated on Android 12+ where the communication route is a
 *        first-class device selection (`AudioManager.setCommunicationDevice`).
 *    We now resolve the requested route against
 *    `availableCommunicationDevices` and pin it, so speaker, earpiece and
 *    every connected Bluetooth headset are switchable mid-call — the same
 *    primitive Google Dialer uses.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "metricorex/app_badge"
    private val audioChannelName = "metricorex/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBadge" -> {
                        val count = call.argument<Int>("count") ?: 0
                        result.success(applyBadge(count))
                    }
                    "clearBadge" -> {
                        result.success(applyBadge(0))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listOutputs" -> result.success(listAudioOutputs())
                    "setRoute" -> {
                        val route = call.argument<String>("route") ?: "speaker"
                        result.success(applyAudioRoute(route))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun applyBadge(count: Int): Boolean {
        return try {
            if (count > 0) {
                ShortcutBadger.applyCount(applicationContext as Context, count)
            } else {
                ShortcutBadger.removeCount(applicationContext as Context)
            }
        } catch (e: Exception) {
            false
        }
    }

    // -----------------------------------------------------------------------
    // Audio routing
    // -----------------------------------------------------------------------

    private fun audioManager(): AudioManager? {
        return try {
            applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        } catch (e: Exception) {
            null
        }
    }

    private fun deviceTypeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "wired"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth_a2dp"
        else -> "other"
    }

    private fun listAudioOutputs(): List<Map<String, Any>> {
        val am = audioManager() ?: return emptyList()
        return try {
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { d ->
                mapOf(
                    "id" to d.id,
                    "productName" to (d.productName?.toString() ?: ""),
                    "type" to deviceTypeName(d.type),
                    "isBluetooth" to (deviceTypeName(d.type) == "bluetooth" ||
                        deviceTypeName(d.type) == "bluetooth_a2dp")
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /// Pin the communication-audio route to the requested output.
    /// route: "speaker" | "earpiece" | "bluetooth" (first connected BT SCO /
    /// BLE headset, or fall back to letting the OS pick).
    private fun applyAudioRoute(route: String): Boolean {
        val am = audioManager() ?: return false
        return try {
            val wantedType: Int? = when (route) {
                "speaker" -> AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                "earpiece" -> AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                "bluetooth" -> null // any BT SCO / BLE headset, resolved below
                else -> null
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val available = try { am.availableCommunicationDevices } catch (e: Exception) { emptyList() }
                val target: AudioDeviceInfo? = if (route == "bluetooth") {
                    available.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                    } ?: available.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
                    }
                } else if (wantedType != null) {
                    available.firstOrNull { it.type == wantedType }
                } else null

                if (target != null) {
                    // setCommunicationDevice also handles SCO start/stop for BT.
                    val ok = am.setCommunicationDevice(target)
                    if (ok) return true
                    // fall through to the legacy path if the platform refused.
                }
            }

            // Legacy fallback (pre-S, or setCommunicationDevice refused):
            when (route) {
                "speaker" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try { am.clearCommunicationDevice() } catch (e: Exception) {}
                    }
                    am.isSpeakerphoneOn = true
                }
                "earpiece" -> {
                    try { am.stopBluetoothSco() } catch (e: Exception) {}
                    am.isSpeakerphoneOn = false
                }
                "bluetooth" -> {
                    am.isSpeakerphoneOn = false
                    try { am.startBluetoothSco() } catch (e: Exception) {}
                    try { am.isBluetoothScoOn = true } catch (e: Exception) {}
                }
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
