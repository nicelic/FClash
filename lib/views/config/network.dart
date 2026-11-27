import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _VpnUpdate<T> = VpnProps Function(VpnProps state, T value);

typedef _NetworkUpdate<T> = NetworkProps Function(NetworkProps state, T value);

typedef _TunUpdate<T> =
    PatchClashConfig Function(PatchClashConfig state, T value);

ConfigWriter<T> _vpnWriter<T>(_VpnUpdate<T> update) {
  return (ref, value) => ref
      .read(vpnSettingProvider.notifier)
      .update((state) => update(state, value));
}

ConfigWriter<T> _networkWriter<T>(_NetworkUpdate<T> update) {
  return (ref, value) => ref
      .read(networkSettingProvider.notifier)
      .update((state) => update(state, value));
}

ConfigWriter<T> _tunWriter<T>(_TunUpdate<T> update) {
  return (ref, value) => ref
      .read(patchClashConfigProvider.notifier)
      .update((state) => update(state, value));
}

ConfigToggleItem _vpnToggle({
  required ConfigLabel title,
  required bool Function(VpnProps state) select,
  required _VpnUpdate<bool> update,
  ConfigLabel? subtitle,
}) {
  return ConfigToggleItem(
    title: title,
    subtitle: subtitle,
    selector: vpnSettingProvider.select(select),
    onChanged: _vpnWriter(update),
  );
}

ConfigToggleItem _networkToggle({
  required ConfigLabel title,
  required bool Function(NetworkProps state) select,
  required _NetworkUpdate<bool> update,
  ConfigLabel? subtitle,
}) {
  return ConfigToggleItem(
    title: title,
    subtitle: subtitle,
    selector: networkSettingProvider.select(select),
    onChanged: _networkWriter(update),
  );
}

class VPNItem extends ConsumerWidget {
  const VPNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => 'VPN',
      subtitle: (l) => l.vpnEnableDesc,
      select: (state) => state.enable,
      update: (state, value) => state.copyWith(enable: value),
    );
  }
}

class TUNItem extends ConsumerWidget {
  const TUNItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigToggleItem(
      title: (l) => l.tun,
      subtitle: (l) => l.tunDesc,
      selector: patchClashConfigProvider.select((state) => state.tun.enable),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(enable: value),
      ),
    );
  }
}

class AllowBypassItem extends ConsumerWidget {
  const AllowBypassItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => l.allowBypass,
      subtitle: (l) => l.allowBypassDesc,
      select: (state) => state.allowBypass,
      update: (state, value) => state.copyWith(allowBypass: value),
    );
  }
}

class VpnSystemProxyItem extends ConsumerWidget {
  const VpnSystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final authenticationEnable = ref.watch(
      networkSettingProvider.select((state) => state.authentication.enable),
    );
    return _vpnToggle(
      title: (l) => l.systemProxy,
      subtitle: (l) => authenticationEnable
          ? l.authenticationSystemProxyDesc
          : l.systemProxyDesc,
      select: (state) => state.systemProxy,
      update: (state, value) => state.copyWith(systemProxy: value),
    );
  }
}

class SystemProxyItem extends ConsumerWidget {
  const SystemProxyItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _networkToggle(
      title: (l) => l.systemProxy,
      subtitle: (l) => l.systemProxyDesc,
      select: (state) => state.systemProxy,
      update: (state, value) => state.copyWith(systemProxy: value),
    );
  }
}

class Ipv6Item extends ConsumerWidget {
  const Ipv6Item({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => 'IPv6',
      subtitle: (l) => l.ipv6InboundDesc,
      select: (state) => state.ipv6,
      update: (state, value) => state.copyWith(ipv6: value),
    );
  }
}

class AutoSetSystemDnsItem extends ConsumerWidget {
  const AutoSetSystemDnsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _networkToggle(
      title: (l) => l.autoSetSystemDns,
      select: (state) => state.autoSetSystemDns,
      update: (state, value) => state.copyWith(autoSetSystemDns: value),
    );
  }
}

class DNSHijackingItem extends ConsumerWidget {
  const DNSHijackingItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _vpnToggle(
      title: (l) => l.dnsHijacking,
      select: (state) => state.dnsHijacking,
      update: (state, value) => state.copyWith(dnsHijacking: value),
    );
  }
}

class TunStackItem extends ConsumerWidget {
  const TunStackItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigOptionsItem<TunStack>(
      title: (l) => l.stackMode,
      options: TunStack.values,
      textBuilder: (stack) => stack.name,
      selector: patchClashConfigProvider.select((state) => state.tun.stack),
      onChanged: _tunWriter((state, value) => state.copyWith.tun(stack: value)),
    );
  }
}

