import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'app_scope.dart';
import 'core/localization/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/menu/menu_management_screen.dart';
import 'features/orders/orders_screen.dart';
import 'features/payments/bkash_payment_gate_screen.dart';
import 'features/setup/tenant_setup_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/mode_intro_screen.dart';
import 'features/splash/splash_screen.dart';

class LocalPosApp extends StatefulWidget {
  const LocalPosApp({super.key});

  @override
  State<LocalPosApp> createState() => _LocalPosAppState();
}

class _LocalPosAppState extends State<LocalPosApp> with WidgetsBindingObserver {
  late final PosAppController _controller;
  late final Future<void> _bootFuture;
  bool _showSplash = true;
  bool _showIntro = false;
  int _initialShellIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PosAppController();
    _bootFuture = _controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _controller.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final uiScale = _controller.uiScale;
          final text = _controller.strings;
          final tone = _resolveTone(_controller.themePreference);
          PosColors.setTone(tone);
          return MaterialApp(
            title: text.appTitle,
            debugShowCheckedModeBanner: false,
            locale: _controller.language.locale,
            supportedLocales: AppLanguage.values
                .map((language) => language.locale)
                .toList(growable: false),
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light(uiScale: uiScale),
            themeMode: ThemeMode.light,
            builder: (context, child) {
              return _WindowScale(
                scale: uiScale,
                child: child ?? SizedBox.shrink(),
              );
            },
            home: AnimatedSwitcher(
              duration: Duration(milliseconds: 320),
              child: _home(),
            ),
          );
        },
      ),
    );
  }

  PosThemeTone _resolveTone(AppThemePreference _) {
    return PosThemeTone.light;
  }

  Widget _home() {
    if (_showSplash) {
      return SplashScreen(
        bootFuture: _bootFuture,
        onFinished: () {
          setState(() {
            _showSplash = false;
            _showIntro = !_controller.hasSeenIntro;
            _initialShellIndex = _showIntro ? 4 : 0;
          });
        },
      );
    }
    if (!_controller.isLoggedIn) {
      return LoginScreen(
        onSignedIn: () {
          setState(() {
            _showIntro = !_controller.hasSeenIntro;
            _initialShellIndex = _showIntro ? 4 : 0;
          });
        },
      );
    }
    if (_controller.requiresBkashPayment) {
      return BkashPaymentGateScreen(
        onVerified: () {
          setState(() {
            _showIntro = false;
            _initialShellIndex = 0;
          });
        },
      );
    }
    if (_showIntro) {
      return ModeIntroScreen(
        onContinue: () async {
          await _controller.completeIntro();
          if (!mounted) return;
          setState(() {
            _showIntro = false;
            _initialShellIndex = 4;
          });
        },
      );
    }
    if (!_controller.isTenantReady) {
      return TenantSetupScreen(
        onProvisioned: () {
          setState(() {
            _initialShellIndex = 0;
          });
        },
      );
    }
    return MainShell(initialIndex: _initialShellIndex);
  }
}

