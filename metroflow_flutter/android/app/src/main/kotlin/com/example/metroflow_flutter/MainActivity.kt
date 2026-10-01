package com.example.Metricorex_flutter

import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import me.leolin.shortcutbadger.ShortcutBadger

/**
 * MainActivity with the launcher-badge channel.
 *
 * Facebook-style unread badge on the app icon. ShortcutBadger covers the
 * launchers that matter (Samsung, Xiaomi/HyperOS, Oppo/OnePlus, Huawei and
 * most stock launchers); every call is best-effort — launchers that do not
 * support badges just no-op.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "metricorex/app_badge"

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
}
