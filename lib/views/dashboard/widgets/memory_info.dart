import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemoryInfo extends ConsumerStatefulWidget {
  final Future<num> Function()? memoryReader;
  final DashboardTileSize? size;

  const MemoryInfo({
    super.key,
    @visibleForTesting this.memoryReader,
    this.size,
  });

  @override
  ConsumerState<MemoryInfo> createState() => _MemoryInfoState();
}

class _MemoryInfoState extends ConsumerState<MemoryInfo>
    with WidgetsBindingObserver, ActivePollingMixin<MemoryInfo> {
  final _memoryStateNotifier = ValueNotifier<num>(0);
  final List<double> _history = [];

  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  Duration get pollInterval => const Duration(seconds: 2);

  @override
  void dispose() {
    _memoryStateNotifier.dispose();
    super.dispose();
  }

  @override
  Future<void> poll(PollGuard isCurrent) async {
    final memory = await _readMemory();
    if (memory == null || !isCurrent()) {
      return;
    }
    _history.add(memory.toDouble());
    if (_history.length > trafficSampleLength) {
      _history.removeAt(0);
    }
    _memoryStateNotifier.value = memory;
  }

  Future<num?> _readMemory() async {
    try {
      final memoryReader = widget.memoryReader;
      return memoryReader != null ? await memoryReader() : await _readTotal();
    } catch (error) {
      commonPrint.log(
        'updateMemory error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<num> _readTotal() async {
    final rss = ProcessInfo.currentRss;
    final coreConnected = ref.read(coreStatusProvider) == CoreStatus.connected;
    if (system.isDesktop && coreConnected) {
      return await _core.getMemory() + rss;
    }
    return rss;
  }

  List<Point> _buildPoints(num current) {
    final samples = _history.isEmpty
        ? <double>[current.toDouble(), current.toDouble()]
        : _history.length == 1
        ? <double>[_history.first, _history.first]
        : _history;
    return [
      for (final (index, value) in samples.indexed)
        Point(index.toDouble(), value),
    ];
  }

  Widget _buildValueText(BuildContext context, num memory) {
    final traffic = memory.traffic;
    final style = context.textTheme.bodyMedium?.toLight.adjustSize(1);
    return SizedBox(
      height: globalState.measure.bodyMediumHeight + 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(traffic.value, style: style),
          const SizedBox(width: 8),
          Text(traffic.unit, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final effectiveSize = widget.size ?? DashboardTileSize.small;
    final lines = effectiveSize == DashboardTileSize.tall ? 2 : 1;

    return SizedBox(
      height: getWidgetHeight(lines),
      child: RepaintBoundary(
        child: CommonCard(
          radius: AppCorner.lg,
          info: effectiveSize == DashboardTileSize.wide
              ? null
              : Info(
                  iconData: Icons.memory,
                  label: appLocalizations.memoryInfo,
                ),
          onPressed: () {
            _core.requestGc();
          },
          child: ValueListenableBuilder(
            valueListenable: _memoryStateNotifier,
            builder: (_, memory, _) {
              final points = _buildPoints(memory);
              return switch (effectiveSize) {
                DashboardTileSize.wide => Padding(
                  padding: EdgeInsets.only(left: 16.mAp, right: 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InfoHeader(
                              padding: EdgeInsets.only(top: 16.mAp),
                              info: Info(
                                iconData: Icons.memory,
                                label: appLocalizations.memoryInfo,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(bottom: 16.mAp),
                              child: _buildValueText(context, memory),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: LineChart(
                            gradient: true,
                            color: context.colorScheme.primary,
                            points: points,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                DashboardTileSize.tall => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: baseInfoEdgeInsets.copyWith(top: 0, bottom: 0),
                      child: _buildValueText(context, memory),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: LineChart(
                          gradient: true,
                          color: context.colorScheme.primary,
                          points: points,
                        ),
                      ),
                    ),
                  ],
                ),
                DashboardTileSize.small || DashboardTileSize.large => Container(
                  padding: baseInfoEdgeInsets.copyWith(top: 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_buildValueText(context, memory)],
                  ),
                ),
              };
            },
          ),
        ),
      ),
    );
  }
}