class TunAutoRouteItem extends ConsumerWidget {
  const TunAutoRouteItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigToggleItem(
      title: (l) => l.autoRoute,
      selector: patchClashConfigProvider.select((state) => state.tun.autoRoute),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(autoRoute: value),
      ),
    );
  }
}

class TunStrictRouteItem extends ConsumerWidget {
  const TunStrictRouteItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigToggleItem(
      title: (l) => l.strictRoute,
      selector: patchClashConfigProvider.select(
        (state) => state.tun.strictRoute,
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(strictRoute: value),
      ),
    );
  }
}

class TunDnsHijackItem extends ConsumerWidget {
  const TunDnsHijackItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigToggleItem(
      title: (l) => l.dnsHijacking,
      selector: patchClashConfigProvider.select(
        (state) => state.tun.dnsHijack.isNotEmpty,
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(
          dnsHijack: value ? defaultTunDnsHijack : const [],
        ),
      ),
    );
  }
}

class TunCongestionControllerItem extends ConsumerWidget {
  const TunCongestionControllerItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final stack = ref.watch(
      patchClashConfigProvider.select((state) => state.tun.stack),
    );
    if (stack != TunStack.mips) {
      return const SizedBox.shrink();
    }
    return ConfigOptionsItem<TunCongestionController>(
      title: (l) => l.congestionController,
      options: TunCongestionController.values,
      textBuilder: (controller) => controller.name,
      selector: patchClashConfigProvider.select(
        (state) => state.tun.congestionController,
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(congestionController: value),
      ),
    );
  }
}

class TunMtuItem extends ConsumerWidget {
  const TunMtuItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.mtu,
      keyboardType: TextInputType.number,
      inputFormatters: TextInputLimits.digitsOnly(4),
      resetValue: '$defaultTunMtu',
      normalize: (value) => value.trim(),
      validator: (value, l) {
        final mtu = int.tryParse(value ?? '');
        if (mtu == null || mtu < minTunMtu || mtu > maxTunMtu) {
          return l.mtuTip(minTunMtu, maxTunMtu);
        }
        return null;
      },
      selector: patchClashConfigProvider.select(
        (state) => state.tun.mtu.toString(),
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(
          mtu: int.tryParse(value) ?? defaultTunMtu,
        ),
      ),
    );
  }
}

class TunInterfaceItem extends ConsumerWidget {
  const TunInterfaceItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final state = ref.watch(
      patchClashConfigProvider.select(
        (state) => (mode: state.interfaceNameMode, name: state.interfaceName),
      ),
    );
    final selected = switch (state.mode) {
      InterfaceNameMode.clear => '',
      InterfaceNameMode.follow => null,
      InterfaceNameMode.custom => state.name,
    };
    final subtitle = switch (state.mode) {
      InterfaceNameMode.clear => appLocalizations.auto,
      InterfaceNameMode.follow => appLocalizations.interfaceNameModeFollow,
      InterfaceNameMode.custom =>
        state.name.isEmpty ? appLocalizations.auto : state.name,
    };
    return ListItem(
      title: Text(appLocalizations.networkInterface),
      subtitle: Text(subtitle),
      onTap: () async {
        final isInit = ref.read(initProvider);
        final detected = await getPhysicalInterfaceNames(
          fetchFromCore: isInit
              ? ref.read(coreHandlerProvider).getInterfaces
              : null,
        );
        final current = selected ?? '';
        final options = <String>[
          '',
          ...detected,
          if (current.isNotEmpty && !detected.contains(current)) current,
        ];
        final value = await dialogs.showCommonDialog<String>(
          child: OptionsDialog<String>(
            title: appLocalizations.networkInterface,
            options: options,
            value: current,
            textBuilder: (item) => item.isEmpty ? appLocalizations.auto : item,
          ),
        );
        if (value == null || !context.mounted) {
          return;
        }
        ref.read(patchClashConfigProvider.notifier).update((state) {
          if (value.isEmpty) {
            return state.copyWith(
              interfaceNameMode: InterfaceNameMode.clear,
              interfaceName: '',
              tun: state.tun.copyWith(autoDetectInterface: true),
            );
          }
          return state.copyWith(
            interfaceNameMode: InterfaceNameMode.custom,
            interfaceName: value,
          );
        });
      },
    );
  }
}

