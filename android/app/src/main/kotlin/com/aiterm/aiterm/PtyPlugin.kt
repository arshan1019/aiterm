package com.aiterm.aiterm

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges lib/platform/pty.dart to [SessionRegistry]. "aiterm/pty" is the
 * control channel, "aiterm/pty/output" the single shared output stream.
 * Sessions belong to the registry, so this plugin (and its engine) can come
 * and go without ending them.
 */
class PtyPlugin : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> try {
                val id = SessionRegistry.start(
                    argv = call.argument<List<String>>("argv") ?: emptyList(),
                    env = call.argument<Map<String, String>>("env") ?: emptyMap(),
                    cwd = call.argument<String>("cwd") ?: "/",
                    rows = call.argument<Int>("rows") ?: 24,
                    cols = call.argument<Int>("cols") ?: 80,
                )
                result.success(mapOf("id" to id))
            } catch (e: Exception) {
                result.error("start_failed", e.message, null)
            }
            "write" -> {
                SessionRegistry.write(call.argument<Int>("id") ?: 0, call.argument<String>("data") ?: "")
                result.success(null)
            }
            "resize" -> {
                SessionRegistry.resize(
                    call.argument<Int>("id") ?: 0,
                    call.argument<Int>("rows") ?: 24,
                    call.argument<Int>("cols") ?: 80,
                )
                result.success(null)
            }
            "stop" -> {
                SessionRegistry.stop(call.argument<Int>("id") ?: 0)
                result.success(null)
            }
            "list" -> result.success(SessionRegistry.live())
            "attach" -> result.success(SessionRegistry.attach(call.argument<Int>("id") ?: 0))
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) = SessionRegistry.setSink(events)

    override fun onCancel(arguments: Any?) = SessionRegistry.setSink(null)
}
