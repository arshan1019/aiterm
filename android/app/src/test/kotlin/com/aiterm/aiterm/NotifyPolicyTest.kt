package com.aiterm.aiterm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NotifyPolicyTest {
    private var now = 1_000_000L
    private fun policy() = NotifyPolicy(clock = { now })
    private val hidden = Visibility(visible = false)
    private val shown = Visibility(visible = true)

    @Test
    fun longCommandFinishingInTheBackgroundNotifies() {
        val p = policy()
        p.onEnter()
        now += 42_000
        p.onSignal(Signal.Osc("133", listOf("D", "0")), hidden, "x", "build")
        val n = p.onSignal(Signal.Osc("133", listOf("A")), hidden, "BUILD SUCCESSFUL", "build")!!
        assertEquals("Finished in 42s · build", n.title)
        assertEquals("BUILD SUCCESSFUL", n.body)
    }

    @Test
    fun failedCommandSaysSo() {
        val p = policy()
        p.onEnter()
        now += 15_000
        p.onSignal(Signal.Osc("133", listOf("D", "2")), hidden, "", "t")
        assertEquals("Failed (exit 2) after 15s · t", p.onSignal(Signal.Osc("133", listOf("A")), hidden, "err", "t")!!.title)
    }

    @Test
    fun shortCommandsAndVisibleTabsStayQuiet() {
        val p = policy()
        p.onEnter()
        now += 3_000
        assertNull(p.onSignal(Signal.Osc("133", listOf("A")), hidden, "", "t"))
        p.onEnter()
        now += 60_000
        assertNull(p.onSignal(Signal.Osc("133", listOf("A")), shown, "", "t"))
    }

    @Test
    fun programNotificationsShowTheirText() {
        val p = policy()
        val n = p.onSignal(Signal.Osc("9", listOf("Claude needs your permission", " continue?")), hidden, "", "claude")!!
        assertEquals("claude", n.title)
        assertEquals("Claude needs your permission; continue?", n.body)
        val m = p.onSignal(Signal.Osc("777", listOf("notify", "Tests", "3 failed")), hidden, "", "claude")!!
        assertEquals("Tests", m.title)
        assertEquals("3 failed", m.body)
        assertNull(p.onSignal(Signal.Osc("9", listOf("4", "1", "50")), hidden, "", "t")) // progress
    }

    @Test
    fun bellsAreThrottledAndUseTheLastLine() {
        val p = policy()
        val n = p.onSignal(Signal.Bell, hidden, "Do you want to proceed? 1. Yes", "claude")!!
        assertEquals("claude needs attention", n.title)
        assertEquals("Do you want to proceed? 1. Yes", n.body)
        now += 5_000
        assertNull(p.onSignal(Signal.Bell, hidden, "x", "claude"))
        now += 30_000
        assertEquals("claude needs attention", p.onSignal(Signal.Bell, hidden, "x", "claude")!!.title)
    }

    @Test
    fun visibleBellIsIgnored() {
        assertNull(policy().onSignal(Signal.Bell, shown, "x", "t"))
    }
}
