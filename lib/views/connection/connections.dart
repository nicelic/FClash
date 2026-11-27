import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectionsView extends ConsumerStatefulWidget {
  final Future<List<TrackerInfo>> Function()? connectionsReader;
  final int Function()? speedNowMs;

  const ConnectionsView({
    super.key,
    @visibleForTesting this.connectionsReader,
    @visibleForTesting this.speedNowMs,
  });

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView>
    with WidgetsBindingObserver, ActivePollingMixin<ConnectionsView> {
  static const _relativeTimeRefreshPolls = 30;

  CoreController get _core => ref.read(coreHandlerProvider);

  final _scaffoldKey = GlobalKey<CommonScaffoldState>();
  final _listController = TrackerInfoListController();
  late final ConnectionSpeedTracker _speedTracker;
  final _visibleItemsNotifier = ValueNotifier<List<TrackerInfo>>(const []);
  final _isEmptyNotifier = ValueNotifier<bool>(true);
  final _relativeTimeTick = ValueNotifier<int>(0);
  final ScrollController _scrollController = ScrollController();
  List<TrackerInfo> _trackedConnections = const [];
  late ConnectionSortMode _sortMode;
  int _pollCount = 0;

  @override
  Duration get pollInterval => const Duration(seconds: 1);

  @override
  bool get pollWhenInactive => true;

  @override
  void initState() {
    _speedTracker = ConnectionSpeedTracker(nowMs: widget.speedNowMs);
    _sortMode = ref.read(
      appSettingProvider.select((state) => state.connectionSortMode),
    );
    super.initState();
    _listController.addListener(_syncVisibleConnections);
    ref.listenManual(
      appSettingProvider.select((state) => state.connectionSortMode),
      (prev, next) {
        if (prev != next && mounted) {
          setState(() {
            _sortMode = next;
          });
          _applySortOnly();
        }
      },
    );
  }

  void _syncVisibleConnections() {
    final visible = _listController.value.list;
    _visibleItemsNotifier.value = visible;
    _isEmptyNotifier.value = visible.isEmpty;
  }

  @override
  void onPollingStopped() {
    _speedTracker.reset();
    _pollCount = 0;
  }

  void _selectSortCategory(ConnectionSortCategory category) {
    ref.read(appSettingProvider.notifier).update(
      (state) => state.copyWith(
        connectionSortMode: state.connectionSortMode.selectCategory(category),
      ),
    );
  }

  CommonPopupMenuItem _buildSortMenuItem(
    BuildContext context, {
    required ConnectionSortCategory category,
    required IconData icon,
    required String label,
  }) {
    final selected = _sortMode.category == category;
    final colorScheme = context.colorScheme;
    return CommonPopupMenuItem(
      icon: icon,
      label: label,
      selected: selected,
      trailing: selected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Icon(
                  _sortMode.descending
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 16,
                  color: colorScheme.primary,
                ),
                Icon(
                  Icons.check,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ],
            )
          : null,
      onPressed: () => _selectSortCategory(category),
    );
  }

  Widget _buildSortMenu(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonPopupMenu(
      items: [
        _buildSortMenuItem(
          context,
          category: ConnectionSortCategory.speed,
          icon: Icons.speed,
          label: appLocalizations.sortBySpeed,
        ),
        _buildSortMenuItem(
          context,
          category: ConnectionSortCategory.traffic,
          icon: Icons.swap_vert,
          label: appLocalizations.sortByTraffic,
        ),
        _buildSortMenuItem(
          context,
          category: ConnectionSortCategory.time,
          icon: Icons.schedule,
          label: appLocalizations.sortByTime,
        ),
        _buildSortMenuItem(
          context,
          category: ConnectionSortCategory.defaultTime,
          icon: Icons.history,
          label: appLocalizations.sortByDefaultTime,
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupBox(
        targetBuilder: (open) {
          return IconButton(
            tooltip: appLocalizations.sort,
            onPressed: () {
              open(offset: Offset.zero);
            },
            icon: const Icon(Icons.sort),
          );
        },
        popupBuilder: _buildSortMenu,
      ),
      IconButton(
        tooltip: appLocalizations.search,
        onPressed: () {
          _scaffoldKey.currentState?.handleToSearch();
        },
        icon: const Icon(Icons.search),
      ),
      IconButton(
        tooltip: appLocalizations.closeConnections,
        onPressed: () async {
          unawaited(_core.closeConnections());
          await _refreshConnections();
        },
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  @override
  Future<void> poll(PollGuard isCurrent) async {
    final trackerInfos = await _readConnections();
    if (trackerInfos == null || !isCurrent()) {
      return;
    }
    _applyConnections(trackerInfos);
    _pollCount++;
    if (_pollCount % _relativeTimeRefreshPolls == 0) {
      _relativeTimeTick.value++;
    }
  }

  Future<void> _refreshConnections() async {
    final trackerInfos = await _readConnections();
    if (trackerInfos == null || !mounted) {
      return;
    }
    _applyConnections(trackerInfos);
  }

  Future<List<TrackerInfo>?> _readConnections() async {
    try {
      final connectionsReader = widget.connectionsReader;
      return connectionsReader != null
          ? await connectionsReader()
          : await _core.getConnections();
    } catch (error) {
      commonPrint.log(
        'updateConnections error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  void _applyConnections(List<TrackerInfo> trackerInfos) {
    final tracked = _speedTracker.apply(trackerInfos);
    _trackedConnections = tracked;
    _listController.setTrackerInfos(sortConnections(tracked, _sortMode));
  }

  void _applySortOnly() {
    if (_trackedConnections.isEmpty) {
      return;
    }
    _listController.setTrackerInfos(
      sortConnections(_trackedConnections, _sortMode),
    );
  }

  Future<void> _handleBlockConnection(String id) async {
    await _core.closeConnection(id);
    await _refreshConnections();
  }

  @override
  void dispose() {
    _listController.removeListener(_syncVisibleConnections);
    _speedTracker.reset();
    _trackedConnections = const [];
    _visibleItemsNotifier.dispose();
    _isEmptyNotifier.dispose();
    _relativeTimeTick.dispose();
    _listController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final showProcess = ref.watch(
      patchClashConfigProvider.select(
        (state) => state.findProcessMode == FindProcessMode.always,
      ),
    );
    return CommonScaffold(
      key: _scaffoldKey,
      title: appLocalizations.connections,
      onKeywordsUpdate: _listController.updateKeywords,
      searchState: AppBarSearchState(
        onSearch: _listController.search,
        autoAddSearch: false,
      ),
      actions: _buildActions(context),
      body: ValueListenableBuilder<bool>(
        valueListenable: _isEmptyNotifier,
        builder: (context, isEmpty, _) {
          return NullStatusSwitcher(
            isEmpty: isEmpty,
            nullStatus: NullStatus(
              label: appLocalizations.nullTip(appLocalizations.connections),
              illustration: NullStatusIllustration.connections,
            ),
            child: TrackerInfoAnimatedList(
              controller: _scrollController,
              trackerInfos: _visibleItemsNotifier.value,
              itemsListenable: _visibleItemsNotifier,
              detailStateListenable: _listController,
              relativeTimeListenable: _relativeTimeTick,
              showProcess: showProcess,
              animateMoves: _sortMode.category != ConnectionSortCategory.speed,
              detailTitle: appLocalizations.details(
                appLocalizations.connection,
              ),
              trailingBuilder: (trackerInfo) => IconButton(
                tooltip: appLocalizations.blockConnection,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.block, size: 20),
                onPressed: () {
                  _handleBlockConnection(trackerInfo.id);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
