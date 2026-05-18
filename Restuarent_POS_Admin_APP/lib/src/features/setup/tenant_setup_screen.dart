import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';

class TenantSetupScreen extends StatefulWidget {
  const TenantSetupScreen({required this.onProvisioned, super.key});

  final VoidCallback onProvisioned;

  @override
  State<TenantSetupScreen> createState() => _TenantSetupScreenState();
}

class _TenantSetupScreenState extends State<TenantSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _restaurantCtrl = TextEditingController();
  final _outletCtrl = TextEditingController(text: 'Main Outlet');
  bool _busy = false;

  @override
  void dispose() {
    _restaurantCtrl.dispose();
    _outletCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosColors.background,
      body: Stack(
        children: [
          _SetupWash(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo / Icon
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: PosGradients.brand,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: PosShadows.glow,
                        ),
                        child: Icon(
                          Icons.restaurant_rounded,
                          size: 36,
                          color: PosColors.slate,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Set Up Your Restaurant',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Everything is stored on this device.\nNo internet required.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: PosColors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: 32),
                      // Form card
                      Container(
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: PosColors.background,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: PosColors.line),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel('Restaurant Name'),
                              SizedBox(height: 6),
                              TextFormField(
                                controller: _restaurantCtrl,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofocus: true,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Moon Bistro',
                                  prefixIcon: Icon(Icons.storefront_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Please enter your restaurant name'
                                    : null,
                              ),
                              SizedBox(height: 16),
                              _FieldLabel('Outlet / Branch Name'),
                              SizedBox(height: 6),
                              TextFormField(
                                controller: _outletCtrl,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Dhanmondi Branch',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Please enter an outlet name'
                                    : null,
                              ),
                              SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: PrimaryButton(
                                  label: 'Get Started',
                                  icon: Icons.arrow_forward_rounded,
                                  busy: _busy,
                                  onPressed: _busy ? null : _submit,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      // Reassurance footer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Chip(Icons.storage_rounded, 'Stored on device'),
                          SizedBox(width: 10),
                          _Chip(Icons.wifi_off_rounded, 'Works offline'),
                          SizedBox(width: 10),
                          _Chip(Icons.print_rounded, 'Print ready'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final app = AppScope.of(context);
      await app.saveLocalSetup(
        restaurantName: _restaurantCtrl.text,
        outletName: _outletCtrl.text,
      );
      if (!mounted) return;
      widget.onProvisioned();
    } catch (error) {
      if (!mounted) return;
      final appError = AppScope.of(context).lastError;
      final message = appError?.trim().isNotEmpty == true
          ? appError!
          : 'Could not connect to the local server. Start the backend and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 13,
        color: PosColors.slate,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: PosColors.line.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: PosColors.muted),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: PosColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

// Background decorative wash
class _SetupWash extends StatelessWidget {
  const _SetupWash();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    PosColors.primarySoft,
                    PosColors.accentSoft.withValues(alpha: 0.45),
                    PosColors.background,
                  ],
                ),
              ),
              child: SizedBox.expand(),
            ),
          ),
          Positioned(
            top: -100,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    PosColors.primaryGlow.withValues(alpha: 0.18),
                    PosColors.primaryGlow.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -90,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    PosColors.accent.withValues(alpha: 0.12),
                    PosColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
