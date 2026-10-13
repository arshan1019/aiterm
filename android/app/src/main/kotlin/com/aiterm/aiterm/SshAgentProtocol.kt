package com.aiterm.aiterm

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.interfaces.ECPublicKey
import java.util.Base64

/**
 * The ssh-agent protocol (draft-miller-ssh-agent) for ECDSA P-256 keys,
 * the curve Android's keystore supports in hardware. Pure, so it's unit
 * tested on the JVM; [SshAgent] adds the socket and the keystore.
 */
private const val KEY_TYPE = "ecdsa-sha2-nistp256"

private const val SSH_AGENT_FAILURE: Byte = 5
private const val SSH_AGENTC_REQUEST_IDENTITIES: Byte = 11
private const val SSH_AGENT_IDENTITIES_ANSWER: Byte = 12
private const val SSH_AGENTC_SIGN_REQUEST: Byte = 13
private const val SSH_AGENT_SIGN_RESPONSE: Byte = 14

class SshReader(private val b: ByteArray) {
    private var pos = 0
    fun byte(): Int = b[pos++].toInt() and 0xFF
    fun uint32(): Int {
        if (pos + 4 > b.size) throw IllegalArgumentException("truncated")
        return ByteBuffer.wrap(b, pos, 4).int.also { pos += 4 }
    }
    fun string(): ByteArray {
        val n = uint32()
        if (n < 0 || pos + n > b.size) throw IllegalArgumentException("truncated")
        return b.copyOfRange(pos, pos + n).also { pos += n }
    }
}

private class SshWriter {
    private val out = ByteArrayOutputStream()
    fun byte(v: Byte) = apply { out.write(v.toInt()) }
    fun uint32(v: Int) = apply { out.write(ByteBuffer.allocate(4).putInt(v).array()) }
    fun string(v: ByteArray) = apply { uint32(v.size); out.write(v) }
    fun string(v: String) = string(v.toByteArray())
    fun mpint(v: BigInteger) = string(v.toByteArray()) // two's complement, as SSH expects
    fun bytes() = out.toByteArray()
}

private fun fixed32(v: BigInteger): ByteArray {
    val b = v.toByteArray()
    return when {
        b.size == 32 -> b
        b.size > 32 -> b.copyOfRange(b.size - 32, b.size) // leading sign byte
        else -> ByteArray(32 - b.size) + b
    }
}

/** The OpenSSH public key blob for a P-256 key. */
fun ecdsaBlob(key: ECPublicKey): ByteArray {
    val point = byteArrayOf(0x04) + fixed32(key.w.affineX) + fixed32(key.w.affineY)
    return SshWriter().string(KEY_TYPE).string("nistp256").string(point).bytes()
}

/** A line for authorized_keys / GitHub: "ecdsa-sha2-nistp256 AAAA… comment". */
fun authorizedKey(blob: ByteArray, comment: String) =
    "$KEY_TYPE ${Base64.getEncoder().encodeToString(blob)} $comment"

/** Keystore signatures are DER `SEQUENCE { INTEGER r, INTEGER s }`; SSH wants mpints. */
fun sshSignature(der: ByteArray): ByteArray {
    var pos = 0
    fun length(): Int {
        val first = der[pos++].toInt() and 0xFF
        if (first < 0x80) return first
        var n = 0
        repeat(first and 0x7F) { n = (n shl 8) or (der[pos++].toInt() and 0xFF) }
        return n
    }
    fun integer(): BigInteger {
        require(der[pos++] == 0x02.toByte()) { "expected INTEGER" }
        val n = length()
        return BigInteger(der.copyOfRange(pos, pos + n)).also { pos += n }
    }
    require(der[pos++] == 0x30.toByte()) { "expected SEQUENCE" }
    length()
    val r = integer()
    val s = integer()
    val rs = SshWriter().mpint(r).mpint(s).bytes()
    return SshWriter().string(KEY_TYPE).string(rs).bytes()
}

interface AgentKeys {
    /** (public key blob, comment) for every key. */
    fun identities(): List<Pair<ByteArray, String>>

    /** DER signature of [data] (SHA-256) with the key for [blob], or null if refused. */
    fun sign(blob: ByteArray, data: ByteArray): ByteArray?
}

class AgentProtocol(private val keys: AgentKeys) {
    /** One request body (without its length prefix) in, one reply body out. */
    fun handle(request: ByteArray): ByteArray = try {
        val r = SshReader(request)
        when (r.byte().toByte()) {
            SSH_AGENTC_REQUEST_IDENTITIES -> {
                val ids = keys.identities()
                SshWriter().byte(SSH_AGENT_IDENTITIES_ANSWER).uint32(ids.size).apply {
                    ids.forEach { (blob, comment) -> string(blob).string(comment) }
                }.bytes()
            }
            SSH_AGENTC_SIGN_REQUEST -> {
                val blob = r.string()
                val data = r.string()
                r.uint32() // flags: only relevant to RSA
                val known = keys.identities().any { it.first.contentEquals(blob) }
                val der = if (known) keys.sign(blob, data) else null
                if (der == null) byteArrayOf(SSH_AGENT_FAILURE)
                else SshWriter().byte(SSH_AGENT_SIGN_RESPONSE).string(sshSignature(der)).bytes()
            }
            else -> byteArrayOf(SSH_AGENT_FAILURE)
        }
    } catch (_: Exception) {
        byteArrayOf(SSH_AGENT_FAILURE)
    }
}
