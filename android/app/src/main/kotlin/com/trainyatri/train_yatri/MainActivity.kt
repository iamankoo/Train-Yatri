package com.trainyatri.train_yatri

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Block 4's only native code: hands a downloaded update APK off to
 * Android's own package installer (lib/services/update/apk_installer.dart
 * is the Dart-side caller). Deliberately a hand-written platform
 * channel rather than a plugin - see the path_provider comment in
 * pubspec.yaml.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "trainyatri.app/apk_installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARGUMENT", "Missing 'path' argument", null)
                            return@setMethodCallHandler
                        }
                        try {
                            startInstallIntent(path)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("INSTALL_FAILED", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Starts Android's own ACTION_VIEW package-install flow for [path].
     * This only *launches* that system UI - Android itself, not this
     * app, is what shows the "install this app?" / "allow installs
     * from this source?" confirmation before anything is actually
     * installed.
     */
    private fun startInstallIntent(path: String) {
        val apkFile = File(path)
        val authority = "$packageName.fileprovider"
        val apkUri: Uri = FileProvider.getUriForFile(this, authority, apkFile)

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }
}
