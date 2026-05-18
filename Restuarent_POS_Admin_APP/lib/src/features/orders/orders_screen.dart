import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/menu_image_view.dart';
import '../../core/widgets/pos_compact_ui.dart';
import '../../models/menu_item.dart';
import '../../models/order_item.dart';
import '../../models/order_model.dart';
import '../../models/order_status.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final allOrders = app.ordersFor();

    final pendingOrders = allOrders
        .where((o) => o.status.adminStatus == OrderStatus.pending)
        .toList(growable: false);
    final acceptedOrders = allOrders
        .where((o) => o.status.adminStatus == OrderStatus.accepted)
        .toList(growable: false);
    pendingOrders.sort(_sortOrders);
    acceptedOrders.sort(_sortOrders);

    final menuItems = app.menuItems;
    final canCreate = app.menuItems.any((i) => i.isAvailable);

    return Scaffold(
      backgroundColor: PosColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              pendingCount: pendingOrders.length,
              acceptedCount: acceptedOrders.length,
              canCreate: canCreate,
              onAdd: () => _openNewOrderForm(context),
            ),
            _TabStrip(
              controller: _tabs,
              pendingCount: pendingOrders.length,
              acceptedCount: acceptedOrders.length,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _OrderList(
                    orders: pendingOrders,
                    menuItems: menuItems,
                    emptyLabel: 'No pending orders',
                    emptyIcon: Icons.inbox_outlined,
                    onPrint: (o) => _printDirect(context, o),
                    onStatus: (o, s) => _changeStatus(context, o, s),
                  ),
                  _OrderList(
                    orders: acceptedOrders,
                    menuItems: menuItems,
                    emptyLabel: 'No accepted orders',
                    emptyIcon: Icons.room_service_outlined,
                    onPrint: (o) => _printDirect(context, o),
                    onStatus: (o, s) => _changeStatus(context, o, s),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _sortOrders(OrderModel a, OrderModel b) {
    final priority = a.status.priority.compareTo(b.status.priority);
    if (priority != 0) return priority;
    return b.createdAt.compareTo(a.createdAt);
  }

  Future<void> _openNewOrderForm(BuildContext context) async {
    final app = AppScope.of(context);
    final menuItems = app.menuItems
        .where((i) => i.isAvailable)
        .toList(growable: false);
    final tableCount = app.serverConfig.tableCount;

    final result = await Navigator.of(context).push<_OrderResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _NewOrderPage(menuItems: menuItems, tableCount: tableCount),
      ),
    );
    if (result == null || !context.mounted) return;

    final order = await app.createManualOrder(
      requestedItems: result.items,
      tableNo: result.tableNo,
      note: result.note,
    );

    if (!context.mounted) return;

    final printed = app.printerService.hasPrintedOrder(order.id)
        ? true
        : app.printerState.connected
        ? await app.printOrderTicket(order)
        : false;

    if (!context.mounted) return;
    _showOrderCreated(context, order, printed: printed);
  }

  Future<void> _printDirect(BuildContext context, OrderModel order) async {
    final app = AppScope.of(context);
    if (!app.printerState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Printer not connected — go to Settings to pair one.'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
      return;
    }
    final ok = await app.printOrderTicket(order);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Ticket printed for ${order.displaySequence}'
              : (app.printerState.lastError ?? 'Print failed'),
        ),
      ),
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    OrderModel order,
    OrderStatus status,
  ) async {
    final app = AppScope.of(context);
    await app.updateOrderStatus(order.id, status);
  }

  void _showOrderCreated(
    BuildContext context,
    OrderModel order, {
    required bool printed,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderCreatedSheet(
        order: order,
        autoPrinted: printed,
        onPrint: () => _printDirect(context, order),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.pendingCount,
    required this.acceptedCount,
    required this.canCreate,
    required this.onAdd,
  });

  final int pendingCount;
  final int acceptedCount;
  final bool canCreate;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 14, 12, 7),
      child: CompactHeader(
        title: 'Orders',
        subtitle: 'অর্ডার · $pendingCount pending · $acceptedCount accepted',
        actions: [
          CompactIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filter orders',
            onPressed: () {},
          ),
          CompactIconButton(
            icon: Icons.add_rounded,
            tooltip: 'New order',
            filled: true,
            onPressed: canCreate ? onAdd : null,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pill tab strip
// ─────────────────────────────────────────────────────────────────────────────

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.controller,
    required this.pendingCount,
    required this.acceptedCount,
  });

  final TabController controller;
  final int pendingCount;
  final int acceptedCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Container(
        height: 43,
        alignment: Alignment.centerLeft,
        child: TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: PosColors.surface,
            borderRadius: BorderRadius.circular(PosRadii.pill),
            border: Border.all(color: PosColors.lineStrong),
          ),
          labelColor: PosColors.slate,
          unselectedLabelColor: PosColors.muted,
          labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
          ),
          labelPadding: EdgeInsets.only(right: 14),
          padding: EdgeInsets.zero,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 64, child: Center(child: Text('Pending'))),
                  if (pendingCount > 0) ...[
                    SizedBox(width: 6),
                    _TabBadge(count: pendingCount, active: true),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Accepted'),
                  if (acceptedCount > 0) ...[
                    SizedBox(width: 6),
                    _TabBadge(count: acceptedCount, active: false),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count, required this.active});
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active
            ? PosColors.primary
            : PosColors.surfaceWarm.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(PosRadii.pill),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          color: active ? PosColors.primaryDark : PosColors.muted,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order list
