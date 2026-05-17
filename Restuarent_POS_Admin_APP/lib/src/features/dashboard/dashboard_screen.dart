import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/loading_view.dart';
import '../../core/widgets/pos_compact_ui.dart';
import '../../models/order_model.dart';
import '../../models/order_status.dart';
import '../../models/sales_report.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.onNavigate, super.key});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.initialized && app.lastError == null) {
      return LoadingView(message: 'Preparing cloud workspace...');
    }
    if (app.lastError != null && !app.initialized) {
      return Scaffold(
        backgroundColor: PosColors.background,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: ErrorView(message: app.lastError!),
          ),
        ),
      );
    }

    final metrics = app.metrics;
    final report7 = app.salesReportForDays(7);
    final allOrders = app.ordersFor();
    final pendingNow = allOrders
        .where((o) => o.status.adminStatus == OrderStatus.pending)
        .length;
    final acceptedNow = allOrders
        .where((o) => o.status.adminStatus == OrderStatus.accepted)
        .length;
    final avgTicket = metrics.todayOrders == 0
        ? 0.0
        : metrics.totalSales / metrics.todayOrders;
    final topItem = _topItem(allOrders);
    final salesCurrency = NumberFormat.currency(symbol: '৳', decimalDigits: 0);

    return Scaffold(
      backgroundColor: PosColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(12, 14, 12, 18),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompactHeader(
                      title: _greeting(),
                      subtitle:
                          'আজকের সারাংশ · ${DateFormat('EEE, MMM d').format(DateTime.now())}',
                      actions: [
                        CompactIconButton(
                          icon: Icons.notifications_none_rounded,
                          tooltip: 'Notifications',
                          onPressed: () {},
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    _SalesHeroCard(
                      report: report7,
                      todaySales: metrics.totalSales,
                      currency: salesCurrency,
                    ),
                    SizedBox(height: 16),
                    CompactSectionLabel(label: 'Today · আজকের'),
                    SizedBox(height: 8),
                    _MetricGrid(
                      orders: metrics.todayOrders,
                      open: pendingNow + acceptedNow,
                      avgTicket: avgTicket,
                      topItem: topItem,
                      currency: salesCurrency,
                      onOpenOrders: () => onNavigate(0),
                    ),
                    SizedBox(height: 16),
                    CompactSectionLabel(label: 'Quick actions'),
                    SizedBox(height: 8),
                    _QuickActions(
                      onNewOrder: () => onNavigate(0),
                      onOpenReports: () => onNavigate(4),
                      onSync: app.syncNow,
                      onOpenMenu: () => onNavigate(3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _topItem(List<OrderModel> orders) {
    final counts = <String, int>{};
    final now = DateTime.now();
    for (final order in orders) {
      final created = order.createdAt.toLocal();
      if (created.year != now.year ||
          created.month != now.month ||
          created.day != now.day ||
          order.status == OrderStatus.cancelled) {
        continue;
      }
      for (final item in order.items) {
        counts[item.name] = (counts[item.name] ?? 0) + item.qty;
      }
    }
    if (counts.isEmpty) return 'No item';
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        if (count != 0) return count;
        return a.key.compareTo(b.key);
      });
    return sorted.first.key;
  }
}

class _SalesHeroCard extends StatelessWidget {
  const _SalesHeroCard({
    required this.report,
    required this.todaySales,
    required this.currency,
  });

  final SalesReport report;
  final double todaySales;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final daily = report.dailyBreakdown;
    final values = daily.map<double>((day) => day.sales).toList();
    final yesterday = daily.length >= 2 ? daily[daily.length - 2].sales : 0.0;
    final deltaPct = yesterday <= 0
        ? 0.0
        : ((todaySales - yesterday) / yesterday) * 100;
    final positive = todaySales >= yesterday;

    return CompactSurface(
      color: PosColors.surfaceTinted,
      borderColor: PosColors.lineStrong,
      padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
      radius: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "TODAY'S SALES",
            style: TextStyle(
              color: PosColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'আজকের বিক্রি',
            style: TextStyle(
              color: PosColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              currency.format(todaySales),
              style: TextStyle(
                color: PosColors.slate,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                height: 0.95,
                letterSpacing: 0,
              ),
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (positive ? PosColors.success : PosColors.danger)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(PosRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      positive
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: positive ? PosColors.success : PosColors.danger,
                      size: 10,
                    ),
                    SizedBox(width: 3),
                    Text(
                      '${positive ? '+' : ''}${deltaPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: positive ? PosColors.success : PosColors.danger,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 7),
              Text(
                'vs yesterday',
                style: TextStyle(
                  color: PosColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 13),
          RepaintBoundary(
            child: SizedBox(
              height: 66,
              width: double.infinity,
              child: CustomPaint(painter: _SalesLinePainter(values: values)),
            ),
          ),
          SizedBox(height: 3),
          Row(
            children: [
              _AxisLabel('9 AM'),
              Spacer(),
              _AxisLabel('12 PM'),
              Spacer(),
              _AxisLabel('3 PM'),
              Spacer(),
              _AxisLabel('now'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.orders,
    required this.open,
    required this.avgTicket,
    required this.topItem,
    required this.currency,
    required this.onOpenOrders,
  });

  final int orders;
  final int open;
  final double avgTicket;
  final String topItem;
  final NumberFormat currency;
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricData('ORDERS', 'অর্ডার', orders.toString(), '+5 vs yest.'),
      _MetricData('OPEN', 'চলমান', open.toString(), 'needs action'),
      _MetricData('AVG TICKET', 'গড় বিল', currency.format(avgTicket), '+৳22'),
      _MetricData('TOP ITEM', 'টপ আইটেম', topItem, 'today'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 4 : 2;
        return GridView.builder(
          itemCount: metrics.length,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: columns == 2 ? 1.42 : 1.55,
          ),
          itemBuilder: (context, index) {
            final item = metrics[index];
            return CompactSurface(
              padding: EdgeInsets.all(12),
              radius: 9,
              onTap: index <= 1 ? onOpenOrders : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: PosColors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    item.bnLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: PosColors.muted,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Spacer(),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: index == 1 ? PosColors.primary : PosColors.slate,
                      fontSize: index == 3 ? 19 : 26,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    item.footer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: PosColors.success,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onNewOrder,
    required this.onOpenReports,
    required this.onSync,
    required this.onOpenMenu,
  });

  final VoidCallback onNewOrder;
  final VoidCallback onOpenReports;
  final Future<bool> Function() onSync;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(Icons.add_rounded, 'New', onNewOrder),
      _QuickAction(Icons.print_outlined, 'Print', onOpenReports),
      _QuickAction(Icons.sync_rounded, 'Sync', () async => onSync()),
      _QuickAction(Icons.inventory_2_outlined, 'Stock', onOpenMenu),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          Expanded(
            child: Tooltip(
              message: actions[i].label,
              child: Material(
                color: PosColors.surface,
                borderRadius: BorderRadius.circular(9),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: actions[i].onTap,
                  child: SizedBox(
                    height: 42,
                    child: Icon(
                      actions[i].icon,
                      color: i == 0 ? PosColors.primary : PosColors.slate,
                      size: 17,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (i < actions.length - 1) SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _SalesLinePainter extends CustomPainter {
  _SalesLinePainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final usableValues = values.length >= 2
        ? values
        : const [8000.0, 12000.0, 9000.0, 17000.0, 15000.0, 21000.0, 24000.0];
    final minValue = usableValues.reduce(math.min);
    final maxValue = usableValues.reduce(math.max);
    final range = (maxValue - minValue).abs() < 0.01
        ? 1.0
        : maxValue - minValue;
    final chartHeight = size.height - 10;
    final step = size.width / (usableValues.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < usableValues.length; i++) {
      final normalized = (usableValues[i] - minValue) / range;
      points.add(
        Offset(i * step, chartHeight - (normalized * (chartHeight - 7)) + 3),
      );
    }

    final gridPaint = Paint()
      ..color = PosColors.lineStrong
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 4),
      Offset(size.width, size.height - 4),
      gridPaint,
    );

    final fill = Path()..moveTo(points.first.dx, size.height - 4);
    for (final point in points) {
      fill.lineTo(point.dx, point.dy);
    }
    fill.lineTo(points.last.dx, size.height - 4);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()..color = PosColors.primary.withValues(alpha: 0.08),
    );

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final current = points[i];
      final midX = (prev.dx + current.dx) / 2;
      line.cubicTo(midX, prev.dy, midX, current.dy, current.dx, current.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = PosColors.primary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SalesLinePainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: PosColors.mutedSoft,
        fontSize: 8,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.bnLabel, this.value, this.footer);

  final String label;
  final String bnLabel;
  final String value;
  final String footer;
}

class _QuickAction {
  const _QuickAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
