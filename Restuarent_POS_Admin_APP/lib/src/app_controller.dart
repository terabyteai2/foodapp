import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../firebase_options.dart';
import 'core/constants/cloud_defaults.dart';
import 'core/constants/payment_defaults.dart';
import 'core/localization/app_strings.dart';
import 'models/bkash_payment_session.dart';
import 'models/dashboard_metrics.dart';
import 'models/inventory_item.dart';
import 'models/menu_item.dart';
import 'models/order_item.dart';
import 'models/order_model.dart';
import 'models/order_source.dart';
import 'models/order_status.dart';
import 'models/sales_report.dart';
import 'models/server_config.dart';
import 'models/stock_adjustment.dart';
import 'models/sync_event.dart';
import 'services/cloud_api_service.dart';
import 'services/cloud_realtime_service.dart';
import 'services/connectivity_service.dart';
import 'services/local_database_service.dart';
import 'services/printer_service.dart';
import 'services/sync_service.dart';

enum AppThemePreference {
  black('black'),
  white('white'),
  device('device');

  const AppThemePreference(this.code);
  final String code;

  static AppThemePreference parse(String? _) {
    return AppThemePreference.white;
  }
}

class PosAppController extends ChangeNotifier {
  PosAppController({
    LocalDatabaseService? database,
    PrinterService? printerService,
    CloudApiService? cloudApiService,
    CloudRealtimeService? cloudRealtimeService,
    ConnectivityService? connectivityService,
    SyncService? syncService,
  }) : database = database ?? LocalDatabaseService(),
       printerService = printerService ?? PrinterService(),
       cloudApiService = cloudApiService ?? CloudApiService(),
       cloudRealtimeService = cloudRealtimeService ?? CloudRealtimeService(),
       connectivityService = connectivityService ?? ConnectivityService() {
    this.syncService =
        syncService ??
        SyncService(
          database: this.database,
          cloudApi: this.cloudApiService,
          cloudRealtime: this.cloudRealtimeService,
          connectivity: this.connectivityService,
        );
  }

  final LocalDatabaseService database;
  final PrinterService printerService;
  final CloudApiService cloudApiService;
  final CloudRealtimeService cloudRealtimeService;
  final ConnectivityService connectivityService;
  late final SyncService syncService;

  final Uuid _uuid = Uuid();
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Set<String> _knownOrderIds = <String>{};
  final Set<String> _autoPrintInFlight = <String>{};
  Future<void>? _googleSignInInit;

  bool initialized = false;
  bool busy = false;
  bool hasSeenIntro = false;
  bool bkashPaymentVerified = false;
  String? lastBkashPaymentId;
  String? lastBkashTransactionId;
  AppLanguage language = AppLanguage.bn;
  AppThemePreference themePreference = AppThemePreference.white;
  double uiScale = 0.9;
  String? lastError;
  bool isLoggedIn = false;
  String accountEmail = '';
  String accountUsername = '';
  String googleUid = '';
  String _accountPassword = '';
  List<MenuItem> menuItems = [];
  List<OrderModel> orders = [];
  List<SyncEvent> syncEvents = [];
  List<InventoryItem> inventoryItems = [];
  List<BluetoothPrinterDevice> pairedPrinters = [];
  PrinterRuntimeState printerState = PrinterRuntimeState(
    autoPrintEnabled: true,
    connected: false,
    busy: false,
  );
  SyncRuntimeState syncState = SyncRuntimeState(
    isSyncing: false,
    cloudConnected: false,
    pendingCount: 0,
    failedCount: 0,
    logs: [],
  );

  ServerConfig serverConfig = ServerConfig(
    serverId: '',
    restaurantId: '',
    outletId: '',
    restaurantName: '',
    outletName: '',
  );
  CloudConfig cloudConfig = CloudConfig(
    baseUrl: CloudDefaults.baseUrl,
    enabled: CloudDefaults.shouldEnableSyncByDefault,
    deviceToken: '',
    autoSyncIntervalSeconds: 30,
  );

  String get restaurantName => serverConfig.restaurantName;
  String get outletName => serverConfig.outletName;
  AppStrings get strings => AppStrings.of(language);
  bool get requiresBkashPayment {
    return PaymentDefaults.requireBkashGate && !bkashPaymentVerified;
  }

  String get uiScaleLabel {
    final text = strings;
    if (uiScale <= 0.88) return text.compact;
    if (uiScale >= 0.98) return text.large;
    return text.comfortable;
  }

  // App is ready to use as soon as the restaurant has a name.
  // Cloud sync is optional and configured separately.
  bool get isTenantReady {
    return serverConfig.restaurantName.trim().isNotEmpty &&
        serverConfig.outletName.trim().isNotEmpty;
  }

