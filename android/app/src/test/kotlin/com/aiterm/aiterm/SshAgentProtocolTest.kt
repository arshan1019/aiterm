package com.aiterm.aiterm

import java.math.BigInteger
import java.nio.ByteBuffer
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SshAgentProtocolTest {
    private val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
    private val pub = pair.public as ECPublicKey

    private fun reader(b: ByteArray) = SshReader(b)

    @Test
    fun publicKeyBlobIsTheOpenSshFormat() {
        val blob = ecdsaBlob(pub)
        val r = reader(blob)
        assertEquals("ecdsa-sha2-nistp256", String(r.string()))
        assertEquals("nistp256", String(r.string()))
        val point = r.string()
        assertEquals(65, point.size)
        assertEquals(0x04.toByte(), point[0])
        assertEquals(pub.w.affineX, BigInteger(1, point.copyOfRange(1, 33)))
        assertEquals(pub.w.affineY, BigInteger(1, point.copyOfRange(33, 65)))
    }

    @Test
    fun authorizedKeysLine() {
        val line = authorizedKey(ecdsaBlob(pub), "phone")
        val parts = line.split(" ")
        assertEquals("ecdsa-sha2-nistp256", parts[0])
        assertArrayEquals(ecdsaBlob(pub), Base64.getDecoder().decode(parts[1]))
        assertEquals("phone", parts[2])
    }

    @Test
    fun derSignatureBecomesSshSignatureThatStillVerifies() {
        val data = "challenge".toByteArray()
        val der = Signature.getInstance("SHA256withECDSA").run { initSign(pair.private); update(data); sign() }
        val ssh = sshSignature(der)
        val r = reader(ssh)
        assertEquals("ecdsa-sha2-nistp256", String(r.string()))
        val inner = reader(r.string())
        val rr = BigInteger(inner.string())
        val ss = BigInteger(inner.string())
        // Re-encode r,s as DER and verify with the public key.
        val back = derOf(rr, ss)
        val ok = Signature.getInstance("SHA256withECDSA").run { initVerify(pub); update(data); verify(back) }
        assertTrue(ok)
    }

    @Test
    fun agentListsIdentities() {
        val agent = AgentProtocol(object : AgentKeys {
            override fun identities() = listOf(ecdsaBlob(pub) to "phone")
            override fun sign(blob: ByteArray, data: ByteArray): ByteArray? = null
        })
        val reply = reader(agent.handle(byteArrayOf(11)))
        assertEquals(12, reply.byte())
        assertEquals(1, reply.uint32())
        assertArrayEquals(ecdsaBlob(pub), reply.string())
        assertEquals("phone", String(reply.string()))
    }

    @Test
    fun agentSignsWithTheMatchingKey() {
        val blob = ecdsaBlob(pub)
        val agent = AgentProtocol(object : AgentKeys {
            override fun identities() = listOf(blob to "phone")
            override fun sign(blob: ByteArray, data: ByteArray) =
                Signature.getInstance("SHA256withECDSA").run { initSign(pair.private); update(data); sign() }
        })
        val request = ByteBuffer.allocate(1 + 4 + blob.size + 4 + 4 + 4).apply {
            put(13); putInt(blob.size); put(blob); putInt(4); put("data".toByteArray()); putInt(0)
        }.array()
        val reply = reader(agent.handle(request))
        assertEquals(14, reply.byte())
        val sig = reader(reply.string())
        assertEquals("ecdsa-sha2-nistp256", String(sig.string()))
    }

    @Test
    fun refusedOrUnknownRequestsFail() {
        val agent = AgentProtocol(object : AgentKeys {
            override fun identities() = emptyList<Pair<ByteArray, String>>()
            override fun sign(blob: ByteArray, data: ByteArray): ByteArray? = null
        })
        assertArrayEquals(byteArrayOf(5), agent.handle(byteArrayOf(99)))
        val sign = ByteBuffer.allocate(1 + 4 + 1 + 4 + 1 + 4).apply {
            put(13); putInt(1); put(1); putInt(1); put(2); putInt(0)
        }.array()
        assertArrayEquals(byteArrayOf(5), agent.handle(sign))
        assertArrayEquals(byteArrayOf(5), agent.handle(byteArrayOf(13, 0, 0))) // truncated
    }

    private fun derOf(r: BigInteger, s: BigInteger): ByteArray {
        fun int(v: BigInteger): ByteArray {
            val b = v.toByteArray()
            return byteArrayOf(0x02, b.size.toByte()) + b
        }
        val body = int(r) + int(s)
        return byteArrayOf(0x30, body.size.toByte()) + body
    }
}
