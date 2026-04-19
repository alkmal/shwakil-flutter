import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

class DeviceUnlockScreen extends StatefulWidget {
  const DeviceUnlockScreen({super.key});

  @override
  State<DeviceUnlockScreen> createState() => _DeviceUnlockScreenState();
}

class _DeviceUnlockScreenState extends State<DeviceUnlockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final AuthService _auth = AuthService();

  String _username = '';
  bool _hasPin = false;
  bool _biometricEnabled = false;
  bool _isLoading = true;
  bool _isUnlocking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final trustedUsername = await LocalSecurityService.trustedUsername() ?? '';
    final hasPin = await LocalSecurityService.hasPin();
    final canUseBiometrics = await LocalSecurityService.canUseBiometrics();
    final biometricEnabled = await LocalSecurityService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _username = trustedUsername;
        _hasPin = hasPin;
        _biometricEnabled = biometricEnabled && canUseBiometrics;
        _isLoading = false;
      });
    }
  }

  Future<void> _unlockPin() async {
    final l = context.loc;
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
      await LocalSecurityService.clearRelockRequirement();
      await LocalSecurityService.skipNextUnlock();
      await RealtimeNotificationService.start();
      if (!mounted) {
        return;
      }
      Navigator.pushNamedAndRemoveUntil(context, '/app-shell', (route) => false);
      return;
    }

    if (mounted) {
      setState(() => _isUnlocking = false);
      await AppAlertService.showError(
        context,
        title: l.tr('screens_device_unlock_screen.003'),
        message: l.tr('screens_device_unlock_screen.004'),
      );
    }
  }

  Future<void> _unlockBiometric() async {
    setState(() => _isUnlocking = true);
    final authenticated =
        await LocalSecurityService.authenticateWithBiometrics();
    if (authenticated) {
      await LocalSecurityService.clearRelockRequirement();
      await LocalSecurityService.skipNextUnlock();
      await RealtimeNotificationService.start();
      if (!mounted) {
        return;
      }
      Navigator.pushNamedAndRemoveUntil(context, '/app-shell', (route) => false);
      return;
    }

    if (mounted) {
      setState(() => _isUnlocking = false);
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

  String _subtitle(AppLocalizer l) {
    if (_username.isEmpty) {
      return _hasPin
          ? l.tr('screens_device_unlock_screen.007')
          : l.tr('screens_device_unlock_screen.008');
    }
    return _hasPin
        ? l.tr(
            'screens_device_unlock_screen.009',
            params: {'username': _username},
          )
        : l.tr(
            'screens_device_unlock_screen.010',
            params: {'username': _username},
          );
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
            l.tr('screens_device_unlock_screen.006'),
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
              obscureText: true,
              maxLength: 4,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: AppTheme.h1.copyWith(
                letterSpacing: 20,
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
              onPressed: _unlockPin,
              isLoading: _isUnlocking,
            ),
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
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: CircleAvatar(
            radius: 200,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.05),
          ),
        ),
        Positioned(
          bottom: -50,
          left: -50,
          child: CircleAvatar(
            radius: 150,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.05),
          ),
        ),
      ],
    );
  }
}
