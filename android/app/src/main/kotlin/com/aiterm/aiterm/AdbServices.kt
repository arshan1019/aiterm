package com.aiterm.aiterm

import java.net.InetAddress

/** A Wireless debugging service seen on the network. */
data class Found(val host: InetAddress?, val port: Int)

/**
 * Wireless debugging advertises its pairing and connect ports over mDNS,
 * but so do other phones on the same Wi-Fi: keep the one whose address is
 * ours. A lone service whose host couldn't be resolved is taken as ours.
 */
fun pickOwnPort(found: List<Found>, ownAddresses: Set<InetAddress>): Int? {
    found.firstOrNull { it.host != null && it.host in ownAddresses }?.let { return it.port }
    return found.singleOrNull()?.takeIf { it.host == null }?.port
}
