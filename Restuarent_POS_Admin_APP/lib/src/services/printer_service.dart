import 'dart:async';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_item.dart';
import '../models/order_model.dart';

class BluetoothPrinterDevice {
  BluetoothPrinterDevice({required this.name, required this.address});

  final String name;
  final String address;

  String get label => name.trim().isEmpty ? address : name.trim();
}

class PrinterRuntimeState {
  PrinterRuntimeState({
    required this.autoPrintEnabled,
    required this.connected,
    required this.busy,
    this.selectedPrinterName,
    this.selectedPrinterAddress,
    this.lastError,
    this.lastPrintedOrderNo,
    this.lastPrintedAt,
  });

  final bool autoPrintEnabled;
  final bool connected;
  final bool busy;
  final String? selectedPrinterName;
  final String? selectedPrinterAddress;
  final String? lastError;
  final String? lastPrintedOrderNo;
  final DateTime? lastPrintedAt;

  bool get hasSelectedPrinter {
    return selectedPrinterAddress != null &&
        selectedPrinterAddress!.trim().isNotEmpty;
  }

  String get selectedPrinterLabel {
    final name = selectedPrinterName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return selectedPrinterAddress ?? 'No printer selected';
  }

  PrinterRuntimeState copyWith({
    bool? autoPrintEnabled,
    bool? connected,
    bool? busy,
    String? selectedPrinterName,
    String? selectedPrinterAddress,
    String? lastError,
    String? lastPrintedOrderNo,
    DateTime? lastPrintedAt,
    bool clearLastError = false,
    bool clearPrinter = false,
  }) {
    return PrinterRuntimeState(
      autoPrintEnabled: autoPrintEnabled ?? this.autoPrintEnabled,
      connected: connected ?? this.connected,
      busy: busy ?? this.busy,
      selectedPrinterName: clearPrinter
          ? null
          : selectedPrinterName ?? this.selectedPrinterName,
      selectedPrinterAddress: clearPrinter
          ? null
          : selectedPrinterAddress ?? this.selectedPrinterAddress,
      lastError: clearLastError ? null : lastError ?? this.lastError,
      lastPrintedOrderNo: lastPrintedOrderNo ?? this.lastPrintedOrderNo,
      lastPrintedAt: lastPrintedAt ?? this.lastPrintedAt,
    );
  }
}

class PrinterService {
  static const String _autoPrintKey = 'printer_auto_print_enabled';
  static const String _printerNameKey = 'printer_selected_name';
  static const String _printerAddressKey = 'printer_selected_address';
  static const String _printedOrderIdsKey = 'printer_printed_order_ids';
  static const int _ticketWidth = 32;

  final StreamController<PrinterRuntimeState> _stateController =
      StreamController<PrinterRuntimeState>.broadcast();

  PrinterRuntimeState _state = PrinterRuntimeState(
    autoPrintEnabled: true,
    connected: false,
    busy: false,
  );
  final Set<String> _printedOrderIds = <String>{};