  bool get isCloudReady =>
      cloudConfig.hasDeviceToken && cloudConfig.hasValidBaseUrl;

  Future<void> onResumed() async {
    if (!isCloudReady || !cloudConfig.canSync) return;
    final hasInternet = await connectivityService.hasInternetAccess();
    if (hasInternet) {
      unawaited(syncService.syncNow());
    }
  }

  Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      hasSeenIntro = preferences.getBool(_seenIntroKey) ?? false;
      bkashPaymentVerified =
          preferences.getBool(_bkashPaymentVerifiedKey) ??
          !PaymentDefaults.requireBkashGate;
      lastBkashPaymentId = preferences.getString(_bkashPaymentIdKey);
      lastBkashTransactionId = preferences.getString(_bkashTransactionIdKey);
      final deviceLanguage = AppLanguage.fromLocale(
        ui.PlatformDispatcher.instance.locale,
      );
      final hasManualLanguage =
          preferences.getBool(_languagePreferenceSetKey) ?? false;
      language = hasManualLanguage
          ? AppLanguage.parse(
              preferences.getString(_languageKey),
              fallback: deviceLanguage,
            )
          : deviceLanguage;
      themePreference = AppThemePreference.white;
      uiScale = (preferences.getDouble(_uiScaleKey) ?? 0.9)
          .clamp(minUiScale, maxUiScale)
          .toDouble();
      serverConfig = ServerConfig(
        serverId: await _getOrCreatePreference(
          preferences,
          _serverIdKey,
          _uuid.v4(),
        ),
        restaurantId: preferences.getString(_restaurantIdKey) ?? '',
        outletId: preferences.getString(_outletIdKey) ?? '',
        restaurantName: preferences.getString(_restaurantNameKey) ?? '',
        outletName: preferences.getString(_outletNameKey) ?? '',
        tableCount: preferences.getInt(_tableCountKey) ?? 10,
      );
      cloudConfig = CloudConfig(
        baseUrl: CloudDefaults.resolveBaseUrl(
          preferences.getString(_cloudApiUrlKey),
        ),
        enabled:
            preferences.getBool(_cloudSyncEnabledKey) ??
            CloudDefaults.shouldEnableSyncByDefault,
        deviceToken: preferences.getString(_deviceTokenKey) ?? '',
        autoSyncIntervalSeconds: preferences.getInt(_autoSyncIntervalKey) ?? 30,
      );
      final firebaseUser = FirebaseAuth.instance.currentUser;
      googleUid =
          firebaseUser?.uid ?? preferences.getString(_googleUidKey) ?? '';
      accountEmail =
          firebaseUser?.email ?? preferences.getString(_accountEmailKey) ?? '';
      accountUsername =
          firebaseUser?.displayName ??
          preferences.getString(_accountUsernameKey) ??
          '';
      _accountPassword = preferences.getString(_accountPasswordKey) ?? '';
      isLoggedIn =
          preferences.getBool(_accountLoggedInKey) ?? firebaseUser != null;

      await printerService.initialize();
      printerState = printerService.state;
      _subscriptions.add(
        database.changes.listen((_) {
          unawaited(_handleDatabaseChanged());
          unawaited(syncService.refreshSummary());
        }),
      );
      _subscriptions.add(
        printerService.stateStream.listen((state) {
          printerState = state;
          notifyListeners();
        }),
      );
      _subscriptions.add(
        syncService.stateStream.listen((state) {
          syncState = state;
          notifyListeners();
        }),
      );

