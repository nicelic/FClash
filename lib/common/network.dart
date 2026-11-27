import 'dart:io';

import 'package:flutter/foundation.dart';

typedef NetworkInterfaceLister =
    Future<List<NetworkInterface>> Function({bool includeLoopback});

@visibleForTesting
NetworkInterfaceLister listNetworkInterfaces =
    ({bool includeLoopback = false}) =>
        NetworkInterface.list(includeLoopback: includeLoopback);

final _tunInterfacePattern = RegExp(
  r'^(?:fclash|flclash|wintun|clash|mihomo|utun|tun|tap|wg|tailscale|zerotier|zt)(?:[0-9_-].*)?$',
  caseSensitive: false,
);

final _ownTunAdapterPattern = RegExp(
  r'^(?:fclash|flclash|wintun|clash|mihomo)(?:[0-9_-].*)?$',
  caseSensitive: false,
);

extension NetworkInterfaceExt on NetworkInterface {
  bool get isWifi {
    final nameLowCase = name.toLowerCase();
    if (nameLowCase.contains('wlan') ||
        nameLowCase.contains('wi-fi') ||
        nameLowCase == 'en0' ||
        nameLowCase == 'eth0') {
      return true;
    }

    return false;
  }

  bool get isVirtualTun => _tunInterfacePattern.hasMatch(name.trim());

  bool get includesIPv4 {
    return addresses.any((addr) => addr.isIPv4);
  }
}

extension InternetAddressExt on InternetAddress {
  bool get isIPv4 {
    return type == InternetAddressType.IPv4;
  }
}

bool _isVirtualTunIPv4(String address) {
  final raw = address.split('%').first;
  final parsed = InternetAddress.tryParse(raw);
  if (parsed == null || parsed.type != InternetAddressType.IPv4) {
    return false;
  }
  final bytes = parsed.rawAddress;
  return bytes.length == 4 &&
      bytes[0] == 198 &&
      (bytes[1] == 18 || bytes[1] == 19);
}

bool _isLinkLocalAddress(String address) {
  final raw = address.split('%').first;
  return InternetAddress.tryParse(raw)?.isLinkLocal ?? false;
}

bool _isOwnTunAdapter(NetworkInterface iface) {
  return _ownTunAdapterPattern.hasMatch(iface.name.trim());
}

int _compareLocalAddress(InterfaceAddress a, InterfaceAddress b) {
  if (a.isIPv4 != b.isIPv4) {
    return a.isIPv4 ? -1 : 1;
  }
  final aLinkLocal = _isLinkLocalAddress(a.address);
  final bLinkLocal = _isLinkLocalAddress(b.address);
  if (aLinkLocal != bLinkLocal) {
    return aLinkLocal ? 1 : -1;
  }
  return 0;
}

Future<String?> getLocalIpAddress() async {
  final List<NetworkInterface> interfaces =
      await listNetworkInterfaces(includeLoopback: false)
        ..sort((a, b) {
          if (a.isVirtualTun != b.isVirtualTun) {
            return a.isVirtualTun ? 1 : -1;
          }
          if (a.isWifi && !b.isWifi) return -1;
          if (!a.isWifi && b.isWifi) return 1;
          if (a.includesIPv4 && !b.includesIPv4) return -1;
          if (!a.includesIPv4 && b.includesIPv4) return 1;
          return 0;
        });
  for (final interface in interfaces) {
    if (_isOwnTunAdapter(interface)) {
      continue;
    }
    final addresses = interface.addresses
        .where((addr) => !_isVirtualTunIPv4(addr.address))
        .toList();
    if (addresses.isEmpty) {
      continue;
    }
    addresses.sort(_compareLocalAddress);
    return addresses.first.address;
  }
  return '';
}

bool _isRoutableAddress(String address) {
  final raw = address.split('%').first;
  final parsed = InternetAddress.tryParse(raw);
  if (parsed == null) {
    return false;
  }
  return !parsed.isLoopback &&
      !parsed.isLinkLocal &&
      !parsed.isMulticast &&
      !_isVirtualTunIPv4(raw);
}

