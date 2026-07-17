import Foundation
import Darwin

struct NetworkInterfaceInfo: Hashable {
    let name: String
    let ipv4: String
    let netmaskBits: Int
}

enum NetworkInterface {
    /// The IPv4 default gateway, if there is one.
    ///
    /// Worth the routing-table walk because on a LAN scan this is the single best router evidence
    /// available: the host that everything leaves through is the router, and no vendor string or
    /// hostname guess comes close to that.
    ///
    /// Reads the kernel routing table via sysctl rather than shelling out to `netstat -rn` — the
    /// same reason `activeInterfaces` walks `getifaddrs` instead of parsing `ifconfig`.
    static func defaultGateway() -> String? {
        // Ask for the IPv4 route table, gateways only.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }

        return buffer.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            var offset = 0
            while offset < size {
                let header = base.advanced(by: offset).assumingMemoryBound(to: rt_msghdr.self)
                let messageLength = Int(header.pointee.rtm_msglen)
                guard messageLength > 0 else { return nil }
                defer { offset += messageLength }

                // The default route is the one whose destination is 0.0.0.0.
                let flags = header.pointee.rtm_flags
                guard flags & RTF_GATEWAY != 0,
                      header.pointee.rtm_addrs & RTA_DST != 0,
                      header.pointee.rtm_addrs & RTA_GATEWAY != 0 else { continue }

                // Addresses follow the header, packed in RTA_* order, each self-describing its
                // length — so the gateway is reached by stepping over the destination.
                var cursor = base.advanced(by: offset + MemoryLayout<rt_msghdr>.stride)
                let destination = cursor.assumingMemoryBound(to: sockaddr.self)
                guard destination.pointee.sa_family == UInt8(AF_INET) else { continue }
                let destinationIn = cursor.assumingMemoryBound(to: sockaddr_in.self)
                guard destinationIn.pointee.sin_addr.s_addr == 0 else { continue }  // 0.0.0.0 only

                let destinationLength = Int(destination.pointee.sa_len)
                // Each address is padded to a 4-byte boundary; a zero length still consumes one.
                cursor = cursor.advanced(by: destinationLength == 0 ? 4 : (destinationLength + 3) & ~3)

                let gateway = cursor.assumingMemoryBound(to: sockaddr.self)
                guard gateway.pointee.sa_family == UInt8(AF_INET) else { continue }
                let gatewayIn = cursor.assumingMemoryBound(to: sockaddr_in.self)
                return IPv4.string(from: UInt32(bigEndian: gatewayIn.pointee.sin_addr.s_addr))
            }
            return nil
        }
    }

    static func activeInterfaces() -> [NetworkInterfaceInfo] {
        var results: [NetworkInterfaceInfo] = []
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return results }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }
            let entry = ptr.pointee
            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addrPtr = entry.ifa_addr,
                  addrPtr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let name = String(cString: entry.ifa_name)

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(addrPtr,
                                 socklen_t(MemoryLayout<sockaddr_in>.size),
                                 &hostBuf, socklen_t(NI_MAXHOST),
                                 nil, 0, NI_NUMERICHOST)
            guard rc == 0 else { continue }
            let ipv4 = String(cString: hostBuf)
            if ipv4.hasPrefix("169.254.") { continue }

            guard let maskPtr = entry.ifa_netmask else { continue }
            let maskBE = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr.s_addr
            }
            let bits = UInt32(bigEndian: maskBE).nonzeroBitCount

            results.append(NetworkInterfaceInfo(name: name, ipv4: ipv4, netmaskBits: bits))
        }
        return results
    }

    static func defaultSubnet() -> String? {
        let preferred =
            scannableInterfaces().first(where: { $0.name == "en0" }) ??
            scannableInterfaces().first(where: { $0.name == "en1" }) ??
            scannableInterfaces().first
        return preferred.flatMap(subnet(from:))
    }

    /// Active interfaces filtered to ones likely to host a useful subnet for scanning.
    /// Excludes Apple Wireless Direct Link, link-local helpers, /31, /32.
    static func scannableInterfaces() -> [NetworkInterfaceInfo] {
        let nameAllow: [String] = ["en", "bridge", "utun"]
        return activeInterfaces().filter { iface in
            guard nameAllow.contains(where: { iface.name.hasPrefix($0) }) else { return false }
            return iface.netmaskBits >= 16 && iface.netmaskBits <= 30
        }
    }

    static func subnet(from info: NetworkInterfaceInfo) -> String? {
        guard let ipInt = IPv4.uint32(from: info.ipv4) else { return nil }
        let network = IPv4.network(ipInt, bits: info.netmaskBits)
        return "\(IPv4.string(from: network))/\(info.netmaskBits)"
    }
}
