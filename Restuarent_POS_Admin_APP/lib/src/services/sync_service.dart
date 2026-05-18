import 'dart:async';
import 'dart:math';

import '../core/constants/cloud_defaults.dart';
import '../models/menu_item.dart';
import '../models/order_item.dart';
import '../models/order_model.dart';
import '../models/order_source.dart';
import '../models/order_status.dart';
import '../models/server_config.dart';
import '../models/sync_event.dart';
import '../models/sync_status.dart';
import 'cloud_api_service.dart';
import 'cloud_realtime_service.dart';
import 'connectivity_service.dart';
import 'local_database_service.dart';

class SyncLogEntry {
  SyncLogEntry({
    required this.message,
    required this.createdAt,
    this.isError = false,
  });

  final String message;
  final DateTime createdAt;
  final bool isError;
}

class SyncRuntimeState {
  SyncRuntimeState({
    required this.isSyncing,
    required this.cloudConnected,
    required this.pendingCount,
    required this.failedCount,
    required this.logs,
    this.lastSyncAt,
    this.lastError,
  });

  final bool isSyncing;
  final bool cloudConnected;
  final int pendingCount;
  final int failedCount;
  final DateTime? lastSyncAt;
  final String? lastError;
  final List<SyncLogEntry> logs;

  SyncRuntimeState copyWith({
    bool? isSyncing,
    bool? cloudConnected,
    int? pendingCount,
    int? failedCount,
    DateTime? lastSyncAt,
    String? lastError,
    List<SyncLogEntry>? logs,
    bool clearError = false,
  }) {
    return SyncRuntimeState(
      isSyncing: isSyncing ?? this.isSyncing,
      cloudConnected: cloudConnected ?? this.cloudConnected,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearError ? null : lastError ?? this.lastError,
      logs: logs ?? this.logs,
    );
  }
}

class SyncService {
  SyncService({
    required LocalDatabaseService database,
    required CloudApiService cloudApi,
    required CloudRealtimeService cloudRealtime,
    required ConnectivityService connectivity,
    void Function(Map<String, Object?> event)? onRemoteEvent,
  }) : _database = database,
       _cloudApi = cloudApi,
       _cloudRealtime = cloudRealtime,
       _connectivity = connectivity,
       _onRemoteEvent = onRemoteEvent;

  final LocalDatabaseService _database;
  final CloudApiService _cloudApi;
  final CloudRealtimeService _cloudRealtime;
  final ConnectivityService _connectivity;
  final void Function(Map<String, Object?> event)? _onRemoteEvent;
  final StreamController<SyncRuntimeState> _stateController =
      StreamController<SyncRuntimeState>.broadcast();

  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _autoSyncTimer;
  CloudConfig _cloudConfig = CloudConfig(
    baseUrl: CloudDefaults.baseUrl,
    enabled: CloudDefaults.shouldEnableSyncByDefault,
    deviceToken: '',
    autoSyncIntervalSeconds: 30,
  );
  bool _online = false;
  DateTime? _lastCloudPullAt;
  ServerConfig _serverConfig = ServerConfig(
    serverId: '',
    restaurantId: '',
    outletId: '',
    restaurantName: '',
    outletName: '',
  );
  SyncRuntimeState _state = SyncRuntimeState(
    isSyncing: false,
    cloudConnected: false,
    pendingCount: 0,
    failedCount: 0,
    logs: [],
  );

  SyncRuntimeState get state => _state;
  Stream<SyncRuntimeState> get stateStream => _stateController.stream;

  Future<void> initialize({
    required CloudConfig cloudConfig,
    required ServerConfig serverConfig,
  }) async {
    configure(cloudConfig: cloudConfig, serverConfig: serverConfig);
    await refreshSummary();
    _online = await _connectivity.hasInternetAccess();
    _connectivitySubscription ??= _connectivity.onlineStream.listen((online) {
      _online = online;
      if (online) {
        _addLog('Internet restored. Sync queue will run.');
        unawaited(syncNow());
      } else {
        _state = _state.copyWith(
          cloudConnected: false,
          lastError: 'Internet unavailable.',
        );
        _emitState();
      }
    });
  }

