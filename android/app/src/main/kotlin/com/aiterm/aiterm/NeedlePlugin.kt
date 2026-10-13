package com.aiterm.aiterm

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Needle's engine is process-global and not thread-safe: every call goes through one thread. */
class NeedlePlugin : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var loadedPath: String? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> run(result) {
                val path = call.argument<String>("modelPath")!!
                if (loadedPath != path) {
                    NeedleNative.load(path)
                    loadedPath = path
                }
                NeedleNative.init(
                    call.argument<String>("system")!!,
                    call.argument<String>("tools")!!,
                    call.argument<String>("toolIndexPath")!!,
                )
                null
            }
            "complete" -> run(result) {
                NeedleNative.complete(
                    call.argument<String>("input")!!,
                    call.argument<Int>("maxTokens") ?: 256,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun run(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("needle", e.message, null) }
            }
        }
    }
}
