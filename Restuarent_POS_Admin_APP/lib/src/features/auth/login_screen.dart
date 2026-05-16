import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onSignedIn, super.key});

  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final error = app.lastError;

    return Scaffold(
      backgroundColor: PosColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth >= 720 ? 40 : 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _BrandHeader(),
                        SizedBox(height: 26),
                        _LoginPanel(
                          busy: app.busy,
                          error: error == null ? null : _friendlyError(error),
                          onGooglePressed: app.busy ? null : _signInWithGoogle,
                        ),
                        SizedBox(height: 18),
                        _TrustStrip(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    final ok = await AppScope.of(context).signInWithGoogle();
    if (!ok || !mounted) return;
    widget.onSignedIn();
  }

  String _friendlyError(String error) {
    var message = error.replaceFirst('Exception: ', '').trim();
    if (message.contains('GoogleSignInExceptionCode.canceled')) {
      return 'Google sign-in was cancelled.';
    }
    if (message.contains('clientConfigurationError')) {
      return 'Google sign-in setup needs a valid OAuth client for this build.';
    }
    if (message.isEmpty) return 'Could not sign in with Google.';
    return message;
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PosColors.surface,
            borderRadius: BorderRadius.circular(PosRadii.lg),
            border: Border.all(color: PosColors.line),
            boxShadow: PosShadows.card,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PosRadii.md),
            child: Image.asset('assets/icons/Admin_res.png', fit: BoxFit.cover),
          ),
        ),
        SizedBox(height: 18),
        Text(
          'REs Admin',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: PosColors.slate,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Restaurant POS admin console',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: PosColors.muted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.busy,
    required this.error,
    required this.onGooglePressed,
  });

  final bool busy;
  final String? error;
  final VoidCallback? onGooglePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: PosColors.surface,
        borderRadius: BorderRadius.circular(PosRadii.lg),
        border: Border.all(color: PosColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sign in',
            style: TextStyle(
              color: PosColors.slate,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Use your Google account to open this admin app.',
            style: TextStyle(
              color: PosColors.muted,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (error != null) ...[
            SizedBox(height: 16),
            _ErrorBanner(message: error!),
          ],
          SizedBox(height: 22),
          _GoogleButton(busy: busy, onPressed: onGooglePressed),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = busy || onPressed == null;

    return Material(
      color: disabled ? PosColors.surfaceWarm : Colors.white,
      borderRadius: BorderRadius.circular(PosRadii.sm),
      child: InkWell(
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(PosRadii.sm),
        child: Container(
          height: 54,
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PosRadii.sm),
            border: Border.all(color: PosColors.lineStrong),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      PosColors.primaryDark,
                    ),
                  ),
                )
              else
                _GoogleMark(),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  busy ? 'Signing in...' : 'Continue with Google',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: PosColors.primaryDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Color(0xFFE0E0E0)),
      ),
      child: Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PosColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PosRadii.xs),
        border: Border.all(color: PosColors.danger.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: PosColors.danger, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: PosColors.danger,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _TrustPill(icon: Icons.verified_user_outlined, label: 'Firebase Auth'),
        _TrustPill(icon: Icons.lock_outline_rounded, label: 'Google secured'),
      ],
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: PosColors.surfaceWarm,
        borderRadius: BorderRadius.circular(PosRadii.pill),
        border: Border.all(color: PosColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: PosColors.muted),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: PosColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
