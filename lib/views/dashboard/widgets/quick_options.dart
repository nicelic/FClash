import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/views/config/network.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _QuickSwitchItemsBuilder = List<Widget> Function(WidgetRef ref);

class _QuickSwitchCard extends StatelessWidget {
  const _QuickSwitchCard({
    required this.label,
    required this.iconData,
    this.items = const [],
    this.itemsBuilder,
    required this.selector,
    required this.onChanged,
  });

  final String label;
  final IconData iconData;
  final List<Widget> items;
  final _QuickSwitchItemsBuilder? itemsBuilder;
  final ProviderListenable<bool> selector;
  final void Function(WidgetRef ref, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        radius: AppCorner.lg,
        onPressed: () {
          showSheet(
            context: context,
            builder: (_) {
              return AdaptiveSheetScaffold(
                body: itemsBuilder == null
                    ? generateListView(generateSection(items: items))
                    : Consumer(
                        builder: (_, ref, _) {
                          return generateListView(
                            generateSection(items: itemsBuilder!(ref)),
                          );
                        },
                      ),
                title: label,
              );
            },
          );
        },
        info: Info(label: label, iconData: iconData),
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(top: 4, bottom: 8, right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 1,
                child: TooltipText(
                  text: Text(
                    context.appLocalizations.options,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.adjustSize(-2).toLight,
                  ),
                ),
              ),
              Consumer(
                builder: (_, ref, _) {
                  return Switch(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: ref.watch(selector),
                    onChanged: (value) => onChanged(ref, value),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TUNButton extends StatelessWidget {
  const TUNButton({super.key});

  @override
  Widget build(BuildContext context) {
    return _QuickSwitchCard(
      label: context.appLocalizations.tun,
      iconData: Icons.stacked_line_chart,
      itemsBuilder: (ref) {
        final isMips = ref.watch(
          patchClashConfigProvider.select(
            (state) => state.tun.stack == TunStack.mips,
          ),
        );
        return [
          if (system.isDesktop) const TUNItem(),
          if (system.isMacOS) const AutoSetSystemDnsItem(),
          const TunStackItem(),
          if (isMips) const TunCongestionControllerItem(),
          const TunMtuItem(),
          if (system.isDesktop) ...[
            const TunAutoRouteItem(),
            const TunStrictRouteItem(),
            const TunDnsHijackItem(),
            const TunInterfaceItem(),
          ],
        ];
      },
      selector: patchClashConfigProvider.select((state) => state.tun.enable),
      onChanged: (ref, value) {
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: value));
      },
    );
  }
}

class SystemProxyButton extends StatelessWidget {
  const SystemProxyButton({super.key});

  @override
  Widget build(BuildContext context) {
    return _QuickSwitchCard(
      label: context.appLocalizations.systemProxy,
      iconData: Icons.shuffle,
      items: const [SystemProxyItem(), BypassDomainItem()],
      selector: networkSettingProvider.select((state) => state.systemProxy),
      onChanged: (ref, value) {
        ref
            .read(networkSettingProvider.notifier)
            .update((state) => state.copyWith(systemProxy: value));
      },
    );
  }
}

class VpnButton extends StatelessWidget {
  const VpnButton({super.key});

  @override
  Widget build(BuildContext context) {
    return _QuickSwitchCard(
      label: 'VPN',
      iconData: Icons.stacked_line_chart,
      itemsBuilder: (ref) {
        final isMips = ref.watch(
          patchClashConfigProvider.select(
            (state) => state.tun.stack == TunStack.mips,
          ),
        );
        return [
          const VPNItem(),
          const VpnSystemProxyItem(),
          const DNSHijackingItem(),
          const TunStackItem(),
          if (isMips) const TunCongestionControllerItem(),
          const TunMtuItem(),
        ];
      },
      selector: vpnSettingProvider.select((state) => state.enable),
      onChanged: (ref, value) {
        ref
            .read(vpnSettingProvider.notifier)
            .update((state) => state.copyWith(enable: value));
      },
    );
  }
}