  PrinterRuntimeState get state => _state;
  Stream<PrinterRuntimeState> get stateStream => _stateController.stream;

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _printedOrderIds
      ..clear()
      ..addAll(preferences.getStringList(_printedOrderIdsKey) ?? []);
    // Do not touch the Bluetooth plugin during app boot. Some Android devices
    // wait on the native connection-status call until Bluetooth permission/state
    // is ready, which can keep the splash screen open. We check live status only
    // when the user opens printer actions or when printing.
    _emit(
      _state.copyWith(
        autoPrintEnabled: preferences.getBool(_autoPrintKey) ?? true,
        selectedPrinterName: preferences.getString(_printerNameKey),
        selectedPrinterAddress: preferences.getString(_printerAddressKey),
        connected: false,
        clearLastError: true,
      ),
    );
  }

  Future<List<BluetoothPrinterDevice>> refreshPairedPrinters() async {
    _emit(_state.copyWith(busy: true, clearLastError: true));
    try {
      await _ensureBluetoothReady();
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      return devices
          .map(
            (device) => BluetoothPrinterDevice(
              name: device.name,
              address: device.macAdress,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      _emit(_state.copyWith(lastError: _friendlyError(error)));
      return [];
    } finally {
      _emit(
        _state.copyWith(busy: false, connected: await _readConnectionStatus()),
      );
    }
  }

  Future<bool> connect(BluetoothPrinterDevice printer) async {
    return _withBusyBool(() async {
      await _ensureBluetoothReady();
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: printer.address,
      );
      if (!connected) {
        throw PrinterException('Could not connect to the selected printer.');
      }
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_printerNameKey, printer.name);
      await preferences.setString(_printerAddressKey, printer.address);
      _emit(
        _state.copyWith(
          selectedPrinterName: printer.name,
          selectedPrinterAddress: printer.address,
          connected: true,
          clearLastError: true,
        ),
      );
      return true;
    });
  }

  Future<bool> disconnect() async {
    return _withBusyBool(() async {
      final disconnected = await PrintBluetoothThermal.disconnect;
      _emit(_state.copyWith(connected: !disconnected, clearLastError: true));
      return disconnected;
    });
  }

  Future<void> setAutoPrintEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoPrintKey, value);
    _emit(_state.copyWith(autoPrintEnabled: value, clearLastError: true));
  }

  Future<bool> testPrint({
    required String restaurantName,
    required String outletName,
  }) async {
    return _withBusyBool(() async {
      await _ensureConnected();
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      final now = DateTime.now();
      final bytes = <int>[
        ...generator.reset(),
        ...generator.text(
          _ticketText(restaurantName, fallback: 'HYBRID POS'),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ),
        ),
        ...generator.text(
          _ticketText(outletName, fallback: 'Receipt Printer Test'),
          styles: PosStyles(align: PosAlign.center, bold: true),
        ),
        ...generator.hr(),
        ...generator.text('Deli ES421 58mm printer test'),
        ...generator.text(DateFormat('MMM d, yyyy h:mm a').format(now)),
        ...generator.hr(),
        ...generator.text(
          'Printer is ready.',
          styles: PosStyles(align: PosAlign.center, bold: true),
        ),
        ...generator.feed(2),
        ...generator.cut(),
      ];
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) throw PrinterException('Test print failed.');
      _emit(_state.copyWith(clearLastError: true));
      return true;
    });
  }

  Future<bool> printOrderTicket(
    OrderModel order, {
    required String restaurantName,
    required String outletName,
    bool markAsPrinted = true,
  }) async {
    return _withBusyBool(() async {
      await _ensureConnected();
      final bytes = await _buildOrderTicketBytes(
        order,
        restaurantName: restaurantName,
        outletName: outletName,
      );
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) {
        throw PrinterException('Printing ${order.orderNo} failed.');
      }
      if (markAsPrinted) {
        await markOrderPrinted(order);
      }
      _emit(
        _state.copyWith(
          lastPrintedOrderNo: order.orderNo,
          lastPrintedAt: DateTime.now(),
          clearLastError: true,
        ),
      );
      return true;
    });
  }

  Future<void> markOrderPrinted(OrderModel order) async {
    _printedOrderIds.add(order.id);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _printedOrderIdsKey,
      _printedOrderIds.toList(),
    );
  }

  bool hasPrintedOrder(String orderId) => _printedOrderIds.contains(orderId);

  Future<String> previewTicket(
    OrderModel order, {
    String? restaurantName,
    String? outletName,
  }) async {
    final buffer = StringBuffer();
    _writePreviewCopy(
      buffer,
      order,
      copyLabel: 'ADMIN COPY',
      restaurantName: restaurantName ?? 'HYBRID POS',
    );
    buffer.writeln(_separator('*'));
    _writePreviewCopy(
      buffer,
      order,
      copyLabel: 'CUSTOMER COPY',
      restaurantName: restaurantName ?? 'HYBRID POS',
    );
    return buffer.toString();
  }

  Future<List<int>> _buildOrderTicketBytes(
    OrderModel order, {
    required String restaurantName,
    required String outletName,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];
    bytes
      ..addAll(generator.reset())
      ..addAll(
        _buildCompactCopy(
          generator,
          order,
          copyLabel: 'ADMIN COPY',
          restaurantName: restaurantName,
          outletName: outletName,
        ),
      )
      ..addAll(generator.text(_separator('*')))
      ..addAll(
        _buildCompactCopy(
          generator,
          order,
          copyLabel: 'CUSTOMER COPY',
          restaurantName: restaurantName,
          outletName: outletName,
        ),
      )
      ..addAll(generator.feed(1));
    return bytes;
  }

  List<int> _buildCompactCopy(
    Generator generator,
    OrderModel order, {
    required String copyLabel,
    required String restaurantName,
    required String outletName,
  }) {
    final currency = NumberFormat.currency(symbol: 'Tk ', decimalDigits: 0);
    final date = DateFormat('dd MMM yy h:mm a').format(order.createdAt);
    final table = _ticketText(order.tableNo ?? 'Takeaway');
    final bytes = <int>[];
    bytes
      ..addAll(
        generator.text(
          _ticketText(restaurantName, fallback: 'Restaurant'),
          styles: PosStyles(align: PosAlign.center, bold: true),
        ),
      )
      ..addAll(
        generator.text(
          copyLabel,
          styles: PosStyles(align: PosAlign.center, bold: true),
        ),
      )
      ..addAll(generator.text(_twoCol('No ${order.displaySequence}', date)))
      ..addAll(
        generator.text(
          _twoCol('Table ${_shortText(table, 13)}', order.source.label),
        ),
      );
    final customer = order.customerName?.trim();
    if (customer != null && customer.isNotEmpty) {
      bytes.addAll(generator.text('Name: ${_shortText(customer, 26)}'));
    }
    final note = order.note?.trim();
    if (copyLabel == 'ADMIN COPY' && note != null && note.isNotEmpty) {
      bytes.addAll(generator.text('Note: ${_shortText(note, 26)}'));
    }
    bytes.addAll(generator.text(_separator('-')));

    for (var i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      final name = '${i + 1}. ${_itemLabel(item)}';
      final qty = '${item.qty}x';
      final total = currency.format(item.lineTotal);
      bytes.addAll(generator.text(_itemLine(name, qty, total)));
    }

    bytes
      ..addAll(generator.text(_separator('-')))
      ..addAll(
        generator.text(
          _twoCol('TOTAL', currency.format(order.total)),
          styles: PosStyles(bold: true),
        ),
      );
    if (copyLabel == 'CUSTOMER COPY') {
      bytes.addAll(generator.text(_center('Thank you')));
    } else {
      bytes.addAll(generator.text(_twoCol('Status', order.status.label)));
    }
    return bytes;
  }

  void _writePreviewCopy(
    StringBuffer buffer,
    OrderModel order, {
    required String copyLabel,
    required String restaurantName,
  }) {
    final currency = NumberFormat.currency(symbol: 'Tk ', decimalDigits: 0);
    buffer
      ..writeln(_ticketText(restaurantName))
      ..writeln(copyLabel)
      ..writeln(
        _twoCol(
          'No ${order.displaySequence}',
          DateFormat('dd MMM yy h:mm a').format(order.createdAt),
        ),
      )
      ..writeln(
        _twoCol(
          'Table ${_shortText(order.tableNo ?? 'Takeaway', 13)}',
          order.source.label,
        ),
      )
      ..writeln(_separator('-'));
    for (var i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      buffer.writeln(
        _itemLine(
          '${i + 1}. ${_itemLabel(item)}',
          '${item.qty}x',
          currency.format(item.lineTotal),
        ),
      );
    }
    buffer
      ..writeln(_separator('-'))
      ..writeln(_twoCol('TOTAL', currency.format(order.total)));
    if (copyLabel == 'ADMIN COPY') {
      buffer.writeln(_twoCol('Status', order.status.label));
    }
  }

  String _itemLabel(OrderItem item) {
    final name = _ticketText(item.name);
    final unit = _extractUnit(name);
    final baseName = unit == null
        ? name
        : name
              .replaceFirst(unit, '')
              .replaceAll(RegExp(r'[-–—,]+'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final label = unit == null
        ? name
        : '${baseName.isEmpty ? 'Item' : baseName} - $unit';
    return _shortText(label, 18);
  }

  String? _extractUnit(String name) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?\s?(?:g|gm|kg|ml|l|pcs|pc))\b',
      caseSensitive: false,
    ).firstMatch(name);
    return match?.group(1);
  }

  String _shortText(String value, int maxChars) {
    final clean = _ticketText(value).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= maxChars) return clean;
    if (maxChars <= 1) return clean.substring(0, maxChars);
    return clean.substring(0, maxChars - 1).trimRight();
  }

  String _separator(String ch) => ch * _ticketWidth;

  String _center(String value) {
    final clean = _shortText(value, _ticketWidth);
    final left = ((_ticketWidth - clean.length) / 2).floor();
    return '${' ' * left}$clean';
  }

  String _twoCol(String left, String right) {
    final cleanRight = _shortText(right, 14);
    final leftWidth = _ticketWidth - cleanRight.length - 1;
    final cleanLeft = _shortText(left, leftWidth);
    final gap = _ticketWidth - cleanLeft.length - cleanRight.length;
    return '$cleanLeft${' ' * gap}$cleanRight';
  }

  String _itemLine(String name, String qty, String total) {
    final cleanTotal = _shortText(total, 8);
    final cleanQty = _shortText(qty, 3);
    final nameWidth = _ticketWidth - cleanQty.length - cleanTotal.length - 2;
    final cleanName = _shortText(name, nameWidth);
    final used = cleanName.length + cleanQty.length + cleanTotal.length;
    final gap = _ticketWidth - used;
    final leftGap = gap <= 1 ? 1 : 2;
    final rightGap = gap - leftGap;
    return '$cleanName${' ' * leftGap}$cleanQty${' ' * rightGap}$cleanTotal';
  }

  Future<void> _ensureBluetoothReady() async {
    if (!Platform.isAndroid &&
        !Platform.isIOS &&
        !Platform.isMacOS &&
        !Platform.isWindows) {
      throw PrinterException('Bluetooth printing is not supported here.');
    }
    if (Platform.isAndroid) {
      final alreadyGranted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!alreadyGranted) {
        final statuses = await [
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
        ].request();
        final granted = statuses.values.every((status) => status.isGranted);
        if (!granted) {
          throw PrinterException('Bluetooth permission is required.');
        }
      }
    }
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      throw PrinterException('Turn on Bluetooth first.');
    }
  }

  Future<void> _ensureConnected() async {
    await _ensureBluetoothReady();
    var connected = await _readConnectionStatus();
    if (!connected) {
      final address = _state.selectedPrinterAddress;
      if (address == null || address.trim().isEmpty) {
        throw PrinterException('Select a Bluetooth printer first.');
      }
      connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      );
    }
    if (!connected) {
      throw PrinterException('Printer is not connected.');
    }
    _emit(_state.copyWith(connected: true, clearLastError: true));
  }

  Future<bool> _readConnectionStatus() async {
    try {
      return await PrintBluetoothThermal.connectionStatus.timeout(
        Duration(milliseconds: 900),
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _withBusyBool(Future<bool> Function() action) async {
    _emit(_state.copyWith(busy: true, clearLastError: true));
    try {
      return await action();
    } catch (error) {
      _emit(
        _state.copyWith(
          connected: await _readConnectionStatus(),
          lastError: _friendlyError(error),
        ),
      );
      if (kDebugMode) debugPrint('Printer error: $error');
      return false;
    } finally {
      _emit(
        _state.copyWith(busy: false, connected: await _readConnectionStatus()),
      );
    }
  }

  String _friendlyError(Object error) {
    if (error is PrinterException) return error.message;
    final value = error.toString();
    if (value.contains('permission')) {
      return 'Bluetooth permission is required.';
    }
    if (value.contains('bluetooth')) return 'Bluetooth is not ready.';
    return 'Printer action failed. Check printer power and Bluetooth pairing.';
  }

  String _ticketText(String value, {String fallback = '-'}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return fallback;
    // ES421 lists English/Chinese language support. Keep receipts ASCII-safe
    // so Bluetooth ESC/POS text mode does not crash on unsupported glyphs.
    return trimmed
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '?')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  void _emit(PrinterRuntimeState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  Future<void> dispose() async {
    await _stateController.close();
  }
}

class PrinterException implements Exception {
  PrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}
