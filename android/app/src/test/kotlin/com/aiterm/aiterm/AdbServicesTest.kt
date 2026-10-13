package com.aiterm.aiterm

import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AdbServicesTest {
    private fun ip(s: String) = InetAddress.getByName(s)

    @Test
    fun picksThisPhonesServiceAmongOthersOnTheNetwork() {
        val found = listOf(Found(ip("192.168.1.20"), 40001), Found(ip("192.168.1.7"), 37123))
        assertEquals(37123, pickOwnPort(found, setOf(ip("192.168.1.7"), ip("127.0.0.1"))))
    }

    @Test
    fun nothingOfOursMeansNoPort() {
        assertNull(pickOwnPort(listOf(Found(ip("10.0.0.9"), 1)), setOf(ip("10.0.0.2"))))
    }

    @Test
    fun aSingleServiceWithUnknownHostIsAssumedOurs() {
        assertEquals(5555, pickOwnPort(listOf(Found(null, 5555)), setOf(ip("10.0.0.2"))))
    }
}
