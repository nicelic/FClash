import 'dart:io';

import 'package:flutter/foundation.dart';

typedef NetworkInterfaceLister =
    Future<List<NetworkInterface>> Function({bool includeLoopback});

@visibleForTesting
NetworkInterfaceLister listNetworkInterfaces =
    ({bool includeLoopback = false}) =>
        NetworkInterface.list(includeLoopback: includeLoopback);

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

  bool get includesIPv4 {
    return addresses.any((addr) => addr.isIPv4);
  }
}

extension InternetAddressExt on InternetAddress {
  bool get isIPv4 {
    return type == InternetAddressType.IPv4;
  }
}

Future<String?> getLocalIpAddress() async {
  final List<NetworkInterface> interfaces =
      await listNetworkInterfaces(includeLoopback: false)
        ..sort((a, b) {
          if (a.isWifi && !b.isWifi) return -1;
          if (!a.isWifi && b.isWifi) return 1;
          if (a.includesIPv4 && !b.includesIPv4) return -1;
          if (!a.includesIPv4 && b.includesIPv4) return 1;
          return 0;
        });
  for (final interface in interfaces) {
    final addresses = interface.addresses;
    if (addresses.isEmpty) {
      continue;
    }
    addresses.sort((a, b) {
      if (a.isIPv4 && !b.isIPv4) return -1;
      if (!a.isIPv4 && b.isIPv4) return 1;
      return 0;
    });
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
  return !parsed.isLoopback && !parsed.isLinkLocal && !parsed.isMulticast;
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
            item.addresses.any((addr) => _isRoutableAddress(addr.address)),
      )
      .map((item) => item.name)
      .toSet()
      .toList()
    ..sort();
  return names;
}