// ─────────────────────────────────────────────────────────────────────────────

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.orders,
    required this.menuItems,
    required this.emptyLabel,
    required this.emptyIcon,
    required this.onPrint,
    required this.onStatus,
  });

  final List<OrderModel> orders;
  final List<MenuItem> menuItems;
  final String emptyLabel;
  final IconData emptyIcon;
  final void Function(OrderModel) onPrint;
  final void Function(OrderModel, OrderStatus) onStatus;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return EmptyCompactState(
        icon: emptyIcon,
        title: emptyLabel,
        message: 'New tickets will appear here automatically.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 18),
      itemCount: orders.length,
      separatorBuilder: (_, _) => SizedBox(height: 10),
      itemBuilder: (_, i) => _OrderCard(
        order: orders[i],
        menuItems: menuItems,
        onPrint: () => onPrint(orders[i]),
        onStatus: (s) => onStatus(orders[i], s),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order card with left accent bar
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.menuItems,
    required this.onPrint,
    required this.onStatus,
  });

  final OrderModel order;
  final List<MenuItem> menuItems;
  final VoidCallback onPrint;
  final ValueChanged<OrderStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '৳', decimalDigits: 0);
    final time = _formatTime(order.createdAt.toLocal());
    final adminStatus = order.status.adminStatus;
    final isPending = adminStatus == OrderStatus.pending;
    final accentColor = switch (adminStatus) {
      OrderStatus.pending => PosColors.warning,
      OrderStatus.accepted => PosColors.success,
      OrderStatus.served => PosColors.success,
      OrderStatus.cancelled => PosColors.danger,
      OrderStatus.preparing => PosColors.success,
      OrderStatus.ready => PosColors.success,
    };
    final nextStatus = isPending ? OrderStatus.accepted : null;
    final table = (order.tableNo ?? '').trim();
    final itemCount = order.items.fold<int>(0, (sum, item) => sum + item.qty);
    final summary = _itemsSummary();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: onPrint,
        child: Container(
          constraints: BoxConstraints(minHeight: 142),
          decoration: BoxDecoration(
            color: PosColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PosColors.lineStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 124,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MenuImageView(imageUrl: _primaryImageUrl()),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.10),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.42),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$itemCount item${itemCount == 1 ? '' : 's'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            order.items.isEmpty
                                ? 'Order'
                                : order.items.first.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.86),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              order.displaySequence,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: PosColors.slate,
                                letterSpacing: 0,
                                height: 1,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                PosRadii.pill,
                              ),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              adminStatus.label.toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 8.5,
                                color: accentColor,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          if (table.isNotEmpty) ...[
                            Icon(
                              Icons.table_restaurant_outlined,
                              size: 13,
                              color: PosColors.muted,
                            ),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Table $table',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _metaStyle(),
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: PosColors.muted,
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '$time · ${_ago(order.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _metaStyle(),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: PosColors.slate,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          height: 1.18,
                        ),
                      ),
                      if ((order.note ?? '').trim().isNotEmpty) ...[
                        SizedBox(height: 5),
                        Text(
                          order.note!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: PosColors.muted,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'TOTAL',
                                style: TextStyle(
                                  color: PosColors.muted,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                  height: 1,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                currency.format(order.total),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  color: PosColors.slate,
                                  letterSpacing: 0,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                          Spacer(),
                          _PrintButton(onTap: onPrint),
                          if (nextStatus != null) ...[
                            SizedBox(width: 8),
                            _AdvanceButton(
                              label: 'Accept',
                              color: PosColors.primary,
                              onTap: () => onStatus(nextStatus),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    return DateFormat(isToday ? 'h:mm a' : 'MMM d  h:mm a').format(dt);
  }

  String _ago(DateTime dt) {
    final minutes = DateTime.now().difference(dt.toLocal()).inMinutes;
    if (minutes < 1) return 'now';
    if (minutes < 60) return '$minutes min';
    final hours = (minutes / 60).floor();
    return '$hours hr';
  }

  String? _imageUrlFor(String menuItemId) {
    for (final item in menuItems) {
      if (item.id == menuItemId) return item.imageUrl;
    }
    return null;
  }

  String? _primaryImageUrl() {
    if (order.items.isEmpty) return null;
    return _imageUrlFor(order.items.first.menuItemId);
  }

  String _itemsSummary() {
    if (order.items.isEmpty) return 'No items';
    final visible = order.items
        .take(3)
        .map((item) => '${item.qty}x ${item.name}');
    final rest = order.items.length - 3;
    return [...visible, if (rest > 0) '+$rest more'].join(' · ');
  }

  TextStyle _metaStyle() {
    return TextStyle(
      color: PosColors.muted,
      fontSize: 10.2,
      fontWeight: FontWeight.w800,
      height: 1,
    );
  }
}

class _PrintButton extends StatelessWidget {
  const _PrintButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Print ticket',
      child: SizedBox(
        width: 36,
        height: 36,
        child: Material(
          color: PosColors.surfaceWarm,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(Icons.print_outlined, size: 17, color: PosColors.slate),
          ),
        ),
      ),
    );
  }
}