  void configure({
    required CloudConfig cloudConfig,
    required ServerConfig serverConfig,
  }) {
    _cloudConfig = cloudConfig;
    _serverConfig = serverConfig;
    _cloudApi.configure(cloudConfig: cloudConfig, serverConfig: serverConfig);
    _autoSyncTimer?.cancel();
    if (cloudConfig.canSync) {
      final seconds = max(10, cloudConfig.autoSyncIntervalSeconds);
      _autoSyncTimer = Timer.periodic(
        Duration(seconds: seconds),
        (_) => unawaited(syncNow()),
      );
    } else {
      unawaited(_cloudRealtime.disconnect());
    }
  }

  Future<bool> testCloud() async {
    if (!_cloudConfig.canConnect) {
      _state = _state.copyWith(
        cloudConnected: false,
        lastError: 'Cloud API URL is empty or invalid.',
      );
      _addLog('Cloud health skipped: URL is empty or invalid.', isError: true);
      _emitState();
      return false;
    }
    try {
      await _cloudApi.testHealth();
      await _connectCloudRealtime();
      _state = _state.copyWith(cloudConnected: true, clearError: true);
      _addLog('Cloud health check passed.');
      _emitState();
      return true;
    } catch (error) {
      _state = _state.copyWith(
        cloudConnected: false,
        lastError: error.toString(),
      );
      _addLog('Cloud health failed: $error', isError: true);
      _emitState();
      return false;
    }
  }

  Future<void> syncNow() async {
    await refreshSummary();
    if (_state.isSyncing) return;
    if (!_cloudConfig.canSync) {
      _state = _state.copyWith(
        cloudConnected: false,
        lastError: _cloudConfig.hasDeviceToken
            ? 'Cloud sync disabled or URL invalid.'
            : 'Restaurant cloud setup is not complete yet.',
      );
      _emitState();
      return;
    }
    if (!_online && !await _connectivity.hasInternetAccess()) {
      _state = _state.copyWith(
        cloudConnected: false,
        lastError: 'Internet unavailable. Sync queue is pending.',
      );
      _emitState();
      return;
    }

    _state = _state.copyWith(isSyncing: true, clearError: true);
    _emitState();
    try {
      await _cloudApi.testHealth();
      await _cloudApi.registerDevice();
      await _connectCloudRealtime();
      _state = _state.copyWith(cloudConnected: true, clearError: true);
      final events = await _database.getSyncEvents(
        statuses: {SyncStatus.pending, SyncStatus.failed},
        limit: 120,
      );
      var synced = 0;
      for (final event in events) {
        if (event.status == SyncStatus.failed && !_backoffReady(event)) {
          continue;
        }
        try {
          await _pushEvent(event);
          await _database.markSyncEventSynced(event);
          synced++;
        } catch (error) {
          await _database.markSyncEventFailed(event, error);
          _addLog(
            'Sync failed for ${event.entityType}:${event.entityId}: $error',
            isError: true,
          );
        }
      }
      if (synced > 0) {
        _addLog('Synced $synced pending event${synced == 1 ? '' : 's'}.');
      }
      final pulled = await _pullCloudChanges();
      if (pulled > 0) {
        _addLog('Imported $pulled cloud update${pulled == 1 ? '' : 's'}.');
      }
      await _triggerBackendSync();
      await refreshSummary();
      _state = _state.copyWith(
        isSyncing: false,
        cloudConnected: true,
        lastSyncAt: DateTime.now(),
        clearError: true,
      );
    } catch (error) {
      _state = _state.copyWith(
        isSyncing: false,
        cloudConnected: false,
        lastError: error.toString(),
      );
      _addLog('Sync stopped: $error', isError: true);
    } finally {
      await refreshSummary();
      _emitState();
    }
  }

  Future<void> retryFailed() async {
    await _database.retryFailedSyncEvents();
    _addLog('Failed events moved back to pending.');
    await syncNow();
  }

  Future<void> refreshSummary() async {
    final summary = await _database.getSyncSummary();
    _state = _state.copyWith(
      pendingCount: summary.pendingCount,
      failedCount: summary.failedCount,
      lastSyncAt: summary.lastSyncAt ?? _state.lastSyncAt,
    );
    _emitState();
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _autoSyncTimer?.cancel();
    await _cloudRealtime.disconnect();
    await _stateController.close();
  }

