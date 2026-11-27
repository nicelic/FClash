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