class _WindowScale extends StatelessWidget {
  const _WindowScale({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeScale = scale.clamp(0.78, 1.08).toDouble();
    if ((safeScale - 1).abs() < 0.001) return child;

    final size = mediaQuery.size;
    final layoutSize = Size(size.width / safeScale, size.height / safeScale);

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minWidth: layoutSize.width,
        maxWidth: layoutSize.width,
        minHeight: layoutSize.height,
        maxHeight: layoutSize.height,
        child: Transform.scale(
          scale: safeScale,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: layoutSize.width,
            height: layoutSize.height,
            child: MediaQuery(
              data: mediaQuery.copyWith(size: layoutSize),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({required this.initialIndex, super.key});

  final int initialIndex;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _selectedIndex = widget.initialIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppScope.of(context).strings;
    final destinations = _destinations(text);
    final pages = [
      DashboardScreen(onNavigate: _setIndex),
      OrdersScreen(),
      MenuManagementScreen(),
      InventoryScreen(),
      SettingsScreen(),
    ];
    final safeIndex = _selectedIndex.clamp(0, pages.length - 1);
    if (safeIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedIndex = safeIndex);
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 760;
        if (!useRail) {
          return Scaffold(
            backgroundColor: PosColors.background,
            body: IndexedStack(index: safeIndex, children: pages),
            bottomNavigationBar: _FloatingBottomNav(
              destinations: destinations,
              selectedIndex: safeIndex,
              onChanged: _setIndex,
            ),
          );
        }

        final extended = constraints.maxWidth >= 1050;
        return Scaffold(
          body: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: PosColors.surface,
                  border: Border(right: BorderSide(color: PosColors.line)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 22,
                      offset: Offset(2, 0),
                    ),
                  ],
                ),
                child: NavigationRail(
                  selectedIndex: safeIndex,
                  onDestinationSelected: _setIndex,
                  extended: extended,
                  minExtendedWidth: 232,
                  groupAlignment: -0.86,
                  leading: Padding(
                    padding: EdgeInsets.fromLTRB(14, 22, 14, 28),
                    child: _RailLogo(extended: extended),
                  ),
                  trailing: Padding(
                    padding: EdgeInsets.fromLTRB(12, 18, 12, 22),
                    child: _RailFooter(extended: extended),
                  ),
                  destinations: destinations
                      .map((destination) {
                        return NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              Expanded(
                child: IndexedStack(index: safeIndex, children: pages),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setIndex(int index) {
    final maxIndex = _destinations(AppScope.of(context).strings).length - 1;
    setState(() => _selectedIndex = index.clamp(0, maxIndex));
  }

  List<_Destination> _destinations(AppStrings text) {
    return [
      _Destination('Home', Icons.home_outlined, Icons.home_rounded),
      _Destination(
        text.orders,
        Icons.receipt_long_outlined,
        Icons.receipt_long,
      ),
      _Destination(
        text.menu,
        Icons.restaurant_menu_outlined,
        Icons.restaurant_menu,
      ),
      _Destination('Stock', Icons.grid_on_outlined, Icons.grid_on_rounded),
      _Destination('More', Icons.more_horiz_rounded, Icons.more_horiz_rounded),
    ];
  }
}

class _Destination {
  _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _RailLogo extends StatelessWidget {
  const _RailLogo({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final text = AppScope.of(context).strings;
    final mark = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: PosGradients.brand,
        borderRadius: BorderRadius.circular(PosRadii.md),
        boxShadow: [
          BoxShadow(
            color: PosColors.primary.withValues(alpha: 0.36),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.point_of_sale_rounded,
        color: PosColors.slate,
        size: 24,
      ),
    );
    if (!extended) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.appTitle,
              style: TextStyle(
                color: PosColors.slate,
                fontWeight: FontWeight.w900,
                fontSize: 16.5,
                letterSpacing: 0,
              ),
            ),
            SizedBox(height: 2),
            Text(
              text.cloudSuite,
              style: TextStyle(
                color: PosColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FloatingBottomNav extends StatelessWidget {
  const _FloatingBottomNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final barHeight = 72.0;

    return SafeArea(
      top: false,
      minimum: EdgeInsets.zero,
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          color: Color(0xFFF4EFE4),
          border: Border(top: BorderSide(color: Color(0xFF14110E), width: 1)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 5, 8, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _BottomNavItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = PosColors.primaryDark;
    final icon = selected ? destination.selectedIcon : destination.icon;

    return Tooltip(
      message: destination.label,
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(19),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: selected ? 52 : 52,
                  height: selected ? 56 : 52,
                  padding: EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? PosColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: selected
                        ? Border.all(color: Color(0xFF14110E), width: 1)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: foreground, size: 18),
                      SizedBox(height: 3),
                      Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailFooter extends StatelessWidget {
  const _RailFooter({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    final text = AppScope.of(context).strings;
    if (!extended) {
      return Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: PosColors.primarySoft,
          borderRadius: BorderRadius.circular(PosRadii.sm),
          border: Border.all(color: PosColors.line),
        ),
        child: Icon(
          Icons.verified_user_outlined,
          color: PosColors.primary,
          size: 20,
        ),
      );
    }
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PosColors.primarySoft,
            PosColors.primarySoft.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(PosRadii.md),
        border: Border.all(color: PosColors.line),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: PosColors.primary,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text.secureTenant,
                  style: TextStyle(
                    color: PosColors.primaryDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  text.tokenVerified,
                  style: TextStyle(
                    color: PosColors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