  Future<void> _pushEvent(SyncEvent event) async {
    final payload = event.payload;
    switch (event.entityType) {
      case 'menu_item':
        if (event.action == 'delete') {
          await _cloudApi.deleteMenuItem(event.entityId);
        } else if (event.action == 'update') {
          await _cloudApi.updateMenuItem(MenuItem.fromMap(payload));
        } else {
          await _cloudApi.pushMenuItem(MenuItem.fromMap(payload));
        }
        return;
      case 'order':
        await _cloudApi.pushOrder(_orderFromPayload(payload));
        return;
      case 'order_status':
        final status = OrderStatus.tryParse(payload['status']?.toString());
        if (status == null) {
          throw CloudApiException('Order status payload is invalid.');
        }
        await _cloudApi.pushOrderStatus(event.entityId, status);
        return;
      case 'server_config':
        await _cloudApi.registerDevice();
        return;
      default:
        throw CloudApiException('Unknown sync entity ${event.entityType}.');
    }
  }

  Future<int> _pullCloudChanges() async {
    final since = _lastCloudPullAt;
    final menuPayloads = await _cloudApi.pullMenu(since: since);
    final orderPayloads = await _cloudApi.pullOrders(since: since);
    var imported = 0;

    for (final payload in menuPayloads) {
      try {
        final item = _menuFromPayload(payload);
        final applied = await _database.applyRemoteMenuItem(item);
        if (applied != null) {
          imported++;
          _onRemoteEvent?.call({
            'type': 'menu_updated',
            'data': applied.toJson(),
          });
        }
      } catch (error) {
        _addLog('Cloud menu import skipped: $error', isError: true);
      }
    }

    for (final payload in orderPayloads) {
      try {
        final order = _orderFromPayload(
          payload,
          sourceFallback: OrderSource.cloud,
        );
        final applied = await _database.applyRemoteOrder(order);
        if (applied != null) {
          imported++;
          _onRemoteEvent?.call({
            'type': applied.status == OrderStatus.pending
                ? 'order_created'
                : 'order_status_updated',
            'data': applied.toJson(),
          });
        }
      } catch (error) {
        _addLog('Cloud order import skipped: $error', isError: true);
      }
    }

    _lastCloudPullAt = DateTime.now().subtract(Duration(seconds: 2));
    return imported;
  }

  Future<void> _triggerBackendSync() async {
    try {
      final response = await _cloudApi.syncBackendNow();
      final data = response['data'] is Map
          ? Map<String, Object?>.from(response['data'] as Map)
          : response;
      final pushed = data['pushed'];
      final failed = data['failed'];
      if (pushed is int && pushed > 0) {
        _addLog(
          'Backend pushed $pushed local record${pushed == 1 ? '' : 's'} to Supabase.',
        );
      }
      if (failed is int && failed > 0) {
        _addLog(
          'Backend Supabase sync has $failed failed record${failed == 1 ? '' : 's'}.',
          isError: true,
        );
      }
    } catch (error) {
      _addLog('Backend Supabase sync trigger skipped: $error', isError: true);
    }
  }

  Future<void> _connectCloudRealtime() async {
    var realtimeConfig = await _cloudApi.loadRealtimeConfig();
    // If backend returned enabled:false (Python backend), build a native-WS config
    realtimeConfig ??= CloudRealtimeConfig(
      enabled: false,
      supabaseUrl: '',
      publishableKey: '',
      channelPrefix: 'pos:outlet:',
    );
    // Attach REST base URL + device token so the native WS can connect
    realtimeConfig = realtimeConfig.withRestInfo(
      restBaseUrl: _cloudApi.effectiveBaseUrl,
      deviceToken: _cloudConfig.deviceToken,
    );
    if (!realtimeConfig.canConnect) return;
    await _cloudRealtime.connect(
      config: realtimeConfig,
      serverConfig: _serverConfig,
      onEvent: (event) => unawaited(_handleCloudRealtimeEvent(event)),
      onLog: (message) => _addLog(message),
    );
  }

