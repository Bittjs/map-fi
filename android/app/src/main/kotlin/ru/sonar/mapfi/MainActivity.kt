package ru.sonar.mapfi

import android.media.MediaDrm
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.mapfi/device_id"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getWidevineId") {
                val widevineId = getWidevineDeviceId()
                if (widevineId != null) {
                    result.success(widevineId)
                } else {
                    result.error("UNAVAILABLE", "Widevine DRM ID is not available.", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getWidevineDeviceId(): String? {
        return try {
            val widevineUuid = UUID.fromString("edef8ba9-79d6-4ace-a3c8-27dcd51d21ed")
            val mediaDrm = MediaDrm(widevineUuid)
            val deviceUniqueId = mediaDrm.getPropertyByteArray(MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
            mediaDrm.release()
            deviceUniqueId.joinToString("") { String.format("%02x", it) }
        } catch (e: Exception) {
            null
        }
    }
}