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
    private val loaded = mutableSetOf<String>()
    private val recorder = VoiceRecorder()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> run(result) {
                load(call.argument<String>("modelPath")!!)
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
            "loadVoice" -> run(result) {
                load(call.argument<String>("modelPath")!!)
                null
            }
            "startRecording" -> try {
                recorder.start()
                result.success(null)
            } catch (e: Exception) {
                result.error("voice", e.message, null)
            }
            "stopAndTranscribe" -> {
                val pcm = recorder.stop()
                val keywords = call.argument<String>("keywords") ?: ""
                run(result) {
                    // Under ~0.3 s is a mis-tap, not speech.
                    if (pcm.size < VoiceRecorder.RATE * 3 / 10) """{"text":""}"""
                    else NeedleNative.transcribe(pcm, keywords)
                }
            }
            "cancelRecording" -> {
                recorder.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // needle_load keeps one model per kind (text, speech); load each file once.
    private fun load(path: String) {
        if (loaded.add(path)) {
            try {
                NeedleNative.load(path)
            } catch (e: Throwable) {
                loaded.remove(path)
                throw e
            }
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