Future<List<String>> getPhysicalInterfaceNames({
  Future<List<String>> Function()? fetchFromCore,
}) async {
  if (fetchFromCore != null) {
    try {
      final coreInterfaces = await fetchFromCore();
      if (coreInterfaces.isNotEmpty) {
        return coreInterfaces;
      }
    } catch (_) {}
  }
  final interfaces = await listNetworkInterfaces(includeLoopback: false);
  final names = interfaces
      .where(
        (item) =>
            item.name.isNotEmpty &&
            !item.isVirtualTun &&
            item.addresses.any((addr) => _isRoutableAddress(addr.address)),
      )
      .map((item) => item.name)
      .toSet()
      .toList()
    ..sort();
  return names;
}

bool isTunIp(String ip, [InternetAddress? parsedAddress]) {
  final raw = ip.trim().split('%').first;
  final address = parsedAddress ?? InternetAddress.tryParse(raw);
  if (address == null) {
    return false;
  }
  if (address.type == InternetAddressType.IPv4) {
    final bytes = address.rawAddress;
    return bytes.length == 4 &&
        bytes[0] == 198 &&
        (bytes[1] == 18 || bytes[1] == 19);
  }
  return raw.toLowerCase().startsWith('fdfe:dcba:9876');
}

bool isPrivateOrReservedIp(String ip, [InternetAddress? parsedAddress]) {
  final clean = ip.trim().split('%').first;
  final address = parsedAddress ?? InternetAddress.tryParse(clean);
  if (address == null) {
    return false;
  }
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  if (address.type == InternetAddressType.IPv4) {
    final raw = address.rawAddress;
    final p0 = raw[0];
    final p1 = raw[1];
    final p2 = raw[2];
    if (p0 == 0 || p0 == 10 || p0 == 127) return true;
    if (p0 == 100 && p1 >= 64 && p1 <= 127) return true;
    if (p0 == 169 && p1 == 254) return true;
    if (p0 == 172 && p1 >= 16 && p1 <= 31) return true;
    if (p0 == 192 && p1 == 0 && (p2 == 0 || p2 == 2)) return true;
    if (p0 == 192 && p1 == 88 && p2 == 99) return true;
    if (p0 == 192 && p1 == 168) return true;
    if (p0 == 198 && (p1 == 18 || p1 == 19)) return true;
    if (p0 == 198 && p1 == 51 && p2 == 100) return true;
    if (p0 == 203 && p1 == 0 && p2 == 113) return true;
    if (p0 >= 224) return true;
    return false;
  }
  final lower = clean.toLowerCase();
  if (lower == '::1' || lower == '::') return true;
  if (lower.startsWith('fe8') ||
      lower.startsWith('fe9') ||
      lower.startsWith('fea') ||
      lower.startsWith('feb')) {
    return true;
  }
  if (lower.startsWith('fc') || lower.startsWith('fd')) return true;
  if (lower.startsWith('ff') || lower.startsWith('2001:db8:')) return true;
  return false;
}

IpCategory classifyIp(String ip) {
  final clean = ip.trim().split('%').first;
  final address = InternetAddress.tryParse(clean);
  if (address == null) {
    return IpCategory.public;
  }
  if (isTunIp(clean, address)) {
    return IpCategory.tun;
  }
  if (isPrivateOrReservedIp(clean, address)) {
    return IpCategory.lan;
  }
  return IpCategory.public;
}

String countryCodeToEmoji(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (code.length != 2) {
    return countryCode;
  }
  final first = code.codeUnitAt(0);
  final second = code.codeUnitAt(1);
  if (first < 0x41 || first > 0x5A || second < 0x41 || second > 0x5A) {
    return countryCode;
  }
  return String.fromCharCode(first - 0x41 + 0x1F1E6) +
      String.fromCharCode(second - 0x41 + 0x1F1E6);
}
