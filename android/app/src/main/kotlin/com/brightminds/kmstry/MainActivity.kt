package com.brightminds.kmstry

import android.os.Build
import android.view.KeyEvent
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "app/video_mirror"
    private val volumeShutterChannelName = "app/volume_shutter"
    private var volumeShutterChannel: MethodChannel? = null
    private var volumeShutterEnabled = false

    @OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "mirror") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("BAD_ARGS", "path is null", null)
                    return@setMethodCallHandler
                }
                mirrorVideo(path, result)
            }

        volumeShutterChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            volumeShutterChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "setEnabled") {
                    volumeShutterEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isVolumeButton = event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if (volumeShutterEnabled && isVolumeButton) {
            if (event.action == KeyEvent.ACTION_UP) {
                volumeShutterChannel?.invokeMethod("onVolumeShutter", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    @OptIn(UnstableApi::class)
    private fun mirrorVideo(inputPath: String, result: MethodChannel.Result) {
        try {
            val outFile = File(cacheDir, "${System.currentTimeMillis()}_m.mp4")
            val outputPath = outFile.absolutePath

            // Yatay flip = X ekseninde -1 ölçek (GPU üzerinde, donanım hızlandırmalı).
            val flip: Effect = ScaleAndRotateTransformation.Builder()
                .setScale(-1f, 1f)
                .build()

            val editedItem = EditedMediaItem.Builder(MediaItem.fromUri("file://$inputPath"))
                .setEffects(Effects(/* audioProcessors = */ emptyList(), /* videoEffects = */ listOf(flip)))
                .build()

            val transformer = Transformer.Builder(this)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        result.success(outputPath)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        result.error("MIRROR_FAILED", exportException.message, null)
                    }
                })
                .build()

            // Transformer ana thread (Looper) gerektirir; channel handler zaten ana thread'de.
            transformer.start(editedItem, outputPath)
        } catch (e: Exception) {
            result.error("MIRROR_FAILED", e.message, null)
        }
    }
}
