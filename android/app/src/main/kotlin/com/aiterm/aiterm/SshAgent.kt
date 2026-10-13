package com.aiterm.aiterm

import android.app.Activity
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.Build
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.lang.ref.WeakReference
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * An ssh-agent backed by Android's keystore. Keys are P-256, generated in
 * hardware where available and never exportable; using one needs the
 * fingerprint or screen lock (valid for a minute), so a stolen phone or a
 * malicious process can't quietly use them.
 *
 * Linux sees it as an ordinary agent: SSH_AUTH_SOCK=/tmp/aiterm-agent.sock,
 * so ssh and git just work.
 */
object SshAgent : AgentKeys {
    private const val PREFIX = "aiterm-ssh-"
    private const val AUTH_SECONDS = 60

    private val keyStore: KeyStore by lazy { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }
    private var server: LocalServerSocket? = null
    private var socketPath: String? = null
    var activity: WeakReference<Activity>? = null

    // ── Keys ───────────────────────────────────────────────────────────

    fun names(): List<String> = keyStore.aliases().toList().filter { it.startsWith(PREFIX) }.map { it.removePrefix(PREFIX) }.sorted()

    private fun publicKey(name: String) = keyStore.getCertificate(PREFIX + name).publicKey as ECPublicKey

    fun publicLine(name: String) = authorizedKey(ecdsaBlob(publicKey(name)), "$name@aiterm")

    fun create(name: String) {
        require(name.matches(Regex("[A-Za-z0-9._-]{1,40}"))) { "Use letters, digits, . _ - (up to 40)" }
        require(name !in names()) { "A key named $name exists" }
        val spec = KeyGenParameterSpec.Builder(PREFIX + name, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .apply {
                if (Build.VERSION.SDK_INT >= 30) {
                    setUserAuthenticationParameters(
                        AUTH_SECONDS,
                        KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    setUserAuthenticationValidityDurationSeconds(AUTH_SECONDS)
                }
            }
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").run {
            initialize(spec)
            generateKeyPair()
        }
    }

    fun delete(name: String) = keyStore.deleteEntry(PREFIX + name)

    override fun identities() = names().map { ecdsaBlob(publicKey(it)) to "$it@aiterm" }

    override fun sign(blob: ByteArray, data: ByteArray): ByteArray? {
        val name = names().firstOrNull { ecdsaBlob(publicKey(it)).contentEquals(blob) } ?: return null
        val key = keyStore.getKey(PREFIX + name, null) as PrivateKey
        fun attempt() = Signature.getInstance("SHA256withECDSA").run { initSign(key); update(data); sign() }
        return try {
            attempt()
        } catch (_: UserNotAuthenticatedException) {
            if (authenticate("Use SSH key “$name”")) runCatching { attempt() }.getOrNull() else null
        }
    }

    /** Shows the fingerprint / screen-lock prompt and waits for it (agent thread). */
    private fun authenticate(title: String): Boolean {
        val act = activity?.get() ?: return false
        if (Build.VERSION.SDK_INT < 28) return false
        val done = CountDownLatch(1)
        var ok = false
        act.runOnUiThread {
            val builder = BiometricPrompt.Builder(act).setTitle(title).setSubtitle("aiterm ssh-agent")
            if (Build.VERSION.SDK_INT >= 30) {
                builder.setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                )
            } else if (Build.VERSION.SDK_INT >= 29) {
                @Suppress("DEPRECATION")
                builder.setDeviceCredentialAllowed(true)
            } else {
                builder.setNegativeButton("Cancel", act.mainExecutor) { _, _ -> done.countDown() }
            }
            builder.build().authenticate(CancellationSignal(), act.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    ok = true
                    done.countDown()
                }

                override fun onAuthenticationError(code: Int, message: CharSequence) = done.countDown()
            })
        }
        done.await(2, TimeUnit.MINUTES)
        return ok
    }

    // ── Socket ─────────────────────────────────────────────────────────

    /** Listens on [path] (a host path inside the rootfs's /tmp). Idempotent. */
    @Synchronized
    fun start(path: String) {
        if (server != null && socketPath == path) return
        stop()
        File(path).apply { parentFile?.mkdirs(); delete() }
        val socket = LocalSocket()
        socket.bind(LocalSocketAddress(path, LocalSocketAddress.Namespace.FILESYSTEM))
        val listening = LocalServerSocket(socket.fileDescriptor)
        server = listening
        socketPath = path
        val protocol = AgentProtocol(this)
        thread(isDaemon = true, name = "ssh-agent") {
            while (true) {
                val client = try {
                    listening.accept()
                } catch (_: Exception) {
                    break
                }
                thread(isDaemon = true) { serve(client, protocol) }
            }
        }
    }

    @Synchronized
    fun stop() {
        runCatching { server?.close() }
        server = null
    }

    private fun serve(client: LocalSocket, protocol: AgentProtocol) = client.use {
        val input = DataInputStream(it.inputStream)
        val output = DataOutputStream(it.outputStream)
        try {
            while (true) {
                val length = input.readInt()
                if (length <= 0 || length > 256 * 1024) return
                val request = ByteArray(length).also(input::readFully)
                val reply = protocol.handle(request)
                output.writeInt(reply.size)
                output.write(reply)
                output.flush()
            }
        } catch (_: Exception) {
            // Client closed the connection.
        }
    }
}

/** "aiterm/ssh": list, create and delete keys, and start the agent. */
class SshPlugin : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "list" -> result.success(SshAgent.names().map { mapOf("name" to it, "publicKey" to SshAgent.publicLine(it)) })
                "create" -> {
                    val name = call.argument<String>("name")!!
                    SshAgent.create(name)
                    result.success(mapOf("name" to name, "publicKey" to SshAgent.publicLine(name)))
                }
                "delete" -> {
                    SshAgent.delete(call.argument<String>("name")!!)
                    result.success(null)
                }
                "startAgent" -> {
                    SshAgent.start(call.argument<String>("path")!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ssh", e.message, null)
        }
    }
}
