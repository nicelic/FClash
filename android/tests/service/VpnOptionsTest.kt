package com.follow.clash.service.models

import com.follow.clash.common.AccessControlMode
import java.net.Inet4Address
import java.net.Inet6Address
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

private fun optionsWithRoutes(routeAddress: List<String>) = VpnOptions(
    enable = true,
    port = 7890,
    ipv6 = true,
    dnsHijacking = false,
    accessControlProps = AccessControlProps(
        enable = false,
        mode = AccessControlMode.ACCEPT_SELECTED,
        acceptList = emptyList(),
        rejectList = emptyList(),
    ),
    allowBypass = false,
    systemProxy = true,
    bypassDomain = emptyList(),
    stack = "gvisor",
    routeAddress = routeAddress,
)

class ToCIDRTest {
    @Test
    fun `parses an IPv4 network`() {
        val cidr = "192.168.1.0/24".toCIDR()

        assertTrue(cidr.address is Inet4Address)
        assertEquals("192.168.1.0", cidr.address.hostAddress)
        assertEquals(24, cidr.prefixLength)
    }

    @Test
    fun `parses an IPv6 network`() {
        val cidr = "fd00::/8".toCIDR()

        assertTrue(cidr.address is Inet6Address)
        assertEquals(8, cidr.prefixLength)
    }

    @Test
    fun `accepts the boundary prefix lengths`() {
        assertEquals(0, "0.0.0.0/0".toCIDR().prefixLength)
        assertEquals(32, "10.0.0.1/32".toCIDR().prefixLength)
        assertEquals(0, "::/0".toCIDR().prefixLength)
        assertEquals(128, "fd00::1/128".toCIDR().prefixLength)
    }

    @Test
    fun `rejects an address without a prefix`() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0".toCIDR()
        }
        assertTrue(error.message!!.contains("Invalid CIDR format"))
    }

    @Test
    fun `rejects an address with too many segments`() {
        assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/24/8".toCIDR()
        }
    }

    @Test
    fun `rejects a non-numeric prefix`() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/abc".toCIDR()
        }
        assertTrue(error.message!!.contains("Invalid prefix length"))
    }

    @Test
    fun `rejects an IPv4 prefix above 32`() {
        assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/33".toCIDR()
        }
    }

    @Test
    fun `rejects an IPv6 prefix above 128`() {
        assertThrows(IllegalArgumentException::class.java) {
            "fd00::/129".toCIDR()
        }
    }

    @Test
    fun `rejects a negative prefix`() {
        assertThrows(IllegalArgumentException::class.java) {
            "192.168.1.0/-1".toCIDR()
        }
    }
}

class RouteAddressTest {
    @Test
    fun `splits a mixed route list by address family`() {
        val options = optionsWithRoutes(
            listOf("192.168.1.0/24", "fd00::/8", "10.0.0.0/8", "2000::/3"),
        )

        val ipv4 = options.getIpv4RouteAddress()
        val ipv6 = options.getIpv6RouteAddress()

        assertEquals(2, ipv4.size)
        assertEquals(2, ipv6.size)
        assertTrue(ipv4.all { it.address is Inet4Address })
        assertTrue(ipv6.all { it.address is Inet6Address })
    }

    @Test
    fun `returns empty lists for an empty route list`() {
        val options = optionsWithRoutes(emptyList())

        assertTrue(options.getIpv4RouteAddress().isEmpty())
        assertTrue(options.getIpv6RouteAddress().isEmpty())
    }

    @Test
    fun `preserves the configured order within a family`() {
        val options = optionsWithRoutes(
            listOf("10.0.0.0/8", "fd00::/8", "192.168.0.0/16"),
        )

        assertEquals(
            listOf(8, 16),
            options.getIpv4RouteAddress().map { it.prefixLength },
        )
    }

    @Test
    fun `propagates a malformed entry instead of silently dropping it`() {
        val options = optionsWithRoutes(listOf("192.168.1.0/24", "not-a-cidr"))

        assertThrows(IllegalArgumentException::class.java) {
            options.getIpv4RouteAddress()
        }
    }
}

class TunOptionsResolutionTest {
    @Test
    fun `resolvedMtu keeps valid values and resets out-of-range values`() {
        val base = optionsWithRoutes(emptyList())

        assertEquals(9000, base.copy(mtu = 0).resolvedMtu())
        assertEquals(9000, base.copy(mtu = 1279).resolvedMtu())
        assertEquals(1280, base.copy(mtu = 1280).resolvedMtu())
        assertEquals(1500, base.copy(mtu = 1500).resolvedMtu())
        assertEquals(9000, base.copy(mtu = 9000).resolvedMtu())
        assertEquals(9000, base.copy(mtu = 9001).resolvedMtu())
    }

    @Test
    fun `resolvedCongestionController handles null fallback safely`() {
        val base = optionsWithRoutes(emptyList())

        assertEquals("cubic", base.resolvedCongestionController())
        assertEquals("", base.copy(congestionController = null).resolvedCongestionController())
        assertEquals("bbr3", base.copy(congestionController = "bbr3").resolvedCongestionController())
    }
}
