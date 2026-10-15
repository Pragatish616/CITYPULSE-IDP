package com.citypulse.citypulse_app

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.concurrent.thread

/**
 * Finds the route-question model file (ADR-035, PREREGISTRATION_QA.md addendum 5).
 *
 * A measurement build carries the model as an Android asset (`models/route_qa.gguf`, stored uncompressed). llama.cpp needs a real file,
 * so the first call copies it into the app's private files folder (a streamed copy, never the whole file in memory) and later calls
 * reuse it. A file placed by hand in the app's external files folder (`.../files/models/route_qa.gguf`) is used when the asset is absent.
 * A normal build carries neither and the call returns null.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "citypulse/qa_model")
            .setMethodCallHandler { call, result ->
                if (call.method != "modelPath") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val main = Handler(Looper.getMainLooper())
                thread(name = "qa-model-path") {
                    try {
                        val path = locateModel()
                        main.post { result.success(path) }
                    } catch (e: Exception) {
                        main.post { result.error("model", e.message, null) }
                    }
                }
            }
    }

    private fun locateModel(): String? {
        val assetName = "models/route_qa.gguf"
        val inBundle = assets.list("models")?.contains("route_qa.gguf") == true
        if (inBundle) {
            val dir = File(filesDir, "models").apply { mkdirs() }
            val target = File(dir, "route_qa.gguf")
            val stamp = File(dir, "route_qa.gguf.stamp")
            // The files folder survives an app update, so the copy is keyed on this install's update time and the asset's size.
            val size = try {
                assets.openFd(assetName).use { it.length }
            } catch (e: Exception) {
                -1L
            }
            val updated = packageManager.getPackageInfo(packageName, 0).lastUpdateTime
            val key = "$updated:$size"
            if (target.exists() && target.length() > 0 && stamp.exists() && stamp.readText() == key) {
                return target.absolutePath
            }
            stamp.delete()
            val tmp = File(dir, "route_qa.gguf.part")
            assets.open(assetName).use { input ->
                FileOutputStream(tmp).use { output -> input.copyTo(output, 1 shl 20) }
            }
            if (tmp.length() == 0L || (size > 0 && tmp.length() != size)) {
                tmp.delete()
                throw IllegalStateException("model copy incomplete")
            }
            if (target.exists()) target.delete()
            if (!tmp.renameTo(target)) throw IllegalStateException("model rename failed")
            stamp.writeText(key)
            return target.absolutePath
        }
        val byHand = File(getExternalFilesDir(null), "models/route_qa.gguf")
        return if (byHand.exists()) byHand.absolutePath else null
    }
}