      await database.initialize();
      await syncService.initialize(
        cloudConfig: cloudConfig,
        serverConfig: serverConfig,
      );
      await reloadData();
      _knownOrderIds
        ..clear()
        ..addAll(orders.map((order) => order.id));
      if (isCloudReady && cloudConfig.canSync) {
        unawaited(syncService.syncNow());
      }
      initialized = true;
      lastError = null;
    } catch (error) {
      lastError = 'App initialization failed: $error';
    } finally {
      notifyListeners();
    }
  }

  DashboardMetrics get metrics {
    final now = DateTime.now();
    final todaysOrders = orders
        .where((order) {
          return order.createdAt.year == now.year &&
              order.createdAt.month == now.month &&
              order.createdAt.day == now.day;
        })
        .toList(growable: false);
    final todayStart = DateTime(now.year, now.month, now.day);
    final sevenDayStart = todayStart.subtract(Duration(days: 6));
    final thirtyDayStart = todayStart.subtract(Duration(days: 29));

    return DashboardMetrics(
      todayOrders: todaysOrders.length,
      pendingOrders: orders.where((order) => order.status.isOpen).length,
      completedOrders: orders
          .where((order) => order.status == OrderStatus.served)
          .length,
      totalSales: todaysOrders
          .where((order) => order.status != OrderStatus.cancelled)
          .fold<double>(0, (total, order) => total + order.total),
      sevenDaySales: _salesSince(sevenDayStart),
      thirtyDaySales: _salesSince(thirtyDayStart),
      menuItemsCount: menuItems.length,
      availableItemsCount: menuItems.where((item) => item.isAvailable).length,
      pendingSyncCount: syncState.pendingCount,
    );
  }

  SalesReport salesReportForDays(int days) {
    return SalesReport.fromOrders(orders: orders, days: days);
  }

  List<String> get categories {
    final values = menuItems.map((item) => item.category).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  double _salesSince(DateTime startAt) {
    return orders
        .where(
          (order) =>
              !order.createdAt.isBefore(startAt) &&
              order.status != OrderStatus.cancelled,
        )
        .fold<double>(0, (total, order) => total + order.total);
  }

  Future<void> completeIntro() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_seenIntroKey, true);
    hasSeenIntro = true;
    notifyListeners();
  }

  Future<void> saveLocalSetup({
    required String restaurantName,
    required String outletName,
  }) async {
    if (googleUid.trim().isNotEmpty && accountEmail.trim().isNotEmpty) {
      await _provisionGoogleTenantInternal(
        restaurantName: restaurantName,
        outletName: outletName,
      );
      isLoggedIn = true;
      hasSeenIntro = true;
      await _persistAccountAuth();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_seenIntroKey, true);
      notifyListeners();
      return;
    }
    serverConfig = serverConfig.copyWith(
      restaurantName: restaurantName.trim(),
      outletName: outletName.trim().isEmpty ? 'Main Outlet' : outletName.trim(),
    );
    isLoggedIn = true;
    hasSeenIntro = true;
    await _persistSettings();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_seenIntroKey, true);
    await preferences.setBool(_accountLoggedInKey, true);
    notifyListeners();
  }

  Future<BkashPaymentSession> createBkashSandboxPayment({
    required double amount,
  }) {
    cloudApiService.configure(
      cloudConfig: cloudConfig,
      serverConfig: serverConfig,
    );
    return cloudApiService.createBkashSandboxPayment(
      serverId: serverConfig.serverId,
      amount: amount,
    );
  }

  Future<bool> verifyBkashSandboxPayment(String paymentId) async {
    var verified = false;
    final ok = await _runBusy(() async {
      final session = await cloudApiService.verifyBkashPayment(paymentId);
      verified = session.paid;
      if (!verified) {
        throw CloudApiException(
          session.lastError ?? 'bKash payment is not completed yet.',
        );
      }
      await _persistBkashPayment(session);
    });
    return ok && verified;
  }

  Future<void> markTemporaryBkashPaymentVerified({
    required String plan,
    required double amount,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final paymentId =
        'temporary_${plan}_${DateTime.now().millisecondsSinceEpoch}';
    bkashPaymentVerified = true;
    lastBkashPaymentId = paymentId;
    lastBkashTransactionId = 'temporary_bkash_sandbox';
    hasSeenIntro = true;
    await preferences.setBool(_bkashPaymentVerifiedKey, true);
    await preferences.setString(_bkashPaymentIdKey, paymentId);
    await preferences.setString(
      _bkashTransactionIdKey,
      'temporary_bkash_sandbox_${amount.toStringAsFixed(0)}',
    );
    await preferences.setBool(_seenIntroKey, true);
    notifyListeners();
  }

  int get lowStockCount =>
      inventoryItems.where((i) => i.isLowStock || i.isOutOfStock).length;

  List<String> get inventoryCategories {
    final cats =
        inventoryItems
            .map((i) => i.category)
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return cats;
  }

  Future<void> reloadData() async {
    menuItems = await database.getMenuItems();
    orders = await database.getOrders();
    syncEvents = await database.getSyncEvents(statuses: null, limit: 100);
    inventoryItems = await database.getInventoryItems();
    notifyListeners();
  }

  Future<void> _handleDatabaseChanged() async {
    final previousOrderIds = Set<String>.from(_knownOrderIds);
    await reloadData();
    _knownOrderIds
      ..clear()
      ..addAll(orders.map((order) => order.id));
    await _autoPrintNewOrders(previousOrderIds);
  }

  Future<bool> saveSettings({
    required String restaurantName,
    required String outletName,
    required String cloudApiUrl,
    required String restaurantId,
    required String outletId,
    required bool cloudSyncEnabled,
    required int autoSyncIntervalSeconds,
  }) async {
    return _runBusy(() async {
      serverConfig = serverConfig.copyWith(
        restaurantName: restaurantName.trim(),
        outletName: outletName.trim(),
        restaurantId: restaurantId.trim().isEmpty
            ? serverConfig.restaurantId
            : restaurantId.trim(),
        outletId: outletId.trim().isEmpty
            ? serverConfig.outletId
            : outletId.trim(),
      );
      cloudConfig = cloudConfig.copyWith(
        baseUrl: CloudDefaults.resolveBaseUrl(cloudApiUrl),
        enabled: cloudSyncEnabled,
        autoSyncIntervalSeconds: autoSyncIntervalSeconds.clamp(10, 3600),
      );
      await _persistSettings();
      syncService.configure(
        cloudConfig: cloudConfig,
        serverConfig: serverConfig,
      );
      if (isCloudReady && cloudConfig.canSync) {
        unawaited(syncService.syncNow());
      }
    });
  }

  Future<bool> provisionTenant({
    required String restaurantName,
    required String outletName,
  }) async {
    return _runBusy(() async {
      await _provisionTenantInternal(
        restaurantName: restaurantName,
        outletName: outletName,
      );
    });
  }

  Future<bool> createAccountAndProvisionTenant({
    required String restaurantName,
    required String outletName,
    required String email,
    required String username,
    required String password,
  }) async {
    return _runBusy(() async {
      await _provisionTenantInternal(
        restaurantName: restaurantName,
        outletName: outletName,
      );
      accountEmail = email.trim();
      accountUsername = username.trim();
      _accountPassword = password;
      isLoggedIn = true;
      await _persistAccountAuth();
    });
  }

  Future<bool> loginWithAccount({
    required String usernameOrEmail,
    required String password,
  }) async {
    return _runBusy(() async {
      final id = usernameOrEmail.trim().toLowerCase();
      final cloudErrors = <Object>[];
      if (cloudConfig.hasValidBaseUrl) {
        try {
          await _loginCloudAccount(usernameOrEmail: id, password: password);
          return;
        } catch (error) {
          cloudErrors.add(error);
        }
      }

      if (accountUsername.trim().isEmpty || _accountPassword.isEmpty) {
        if (cloudErrors.isNotEmpty) {
          throw Exception(cloudErrors.first.toString());
        }
        throw Exception(
          'No account found on this device. Please create account first.',
        );
      }
      await _loginLocalAccount(usernameOrEmail: id, password: password);
    });
  }

  Future<bool> signInWithGoogle() async {
    return _runBusy(() async {
      await _ensureGoogleSignInInitialized();
      if (kIsWeb && !_googleSignIn.supportsAuthenticate()) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final userCredential = await FirebaseAuth.instance.signInWithPopup(
          provider,
        );
        final user = userCredential.user;
        if (user == null) {
          throw Exception('Google sign-in did not return a Firebase user.');
        }
        accountEmail = user.email ?? '';
        accountUsername = _resolveFirebaseAccountName(user);
        googleUid = user.uid;
        _accountPassword = '';
        isLoggedIn = true;
        await _restoreGoogleTenantIfLinked();
        await _persistAccountAuth();
        return;
      }

      final googleAccount = await _googleSignIn.authenticate(
        scopeHint: ['email', 'profile'],
      );
      final googleAuth = googleAccount.authentication;
      if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
        throw Exception('Google sign-in did not return an ID token.');
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;
      accountEmail = user?.email ?? googleAccount.email;
      accountUsername = _resolveGoogleAccountName(user, googleAccount);
      googleUid = user?.uid ?? googleAccount.id;
      _accountPassword = '';
      isLoggedIn = true;
      await _restoreGoogleTenantIfLinked();
      await _persistAccountAuth();
    });
  }

  Future<void> _loginCloudAccount({
    required String usernameOrEmail,
    required String password,
  }) async {
    final loginCloudConfig = cloudConfig.copyWith(
      baseUrl: CloudDefaults.resolveBaseUrl(cloudConfig.baseUrl),
      enabled: true,
    );
    cloudApiService.configure(
      cloudConfig: loginCloudConfig,
      serverConfig: serverConfig,
    );
    final result = await cloudApiService.loginAdminAccount(
      usernameOrEmail: usernameOrEmail,
      password: password,
      serverId: serverConfig.serverId,
    );
    serverConfig = serverConfig.copyWith(
      serverId: result.serverId,
      restaurantId: result.restaurantId,
      outletId: result.outletId,
      restaurantName: result.restaurantName,
      outletName: result.outletName,
    );
    cloudConfig = loginCloudConfig.copyWith(deviceToken: result.deviceToken);
    accountEmail = result.email;
    accountUsername = result.username;
    googleUid = '';
    _accountPassword = password;
    isLoggedIn = true;
    await _persistSettings();
    await _persistAccountAuth();
    syncService.configure(cloudConfig: cloudConfig, serverConfig: serverConfig);
    unawaited(syncService.syncNow());
  }

  Future<void> _loginLocalAccount({
    required String usernameOrEmail,
    required String password,
  }) async {
    final usernameMatch =
        accountUsername.trim().toLowerCase() == usernameOrEmail;
    final emailMatch = accountEmail.trim().toLowerCase() == usernameOrEmail;
    if ((!usernameMatch && !emailMatch) || _accountPassword != password) {
      throw Exception('Invalid username/email or password.');
    }
    if (!isTenantReady) {
      throw Exception(
        'Restaurant setup is incomplete on this device. Please create account again.',
      );
    }
    isLoggedIn = true;
    await _persistAccountAuth();
  }

  Future<void> logOut() async {
    isLoggedIn = false;
    lastError = null;
    await FirebaseAuth.instance.signOut();
    try {
      await _ensureGoogleSignInInitialized();
      await _googleSignIn.signOut();
    } on Object {
      // Firebase sign-out above is enough to protect the app session.
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_accountLoggedInKey, false);
    notifyListeners();
  }

  Future<void> saveMenuItem({
    String? id,
    required String name,
    required String description,
    required String category,
    required double price,
    required bool isAvailable,
    String? imageUrl,
    int? preparationTimeMinutes,
    List<String> tags = const [],
    DateTime? createdAt,
  }) async {
    final now = DateTime.now();
    final item = MenuItem(
      id: id ?? _uuid.v4(),
      name: name.trim(),
      description: description.trim(),
      category: category.trim().isEmpty ? 'General' : category.trim(),
      price: price,
      imageUrl: _cleanNullable(imageUrl),
      isAvailable: isAvailable,
      preparationTimeMinutes: preparationTimeMinutes,
      tags: tags,
      createdAt: createdAt ?? now,
      updatedAt: now,
    );
    await database.upsertMenuItem(item);
    unawaited(syncService.syncNow());
  }

  Future<String> uploadMenuImageDataUrl(String dataUrl) async {
    if (!cloudConfig.canSync) return dataUrl;
    return cloudApiService.uploadMenuImageDataUrl(dataUrl);
  }

  Future<void> deleteMenuItem(String id) async {
    await database.deleteMenuItem(id);
    unawaited(syncService.syncNow());
  }

  Future<void> toggleMenuAvailability(String id, bool isAvailable) async {
    await database.toggleMenuAvailability(id, isAvailable);
    unawaited(syncService.syncNow());
  }

  // ── Inventory ─────────────────────────────────────────────────────────────

  Future<void> saveInventoryItem(InventoryItem item) async {
    await database.upsertInventoryItem(item);
  }

  Future<void> deleteInventoryItem(String id) async {
    await database.deleteInventoryItem(id);
  }

  Future<InventoryItem> adjustStock({
    required String inventoryItemId,
    required double delta,
    required AdjustmentType type,
    String note = '',
  }) async {
    return database.adjustStock(
      inventoryItemId: inventoryItemId,
      delta: delta,
      type: type.value,
      note: note,
    );
  }

  Future<List<StockAdjustment>> getStockAdjustments(
    String inventoryItemId,
  ) async {
    return database.getStockAdjustments(inventoryItemId);
  }

  Future<OrderModel> createManualOrder({
    required List<OrderRequestItem> requestedItems,
    String? customerName,
    String? tableNo,
    String? note,
  }) async {
    final order = await database.createOrder(
      requestedItems: requestedItems,
      customerName: customerName,
      tableNo: tableNo,
      note: note,
      source: OrderSource.manual,
      initialStatus: OrderStatus.accepted,
    );
    unawaited(syncService.syncNow());
    return order;
  }

  Future<void> updateOrderStatus(String id, OrderStatus status) async {
    await database.updateOrderStatus(id, status);
    if (status.adminStatus == OrderStatus.accepted) {
      final order = await database.getOrderById(id);
      if (order != null) {
        await _printAcceptedOrderIfNeeded(order);
      }
    }
    unawaited(syncService.syncNow());
  }

  Future<bool> testCloud() async {
    var cloudOk = false;
    final actionOk = await _runBusy(() async {
      cloudOk = await syncService.testCloud();
    });
    return actionOk && cloudOk;
  }

  Future<bool> syncNow() async {
    return _runBusy(syncService.syncNow);
  }

  Future<bool> retryFailedSync() async {
    return _runBusy(syncService.retryFailed);
  }

  Future<bool> pushRestaurantInfo({
    required String title,
    required String phone,
    required String email,
    required String address,
    required String website,
    required String description,
  }) async {
    return _runBusy(() async {
      final payload = <String, Object?>{
        'serverId': serverConfig.serverId,
        'restaurantId': serverConfig.restaurantId,
        'outletId': serverConfig.outletId,
        'restaurantName': serverConfig.restaurantName,
        'outletName': serverConfig.outletName,
        'infoTitle': title.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'address': address.trim(),
        'website': website.trim(),
        'description': description.trim(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await database.queueServerConfigSync(
        serverId: serverConfig.serverId,
        payload: payload,
      );
      syncService.configure(
        cloudConfig: cloudConfig,
        serverConfig: serverConfig,
      );
      if (cloudConfig.canSync) {
        await syncService.syncNow();
      }
    });
  }

  Future<void> updateUiScale(double value) async {
    final next = value.clamp(minUiScale, maxUiScale).toDouble();
    if ((uiScale - next).abs() < 0.001) return;
    uiScale = next;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_uiScaleKey, uiScale);
  }

  Future<void> updateTableCount(int count) async {
    final clamped = count.clamp(1, 200);
    if (serverConfig.tableCount == clamped) return;
    serverConfig = serverConfig.copyWith(tableCount: clamped);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_tableCountKey, clamped);
  }

  Future<void> updateLanguage(AppLanguage value) async {
    if (language == value) return;
    language = value;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, value.code);
    await preferences.setBool(_languagePreferenceSetKey, true);
  }

  Future<void> updateThemePreference(AppThemePreference value) async {
    if (themePreference == AppThemePreference.white) return;
    themePreference = AppThemePreference.white;
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _themePreferenceKey,
      AppThemePreference.white.code,
    );
  }

  Future<void> clearLocalData() async {
    await database.clearLocalData();
    await reloadData();
  }

  Future<String> printTicketPreview(OrderModel order) {
    return printerService.previewTicket(
      order,
      restaurantName: restaurantName,
      outletName: outletName,
    );
  }

  Future<List<BluetoothPrinterDevice>> refreshPairedPrinters() async {
    pairedPrinters = await printerService.refreshPairedPrinters();
    notifyListeners();
    return pairedPrinters;
  }

  Future<bool> connectPrinter(BluetoothPrinterDevice printer) async {
    final ok = await printerService.connect(printer);
    printerState = printerService.state;
    if (ok) {
      await refreshPairedPrinters();
    } else {
      notifyListeners();
    }
    return ok;
  }

  Future<bool> disconnectPrinter() async {
    final ok = await printerService.disconnect();
    printerState = printerService.state;
    notifyListeners();
    return ok;
  }

  Future<void> setAutoPrintOrders(bool value) async {
    await printerService.setAutoPrintEnabled(value);
    printerState = printerService.state;
    notifyListeners();
  }

  Future<bool> testPrinter() {
    return printerService.testPrint(
      restaurantName: restaurantName,
      outletName: outletName,
    );
  }

  Future<bool> printOrderTicket(OrderModel order) {
    return printerService.printOrderTicket(
      order,
      restaurantName: restaurantName,
      outletName: outletName,
    );
  }

  Future<void> _autoPrintNewOrders(Set<String> previousOrderIds) async {
    if (!printerState.autoPrintEnabled || !printerState.hasSelectedPrinter) {
      return;
    }
    final acceptedOrders =
        orders
            .where((order) {
              final becameAccepted =
                  !previousOrderIds.contains(order.id) ||
                  order.status.adminStatus == OrderStatus.accepted;
              return becameAccepted &&
                  order.status.adminStatus == OrderStatus.accepted &&
                  !printerService.hasPrintedOrder(order.id) &&
                  !_autoPrintInFlight.contains(order.id);
            })
            .toList(growable: false)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final order in acceptedOrders) {
      await _printAcceptedOrderIfNeeded(order);
    }
  }

  Future<void> _printAcceptedOrderIfNeeded(OrderModel order) async {
    if (!printerState.autoPrintEnabled ||
        !printerState.hasSelectedPrinter ||
        order.status.adminStatus != OrderStatus.accepted ||
        printerService.hasPrintedOrder(order.id) ||
        _autoPrintInFlight.contains(order.id)) {
      return;
    }
    _autoPrintInFlight.add(order.id);
    try {
      await printOrderTicket(order);
    } finally {
      _autoPrintInFlight.remove(order.id);
    }
  }

  List<OrderModel> ordersFor({OrderStatus? status, OrderSource? source}) {
    return orders
        .where((order) {
          final matchesStatus =
              status == null || order.status.adminStatus == status;
          final matchesSource = source == null || order.source == source;
          return matchesStatus && matchesSource;
        })
        .toList(growable: false);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(syncService.dispose());
    unawaited(printerService.dispose());
    cloudApiService.close();
    unawaited(database.close());
    super.dispose();
  }

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInit ??= _googleSignIn.initialize(
      clientId: kIsWeb ? DefaultFirebaseOptions.webClientId : null,
      serverClientId: DefaultFirebaseOptions.webClientId,
    );
  }

  String _resolveGoogleAccountName(
    User? firebaseUser,
    GoogleSignInAccount googleAccount,
  ) {
    final displayName = firebaseUser?.displayName ?? googleAccount.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    final email = firebaseUser?.email ?? googleAccount.email;
    final localPart = email.split('@').first.trim();
    return localPart.isEmpty ? 'Google Admin' : localPart;
  }

  String _resolveFirebaseAccountName(User firebaseUser) {
    final displayName = firebaseUser.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    final email = firebaseUser.email ?? '';
    final localPart = email.split('@').first.trim();
    return localPart.isEmpty ? 'Google Admin' : localPart;
  }

  Future<bool> _runBusy(Future<void> Function() action) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (error) {
      lastError = error.toString();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _persistSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _restaurantNameKey,
      serverConfig.restaurantName,
    );
    await preferences.setString(_outletNameKey, serverConfig.outletName);
    await preferences.setString(_restaurantIdKey, serverConfig.restaurantId);
    await preferences.setString(_outletIdKey, serverConfig.outletId);
    await preferences.setString(_serverIdKey, serverConfig.serverId);
    await preferences.setString(_cloudApiUrlKey, cloudConfig.baseUrl);
    await preferences.setBool(_cloudSyncEnabledKey, cloudConfig.enabled);
    await preferences.setString(_deviceTokenKey, cloudConfig.deviceToken);
    await preferences.setString(_languageKey, language.code);
    await preferences.setString(_themePreferenceKey, themePreference.code);
    await preferences.setDouble(_uiScaleKey, uiScale);
    await preferences.setInt(
      _autoSyncIntervalKey,
      cloudConfig.autoSyncIntervalSeconds,
    );
    await preferences.setInt(_tableCountKey, serverConfig.tableCount);
  }

  Future<void> _persistAccountAuth() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_googleUidKey, googleUid);
    await preferences.setString(_accountEmailKey, accountEmail);
    await preferences.setString(_accountUsernameKey, accountUsername);
    await preferences.setString(_accountPasswordKey, _accountPassword);
    await preferences.setBool(_accountLoggedInKey, isLoggedIn);
  }

  Future<void> _provisionTenantInternal({
    required String restaurantName,
    required String outletName,
  }) async {
    final bootstrapCloudConfig = cloudConfig.copyWith(
      baseUrl: CloudDefaults.resolveBaseUrl(cloudConfig.baseUrl),
      enabled: true,
    );
    cloudApiService.configure(
      cloudConfig: bootstrapCloudConfig,
      serverConfig: serverConfig,
    );
    final tenant = await cloudApiService.bootstrapTenant(
      serverId: serverConfig.serverId,
      restaurantName: restaurantName.trim(),
      outletName: outletName.trim(),
      restaurantId: serverConfig.restaurantId,
      outletId: serverConfig.outletId,
    );
    serverConfig = serverConfig.copyWith(
      serverId: tenant.serverId,
      restaurantId: tenant.restaurantId,
      outletId: tenant.outletId,
      restaurantName: tenant.restaurantName,
      outletName: tenant.outletName,
    );
    cloudConfig = bootstrapCloudConfig.copyWith(
      deviceToken: tenant.deviceToken,
    );
    await _persistSettings();
    syncService.configure(cloudConfig: cloudConfig, serverConfig: serverConfig);
    unawaited(syncService.syncNow());
  }

  Future<void> _restoreGoogleTenantIfLinked() async {
    if (googleUid.trim().isEmpty || accountEmail.trim().isEmpty) return;
    final googleCloudConfig = cloudConfig.copyWith(
      baseUrl: CloudDefaults.resolveBaseUrl(cloudConfig.baseUrl),
      enabled: true,
    );
    cloudApiService.configure(
      cloudConfig: googleCloudConfig,
      serverConfig: serverConfig,
    );
    try {
      final result = await cloudApiService.loginGoogleAccount(
        googleUid: googleUid,
        email: accountEmail,
        displayName: accountUsername,
        serverId: serverConfig.serverId,
      );
      await _applyCloudLoginResult(result, googleCloudConfig);
    } on CloudApiException catch (error) {
      final message = error.toString();
      if (message.contains('No restaurant is linked')) {
        return;
      }
      lastError = message;
    }
  }

  Future<void> _provisionGoogleTenantInternal({
    required String restaurantName,
    required String outletName,
  }) async {
    final googleCloudConfig = cloudConfig.copyWith(
      baseUrl: CloudDefaults.resolveBaseUrl(cloudConfig.baseUrl),
      enabled: true,
    );
    cloudApiService.configure(
      cloudConfig: googleCloudConfig,
      serverConfig: serverConfig,
    );
    final result = await cloudApiService.loginGoogleAccount(
      googleUid: googleUid,
      email: accountEmail,
      displayName: accountUsername,
      serverId: serverConfig.serverId,
      restaurantName: restaurantName,
      outletName: outletName.trim().isEmpty ? 'Main Outlet' : outletName,
      restaurantId: serverConfig.restaurantId,
      outletId: serverConfig.outletId,
    );
    await _applyCloudLoginResult(result, googleCloudConfig);
  }

  Future<void> _applyCloudLoginResult(
    AdminLoginResult result,
    CloudConfig baseCloudConfig,
  ) async {
    serverConfig = serverConfig.copyWith(
      serverId: result.serverId,
      restaurantId: result.restaurantId,
      outletId: result.outletId,
      restaurantName: result.restaurantName,
      outletName: result.outletName,
    );
    cloudConfig = baseCloudConfig.copyWith(deviceToken: result.deviceToken);
    if (result.email.trim().isNotEmpty) accountEmail = result.email;
    if (result.username.trim().isNotEmpty) accountUsername = result.username;
    await _persistSettings();
    syncService.configure(cloudConfig: cloudConfig, serverConfig: serverConfig);
    unawaited(syncService.syncNow());
  }

  Future<void> _persistBkashPayment(BkashPaymentSession session) async {
    final preferences = await SharedPreferences.getInstance();
    bkashPaymentVerified = true;
    lastBkashPaymentId = session.paymentId;
    lastBkashTransactionId = session.transactionId;
    hasSeenIntro = true;
    await preferences.setBool(_bkashPaymentVerifiedKey, true);
    await preferences.setString(_bkashPaymentIdKey, session.paymentId);
    await preferences.setBool(_seenIntroKey, true);
    final transactionId = session.transactionId?.trim();
    if (transactionId != null && transactionId.isNotEmpty) {
      await preferences.setString(_bkashTransactionIdKey, transactionId);
    }
    notifyListeners();
  }

  Future<String> _getOrCreatePreference(
    SharedPreferences preferences,
    String key,
    String fallback,
  ) async {
    final existing = preferences.getString(key);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    await preferences.setString(key, fallback);
    return fallback;
  }

  String? _cleanNullable(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static final String _seenIntroKey = 'local_pos_seen_intro';
  static final String _restaurantNameKey = 'local_pos_restaurant_name';
  static final String _outletNameKey = 'local_pos_outlet_name';
  static final String _serverIdKey = 'local_pos_server_id';
  static final String _restaurantIdKey = 'local_pos_restaurant_id';
  static final String _outletIdKey = 'local_pos_outlet_id';
  static final String _cloudApiUrlKey = 'local_pos_cloud_api_url';
  static final String _deviceTokenKey = 'local_pos_device_token';
  static final String _cloudSyncEnabledKey = 'local_pos_cloud_sync_enabled';
  static final String _autoSyncIntervalKey = 'local_pos_auto_sync_interval';
  static final String _uiScaleKey = 'local_pos_ui_scale';
  static final String _languageKey = 'local_pos_language';
  static final String _languagePreferenceSetKey =
      'local_pos_language_preference_set';
  static final String _themePreferenceKey = 'local_pos_theme_preference';
  static final String _bkashPaymentVerifiedKey =
      'local_pos_bkash_payment_verified';
  static final String _bkashPaymentIdKey = 'local_pos_bkash_payment_id';
  static final String _bkashTransactionIdKey = 'local_pos_bkash_transaction_id';
  static final String _accountEmailKey = 'local_pos_account_email';
  static final String _accountUsernameKey = 'local_pos_account_username';
  static final String _googleUidKey = 'local_pos_google_uid';
  static final String _accountPasswordKey = 'local_pos_account_password';
  static final String _accountLoggedInKey = 'local_pos_account_logged_in';
  static final String _tableCountKey = 'local_pos_table_count';
  static double minUiScale = 0.78;
  static double maxUiScale = 1.08;
}