class InterfaceNameModeItem extends ConsumerWidget {
  const InterfaceNameModeItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    return ConfigOptionsItem<InterfaceNameMode>(
      title: (l) => l.interfaceNameMode,
      options: InterfaceNameMode.values,
      textBuilder: (mode) => switch (mode) {
        InterfaceNameMode.clear => appLocalizations.interfaceNameModeClear,
        InterfaceNameMode.follow => appLocalizations.interfaceNameModeFollow,
        InterfaceNameMode.custom => appLocalizations.interfaceNameModeCustom,
      },
      selector: patchClashConfigProvider.select(
        (state) => state.interfaceNameMode,
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith(interfaceNameMode: value),
      ),
    );
  }
}

class InterfaceNameItem extends ConsumerWidget {
  const InterfaceNameItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final isCustom = ref.watch(
      patchClashConfigProvider.select(
        (state) => state.interfaceNameMode == InterfaceNameMode.custom,
      ),
    );
    if (!isCustom) {
      return Container();
    }
    return ConfigTextItem(
      title: (l) => l.interfaceName,
      subtitle: (l) => l.interfaceNameDesc,
      maxLength: TextInputLimits.name,
      selector: patchClashConfigProvider.select((state) => state.interfaceName),
      onChanged: _tunWriter(
        (state, value) => state.copyWith(interfaceName: value.trim()),
      ),
    );
  }
}

class RouteModeItem extends ConsumerWidget {
  const RouteModeItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigOptionsItem<RouteMode>(
      title: (l) => l.routeMode,
      options: RouteMode.values,
      textBuilder: (mode) => mode.label,
      selector: networkSettingProvider.select((state) => state.routeMode),
      onChanged: _networkWriter(
        (state, value) => state.copyWith(routeMode: value),
      ),
    );
  }
}

class BypassDomainItem extends ConsumerWidget {
  const BypassDomainItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigListInputItem(
      title: (l) => l.bypassDomain,
      subtitle: (l) => l.bypassDomainDesc,
      itemMaxLength: TextInputLimits.domain,
      selector: networkSettingProvider.select((state) => state.bypassDomain),
      onChanged: _networkWriter(
        (state, value) => state.copyWith(bypassDomain: value),
      ),
    );
  }
}

class RouteAddressItem extends ConsumerWidget {
  const RouteAddressItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final bypassPrivate = ref.watch(
      networkSettingProvider.select(
        (state) => state.routeMode == RouteMode.bypassPrivate,
      ),
    );
    if (bypassPrivate) {
      return Container();
    }
    return ConfigListInputItem(
      title: (l) => l.routeAddress,
      subtitle: (l) => l.routeAddressDesc,
      itemMaxLength: TextInputLimits.cidr,
      maxWidth: 360,
      selector: patchClashConfigProvider.select(
        (state) => state.tun.routeAddress,
      ),
      onChanged: _tunWriter(
        (state, value) => state.copyWith.tun(routeAddress: value),
      ),
    );
  }
}

List<Widget> networkOptionsItems({
  required bool isDesktop,
  required bool isMacOS,
}) {
  return [
    if (isDesktop) const TUNItem(),
    if (isMacOS) const AutoSetSystemDnsItem(),
    const TunStackItem(),
    const TunCongestionControllerItem(),
    const TunMtuItem(),
    // mihomo's DefaultSocketHook ignores interface-name on Android
    // (core/lib.go installHooks, vendored dialer.go), so these rows only
    // apply on desktop.
    if (isDesktop) ...[
      const TunAutoRouteItem(),
      const TunStrictRouteItem(),
      const TunDnsHijackItem(),
      const TunInterfaceItem(),
      const InterfaceNameModeItem(),
      const InterfaceNameItem(),
    ],
    if (!isDesktop) ...[const RouteModeItem(), const RouteAddressItem()],
  ];
}

class NetworkListView extends StatelessWidget {
  const NetworkListView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return generateListView([
      if (system.isAndroid) const VPNItem(),
      if (system.isAndroid)
        ...generateSection(
          title: 'VPN',
          items: [
            const VpnSystemProxyItem(),
            const BypassDomainItem(),
            const AllowBypassItem(),
            const Ipv6Item(),
            const DNSHijackingItem(),
          ],
        ),
      if (system.isDesktop)
        ...generateSection(
          title: appLocalizations.system,
          items: [const SystemProxyItem(), const BypassDomainItem()],
        ),
      ...generateSection(
        title: appLocalizations.options,
        items: networkOptionsItems(
          isDesktop: system.isDesktop,
          isMacOS: system.isMacOS,
        ),
      ),
    ]);
  }
}