class _AdvanceButton extends StatelessWidget {
  const _AdvanceButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              color: color.computeLuminance() > 0.4
                  ? PosColors.slate
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order created sheet
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCreatedSheet extends StatelessWidget {
  const _OrderCreatedSheet({
    required this.order,
    required this.autoPrinted,
    required this.onPrint,
  });

  final OrderModel order;
  final bool autoPrinted;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '৳', decimalDigits: 0);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: PosColors.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 6),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: PosColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              color: PosColors.success,
              size: 32,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Order Created!',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          SizedBox(height: 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(PosRadii.pill),
              border: Border.all(color: PosColors.line),
            ),
            child: Text(
              order.displaySequence,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 32,
                color: PosColors.slate,
                letterSpacing: -1,
              ),
            ),
          ),
          SizedBox(height: 8),
          if ((order.tableNo ?? '').isNotEmpty)
            Text(
              'Table ${order.tableNo}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: PosColors.muted,
              ),
            ),
          Text(
            currency.format(order.total),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: PosColors.slate,
            ),
          ),
          SizedBox(height: 20),
          if (autoPrinted)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.print_rounded, size: 16, color: PosColors.success),
                SizedBox(width: 6),
                Text(
                  'Ticket sent to printer',
                  style: TextStyle(
                    color: PosColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onPrint();
                },
                icon: Icon(Icons.print_rounded),
                label: Text(
                  'Print Ticket',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                backgroundColor: PosColors.slate,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PosRadii.md),
                ),
              ),
              child: Text(
                'Done',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New order page — 2-step wizard
// ─────────────────────────────────────────────────────────────────────────────

class _OrderResult {
  _OrderResult({required this.items, this.tableNo, this.note});
  final List<OrderRequestItem> items;
  final String? tableNo;
  final String? note;
}

class _NewOrderPage extends StatefulWidget {
  const _NewOrderPage({required this.menuItems, required this.tableCount});
  final List<MenuItem> menuItems;
  final int tableCount;

  @override
  State<_NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends State<_NewOrderPage> {
  final _pageCtrl = PageController();
  int _step = 0;

  // Step 1 — table
  String? _selectedTable; // null = not yet chosen; '' = take-away

  // Step 2 — menu
  final Map<String, int> _cart = {};
  String _selectedCategory = 'All';
  final _noteCtrl = TextEditingController();
  bool _showNote = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int index) {
    setState(() => _step = index);
    _pageCtrl.animateToPage(
      index,
      duration: Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  void _selectTable(String? table) {
    setState(() => _selectedTable = table);
    Future.delayed(Duration(milliseconds: 160), () => _goToStep(1));
  }

  List<String> get _categories {
    final cats = widget.menuItems.map((i) => i.category).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...cats];
  }

  List<MenuItem> get _visibleItems => widget.menuItems
      .where(
        (i) => _selectedCategory == 'All' || i.category == _selectedCategory,
      )
      .toList(growable: false);

  int get _totalQty => _cart.values.fold(0, (s, q) => s + q);

  double get _total {
    var sum = 0.0;
    for (final entry in _cart.entries) {
      final item = widget.menuItems.firstWhere(
        (m) => m.id == entry.key,
        orElse: () => widget.menuItems.first,
      );
      sum += item.price * entry.value;
    }
    return sum;
  }

  void _tap(String id) {
    HapticFeedback.lightImpact();
    setState(() => _cart[id] = (_cart[id] ?? 0) + 1);
  }

  void _decrement(String id) {
    setState(() {
      final current = _cart[id] ?? 0;
      if (current <= 1) {
        _cart.remove(id);
      } else {
        _cart[id] = current - 1;
      }
    });
  }

  void _submit() {
    if (_cart.isEmpty) return;
    final items = _cart.entries
        .map((e) => OrderRequestItem(menuItemId: e.key, qty: e.value))
        .toList(growable: false);
    final tableNo = (_selectedTable ?? '').isEmpty ? null : _selectedTable;
    Navigator.pop(
      context,
      _OrderResult(
        items: items,
        tableNo: tableNo,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      ),
    );
  }

  String get _tableLabel {
    if (_selectedTable == null) return '';
    if (_selectedTable!.isEmpty) return 'Take Away';
    return 'Table $_selectedTable';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(
              step: _step,
              tableLabel: _tableLabel,
              onClose: () => Navigator.pop(context),
              onBack: _step > 0 ? () => _goToStep(_step - 1) : null,
            ),
            _StepIndicator(step: _step),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: NeverScrollableScrollPhysics(),
                children: [
                  _TablePickerStep(
                    tableCount: widget.tableCount,
                    selected: _selectedTable,
                    onSelect: _selectTable,
                  ),
                  _MenuStep(
                    menuItems: widget.menuItems,
                    visibleItems: _visibleItems,
                    categories: _categories,
                    selectedCategory: _selectedCategory,
                    cart: _cart,
                    total: _total,
                    totalQty: _totalQty,
                    showNote: _showNote,
                    noteCtrl: _noteCtrl,
                    onCategorySelected: (c) =>
                        setState(() => _selectedCategory = c),
                    onTap: _tap,
                    onDecrement: _decrement,
                    onToggleNote: () => setState(() => _showNote = !_showNote),
                    onSubmit: _cart.isNotEmpty ? _submit : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.step,
    required this.tableLabel,
    required this.onClose,
    required this.onBack,
  });

  final int step;
  final String tableLabel;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 8, 12, 0),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: Icon(Icons.arrow_back_rounded),
              color: PosColors.slate,
              tooltip: 'Back',
              onPressed: onBack,
            )
          else
            IconButton(
              icon: Icon(Icons.close_rounded),
              color: PosColors.slate,
              tooltip: 'Cancel',
              onPressed: onClose,
            ),
          SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step == 0 ? 'Select Table' : 'Select Items',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: PosColors.slate,
                  ),
                ),
                if (tableLabel.isNotEmpty)
                  Text(
                    tableLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: PosColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            'Step ${step + 1} of 2',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: PosColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: Duration(milliseconds: 280),
                height: 3,
                decoration: BoxDecoration(
                  color: i <= step ? PosColors.primary : PosColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < 1) SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _TablePickerStep extends StatelessWidget {
  const _TablePickerStep({
    required this.tableCount,
    required this.selected,
    required this.onSelect,
  });

  final int tableCount;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 20),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 100,
        mainAxisExtent: 76,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: tableCount + 1, // +1 for Take Away
      itemBuilder: (_, i) {
        if (i == 0) {
          final sel = selected == '';
          return _TableTile(
            label: 'Take Away',
            sublabel: 'টেক অ্যাওয়ে',
            icon: Icons.shopping_bag_outlined,
            selected: sel,
            onTap: () => onSelect(''),
          );
        }
        final tableNo = '$i';
        final sel = selected == tableNo;
        return _TableTile(
          label: 'T$i',
          sublabel: 'টেবিল $i',
          icon: Icons.table_restaurant_outlined,
          selected: sel,
          onTap: () => onSelect(tableNo),
        );
      },
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? PosColors.primary : PosColors.surface,
          borderRadius: BorderRadius.circular(PosRadii.md),
          border: Border.all(
            color: selected ? PosColors.primary : PosColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? PosColors.primaryDark : PosColors.muted,
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: selected ? PosColors.primaryDark : PosColors.slate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuStep extends StatelessWidget {
  const _MenuStep({
    required this.menuItems,
    required this.visibleItems,
    required this.categories,
    required this.selectedCategory,
    required this.cart,
    required this.total,
    required this.totalQty,
    required this.showNote,
    required this.noteCtrl,
    required this.onCategorySelected,
    required this.onTap,
    required this.onDecrement,
    required this.onToggleNote,
    required this.onSubmit,
  });

  final List<MenuItem> menuItems;
  final List<MenuItem> visibleItems;
  final List<String> categories;
  final String selectedCategory;
  final Map<String, int> cart;
  final double total;
  final int totalQty;
  final bool showNote;
  final TextEditingController noteCtrl;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onDecrement;
  final VoidCallback onToggleNote;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '৳', decimalDigits: 0);
    return Column(
      children: [
        _CategoryChips(
          categories: categories,
          selected: selectedCategory,
          onSelected: onCategorySelected,
        ),
        Expanded(
          child: _MenuGrid(
            items: visibleItems,
            cart: cart,
            onTap: onTap,
            onDecrement: onDecrement,
          ),
        ),
        _CartFooter(
          cart: cart,
          menuItems: menuItems,
          total: total,
          totalQty: totalQty,
          currency: currency,
          showNote: showNote,
          noteCtrl: noteCtrl,
          onToggleNote: onToggleNote,
          onSubmit: onSubmit,
        ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
        itemCount: categories.length,
        separatorBuilder: (_, _) => SizedBox(width: 6),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final sel = cat == selected;
          return GestureDetector(
            onTap: () => onSelected(cat),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? PosColors.slate : PosColors.surface,
                borderRadius: BorderRadius.circular(PosRadii.pill),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: sel ? Colors.white : PosColors.muted,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({
    required this.items,
    required this.cart,
    required this.onTap,
    required this.onDecrement,
  });

  final List<MenuItem> items;
  final Map<String, int> cart;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onDecrement;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No items in this category',
          style: TextStyle(color: PosColors.muted),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisExtent: 90,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _MenuTile(
        item: items[i],
        qty: cart[items[i].id] ?? 0,
        onTap: () => onTap(items[i].id),
        onDecrement: () => onDecrement(items[i].id),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.qty,
    required this.onTap,
    required this.onDecrement,
  });

  final MenuItem item;
  final int qty;
  final VoidCallback onTap;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '৳', decimalDigits: 0);
    final inCart = qty > 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: inCart ? PosColors.slate : PosColors.surface,
          borderRadius: BorderRadius.circular(PosRadii.md),
          border: Border.all(color: inCart ? PosColors.slate : PosColors.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: inCart ? 0.1 : 0.04),
              blurRadius: inCart ? 10 : 6,
              offset: Offset(0, inCart ? 4 : 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: inCart ? Colors.white : PosColors.slate,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    currency.format(item.price),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: inCart
                          ? Colors.white.withValues(alpha: 0.8)
                          : PosColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (inCart)
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: onDecrement,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.remove_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(width: 4),
                    Container(
                      constraints: BoxConstraints(minWidth: 20),
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$qty',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.cart,
    required this.menuItems,
    required this.total,
    required this.totalQty,
    required this.currency,
    required this.showNote,
    required this.noteCtrl,
    required this.onToggleNote,
    required this.onSubmit,
  });

  final Map<String, int> cart;
  final List<MenuItem> menuItems;
  final double total;
  final int totalQty;
  final NumberFormat currency;
  final bool showNote;
  final TextEditingController noteCtrl;
  final VoidCallback onToggleNote;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final hasItems = cart.isNotEmpty;
    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: PosColors.surface,
        border: Border(top: BorderSide(color: PosColors.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          10,
          14,
          MediaQuery.of(context).padding.bottom + 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasItems) ...[
              for (final entry in cart.entries)
                Builder(
                  builder: (context) {
                    final item = menuItems.firstWhere(
                      (m) => m.id == entry.key,
                      orElse: () => menuItems.first,
                    );
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: PosColors.slate,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                '${entry.value}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            currency.format(item.price * entry.value),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              Divider(height: 12, color: PosColors.line),
            ],
            if (showNote)
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: noteCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Order note (e.g. no onion, extra spicy)',
                    hintStyle: TextStyle(fontSize: 12),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PosRadii.md),
                      borderSide: BorderSide(color: PosColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(PosRadii.md),
                      borderSide: BorderSide(color: PosColors.line),
                    ),
                  ),
                  autofocus: true,
                ),
              ),
            Row(
              children: [
                if (hasItems) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalQty item${totalQty == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: PosColors.muted,
                        ),
                      ),
                      Text(
                        currency.format(total),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: PosColors.slate,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 10),
                  _IconBtn(
                    icon: showNote ? Icons.notes_rounded : Icons.notes_outlined,
                    color: showNote ? PosColors.slate : PosColors.muted,
                    onTap: onToggleNote,
                    tooltip: 'Add note',
                  ),
                  SizedBox(width: 8),
                ] else
                  Expanded(
                    child: Text(
                      'Tap items to add to order',
                      style: TextStyle(
                        color: PosColors.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                Expanded(
                  child: GestureDetector(
                    onTap: onSubmit,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: onSubmit != null
                            ? PosColors.slate
                            : PosColors.line,
                        borderRadius: BorderRadius.circular(PosRadii.md + 2),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.print_rounded,
                            size: 18,
                            color: onSubmit != null
                                ? Colors.white
                                : PosColors.muted,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Create & Print',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: onSubmit != null
                                  ? Colors.white
                                  : PosColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: 36,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