  Future<void> _handleCloudRealtimeEvent(Map<String, Object?> event) async {
    final type = event['type']?.toString() ?? '';
    final data = event['data'];
    if (data is! Map) return;

    try {
      if (type == 'menu_updated') {
        final item = _menuFromPayload(Map<String, Object?>.from(data));
        final applied = await _database.applyRemoteMenuItem(item);
        if (applied != null) {
          _onRemoteEvent?.call({
            'type': 'menu_updated',
            'data': applied.toJson(),
          });
          _addLog('Cloud realtime menu update imported.');
        }
        return;
      }

      if (type == 'order_created' || type == 'order_status_updated') {
        final order = _orderFromPayload(
          Map<String, Object?>.from(data),
          sourceFallback: OrderSource.cloud,
        );
        final applied = await _database.applyRemoteOrder(order);
        if (applied != null) {
          _onRemoteEvent?.call({'type': type, 'data': applied.toJson()});
          _addLog('Cloud realtime order update imported.');
        }
      }
    } catch (error) {
      _addLog('Cloud realtime event skipped: $error', isError: true);
    } finally {
      await refreshSummary();
    }
  }

  MenuItem _menuFromPayload(Map<String, Object?> payload) {
    final now = DateTime.now().toIso8601String();
    final normalized = Map<String, Object?>.from(payload);
    normalized['description'] ??= '';
    normalized['category'] ??= 'General';
    normalized['isAvailable'] ??= true;
    normalized['syncStatus'] = SyncStatus.synced.value;
    normalized['version'] ??= 1;
    normalized['createdAt'] ??= normalized['updatedAt'] ?? now;
    normalized['updatedAt'] ??= normalized['createdAt'] ?? now;
    return MenuItem.fromMap(normalized);
  }

  OrderModel _orderFromPayload(
    Map<String, Object?> payload, {
    OrderSource sourceFallback = OrderSource.cloud,
  }) {
    final orderId = payload['id']?.toString() ?? '';
    final rawItems = payload['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) {
                final m = Map<String, Object?>.from(item);
                // Backend items omit id/orderId — synthesise them to satisfy fromMap
                m['id'] ??= '${orderId}_${m['menuItemId'] ?? m.hashCode}';
                m['orderId'] ??= orderId;
                return OrderItem.fromMap(m);
              })
              .toList(growable: false)
        : <OrderItem>[];
    final now = DateTime.now().toIso8601String();
    final normalized = Map<String, Object?>.from(payload);
    // Field name normalisations: backend uses different names than the Flutter model
    normalized['total'] ??=
        normalized['totalAmount']; // backend sends totalAmount
    normalized['total'] ??= items.fold<double>(
      0,
      (t, item) => t + item.lineTotal,
    );
    normalized['note'] ??= normalized['notes']; // backend sends notes
    // Map serialNumber → sequenceNo and build a human-readable orderNo
    final serial = normalized['serialNumber'];
    normalized['sequenceNo'] ??= serial;
    if (normalized['orderNo'] == null) {
      normalized['orderNo'] = serial != null
          ? '#$serial'
          : 'WEB-${orderId.length > 8 ? orderId.substring(0, 8) : orderId}';
    }
    normalized['source'] = OrderSource.parse(
      normalized['source']?.toString(),
      fallback: sourceFallback,
    ).value;
    normalized['status'] ??= OrderStatus.pending.value;
    normalized['syncStatus'] = SyncStatus.synced.value;
    normalized['version'] ??= 1;
    normalized['createdAt'] ??= normalized['updatedAt'] ?? now;
    normalized['updatedAt'] ??= normalized['createdAt'] ?? now;
    return OrderModel.fromMap(normalized, items: items);
  }

  bool _backoffReady(SyncEvent event) {
    final retry = event.retryCount.clamp(0, 8);
    final delaySeconds = min(300, pow(2, retry).toInt() * 5);
    return DateTime.now().difference(event.updatedAt).inSeconds >= delaySeconds;
  }

  void _addLog(String message, {bool isError = false}) {
    final logs = [
      SyncLogEntry(
        message: message,
        createdAt: DateTime.now(),
        isError: isError,
      ),
      ..._state.logs,
    ];
    if (logs.length > 80) {
      logs.removeRange(80, logs.length);
    }
    _state = _state.copyWith(logs: List.unmodifiable(logs));
    _emitState();
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }
}
