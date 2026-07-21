import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

class DeviceUnlockScreen extends StatefulWidget {
  const DeviceUnlockScreen({super.key, this.returnRoute});

  final String? returnRoute;

  @override
  State<DeviceUnlockScreen> createState() => _DeviceUnlockScreenState();
}

class _DeviceUnlockScreenState extends State<DeviceUnlockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  final AuthService _auth = AuthService();

  String _username = '';
  bool _hasPin = false;
  bool _biometricEnabled = false;
  bool _isLoading = true;
  bool _isUnlocking = false;
  bool _didAutoPromptBiometric = false;
  int _pinRetryAfterSeconds = 0;
  String _returnRoute = '/home';
  bool _readRouteArguments = false;

  @override
  void initState() {
    super.initState();
    final requested = widget.returnRoute?.trim() ?? '';
    if (requested.isNotEmpty) {
      _returnRoute = requested;
    }
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readRouteArguments) return;
    _readRouteArguments = true;
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is Map) {
      final requested = arguments['returnRoute']?.toString().trim() ?? '';
      if (requested.isNotEmpty &&
          requested != '/unlock' &&
          requested != '/login' &&
          requested != '/login-offline') {
        _returnRoute = requested;
      }
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final trustedUsername = await LocalSecurityService.trustedUsername() ?? '';
    final hasPin = await LocalSecurityService.hasPin();
    final canUseBiometrics = await LocalSecurityService.canUseBiometrics();
    final biometricEnabled = await LocalSecurityService.isBiometricEnabled();
    final pinRetryAfterSeconds =
        await LocalSecurityService.pinRetryAfterSeconds();
    if (mounted) {
      setState(() {
        _username = trustedUsername;
        _hasPin = hasPin;
        _biometricEnabled = biometricEnabled && canUseBiometrics;
        _pinRetryAfterSeconds = pinRetryAfterSeconds;
        _isLoading = false;
      });
      _maybeAutoPromptBiometric();
    }
  }

  void _maybeAutoPromptBiometric() {
    if (_didAutoPromptBiometric ||
        _isLoading ||
        _isUnlocking ||
        !_biometricEnabled) {
      return;
    }
    _didAutoPromptBiometric = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isUnlocking) {
        return;
      }
      _unlockBiometric();
    });
  }

  Future<void> _unlockPin() async {
    final l = context.loc;
    if (_pinRetryAfterSeconds > 0) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_device_unlock_screen.003'),
        message: l.tr(
          'screens_device_unlock_screen.014',
          params: {'seconds': '$_pinRetryAfterSeconds'},
        ),
      );
      return;
    }

    if (_pinController.text.trim().length != 4) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_device_unlock_screen.001'),
        message: l.tr('screens_device_unlock_screen.002'),
      );
      return;
    }

    setState(() => _isUnlocking = true);
    final isValid = await LocalSecurityService.verifyPin(
      _pinController.text.trim(),
    );
    if (isValid) {
      _pinController.clear();
      await _completeUnlock();
      return;
    }

    final retryAfterSeconds = await LocalSecurityService.pinRetryAfterSeconds();
    if (!mounted) {
      return;
    }

    setState(() => _isUnlocking = false);
    _pinController.clear();
    setState(() => _pinRetryAfterSeconds = retryAfterSeconds);
    await AppAlertService.showError(
      context,
      title: l.tr('screens_device_unlock_screen.003'),
      message: retryAfterSeconds > 0
          ? l.tr(
              'screens_device_unlock_screen.014',
              params: {'seconds': '$retryAfterSeconds'},
            )
          : l.tr('screens_device_unlock_screen.004'),
    );
  }

  Future<void> _unlockBiometric() async {
    setState(() => _isUnlocking = true);
    final authenticated =
        await LocalSecurityService.authenticateWithBiometrics();
    if (authenticated) {
      await _completeUnlock();
      return;
    }

    if (mounted) {
      setState(() => _isUnlocking = false);
      if (_hasPin) {
        _pinFocusNode.requestFocus();
      }
    }
  }

  Future<void> _loginAnotherAccount() async {
    await _auth.logout();
    await LocalSecurityService.clearTrustedState();
    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _completeUnlock() async {
    final l = context.loc;
    await LocalSecurityService.markLocalUnlockCompleted();
    try {
      final refreshed = await _auth.tryRefreshCurrentUser();
      final user = await _auth.currentUser();
      if (!AuthService.hasPermissionSnapshot(user)) {
        final restored = await _auth.refreshTrustedDeviceSession();
        final restoredUser = restored ? await _auth.currentUser() : user;
        if (restored && AuthService.hasPermissionSnapshot(restoredUser)) {
          await _finishLocalUnlock();
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() => _isUnlocking = false);
        await AppAlertService.showError(
          context,
          title: l.tr('screens_device_unlock_screen.015'),
          message: refreshed
              ? l.tr('screens_device_unlock_screen.016')
              : l.tr('screens_device_unlock_screen.017'),
        );
        return;
      }
    } catch (error) {
      if (error is AuthRequestException && error.deviceSessionOtpRequired) {
        final restored = await _auth.refreshTrustedDeviceSession();
        if (restored) {
          await _finishLocalUnlock();
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() => _isUnlocking = false);
        return;
      }
      if (ErrorMessageService.requiresFreshLogin(error)) {
        final restored = await _auth.refreshTrustedDeviceSession();
        if (restored) {
          await RealtimeNotificationService.start();
          await LocalSecurityService.clearSecuritySetupRequirement();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(
            context,
            _returnRoute,
            (route) => false,
          );
          return;
        }
        final cachedUser = await _auth.currentUser();
        final hasSavedSession = await _auth.isLoggedIn();
        if (cachedUser != null && hasSavedSession) {
          await RealtimeNotificationService.start();
          await LocalSecurityService.clearSecuritySetupRequirement();
          if (!mounted) return;
          Navigator.pushNamedAndRemoveUntil(
            context,
            _returnRoute,
            (route) => false,
          );
          return;
        }
        if (!mounted) {
          return;
        }
        setState(() => _isUnlocking = false);
        await AppAlertService.showError(
          context,
          title: l.tr('screens_device_unlock_screen.015'),
          message: l.tr('screens_device_unlock_screen.017'),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() => _isUnlocking = false);
      await AppAlertService.showError(
        context,
        title: l.tr('screens_device_unlock_screen.015'),
        message: l.tr('screens_device_unlock_screen.017'),
      );
      return;
    }
    await _finishLocalUnlock();
  }

  Future<void> _finishLocalUnlock() async {
    await RealtimeNotificationService.start();
    await LocalSecurityService.clearSecuritySetupRequirement();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, _returnRoute, (route) => false);
  }

  String _subtitle(AppLocalizer l) {
    if (_username.isEmpty) {
      return _hasPin ? 'أدخل الرمز للمتابعة.' : 'تابع بتأكيد هويتك.';
    }
    return 'أهلاً $_username';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          _buildDecor(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    children: [
                      const ShwakelLogo(size: 80, framed: true),
                      const SizedBox(height: 28),
                      _buildMainCard(),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _loginAnotherAccount,
                        child: Text(
                          l.tr('screens_device_unlock_screen.005'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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

  Widget _buildMainCard() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              color: AppTheme.primary,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l.text('فتح التطبيق', 'Open app'),
            style: AppTheme.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _subtitle(l),
            textAlign: TextAlign.center,
            style: AppTheme.bodyAction.copyWith(height: 1.6),
          ),
          if (_hasPin) ...[
            const SizedBox(height: 24),
            TextField(
              controller: _pinController,
              focusNode: _pinFocusNode,
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: AppTheme.h1.copyWith(
                letterSpacing: 0,
                color: AppTheme.primary,
              ),
              decoration: InputDecoration(
                hintText: '••••',
                counterText: '',
                labelText: l.tr('screens_device_unlock_screen.011'),
              ),
              onChanged: (value) {
                if (value.length == 4) {
                  _unlockPin();
                }
              },
            ),
            const SizedBox(height: 24),
            ShwakelButton(
              label: l.tr('screens_device_unlock_screen.012'),
              icon: Icons.lock_open_rounded,
              onPressed: _pinRetryAfterSeconds > 0 ? null : _unlockPin,
              isLoading: _isUnlocking,
            ),
            if (_pinRetryAfterSeconds > 0) ...[
              const SizedBox(height: 12),
              Text(
                l.tr(
                  'screens_device_unlock_screen.014',
                  params: {'seconds': '$_pinRetryAfterSeconds'},
                ),
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(color: AppTheme.error),
              ),
            ],
          ],
          if (_biometricEnabled) ...[
            SizedBox(height: _hasPin ? 14 : 24),
            ShwakelButton(
              label: l.tr('screens_device_unlock_screen.013'),
              icon: Icons.fingerprint_rounded,
              isSecondary: _hasPin,
              gradient: _hasPin ? null : AppTheme.primaryGradient,
              onPressed: _isUnlocking ? null : _unlockBiometric,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDecor() {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: AppTheme.pageBackgroundGradient),
      child: SizedBox.expand(),
    );
  }
}
