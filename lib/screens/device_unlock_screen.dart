import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/index.dart';
import '../widgets/shwakel_logo.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_button.dart';

class DeviceUnlockScreen extends StatefulWidget {
  const DeviceUnlockScreen({super.key});
  @override
  State<DeviceUnlockScreen> createState() => _DeviceUnlockScreenState();
}

class _DeviceUnlockScreenState extends State<DeviceUnlockScreen> {
  final TextEditingController _pinC = TextEditingController();
  final AuthService _auth = AuthService();
  String _user = '';
  bool _bio = false, _isLoading = true, _isUnlocking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { _pinC.dispose(); super.dispose(); }

  Future<void> _load() async {
    final u = await LocalSecurityService.trustedUsername() ?? '';
    final canBio = await LocalSecurityService.canUseBiometrics();
    final bioEn = await LocalSecurityService.isBiometricEnabled();
    if (mounted) setState(() { _user = u; _bio = bioEn && canBio; _isLoading = false; });
  }

  Future<void> _unlockPin() async {
    if (_pinC.text.length != 4) return;
    setState(() => _isUnlocking = true);
    final ok = await LocalSecurityService.verifyPin(_pinC.text.trim());
    if (ok) {
      await LocalSecurityService.clearRelockRequirement();
      await LocalSecurityService.skipNextUnlock();
      await RealtimeNotificationService.start();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    } else {
      if (mounted) { setState(() => _isUnlocking = false); AppAlertService.showError(context, message: 'رمز PIN غير صحيح.'); }
    }
  }

  Future<void> _unlockBio() async {
    setState(() => _isUnlocking = true);
    final ok = await LocalSecurityService.authenticateWithBiometrics();
    if (ok) {
      await LocalSecurityService.clearRelockRequirement();
      await LocalSecurityService.skipNextUnlock();
      await RealtimeNotificationService.start();
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    } else {
      if (mounted) setState(() => _isUnlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
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
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Column(
                    children: [
                      const ShwakelLogo(size: 80, framed: true),
                      const SizedBox(height: 32),
                      _buildMainCard(),
                      const SizedBox(height: 32),
                      TextButton(onPressed: () async { await _auth.logout(); await LocalSecurityService.clearTrustedState(); Navigator.pushReplacementNamed(context, '/login'); }, child: const Text('تسجيل الدخول بحساب آخر', style: TextStyle(fontWeight: FontWeight.bold))),
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
    return ShwakelCard(
      padding: const EdgeInsets.all(40),
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        children: [
          Text('فتح الجهاز الآمن', style: AppTheme.h2),
          const SizedBox(height: 12),
          Text('مرحباً $_user، الرجاء إدخال الرمز السري للمتابعة.', textAlign: TextAlign.center, style: AppTheme.caption),
          const SizedBox(height: 40),
          TextField(
            controller: _pinC,
            obscureText: true,
            maxLength: 4,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: AppTheme.h1.copyWith(letterSpacing: 20, color: AppTheme.primary),
            decoration: const InputDecoration(hintText: '••••', counterText: ''),
            onChanged: (v) { if (v.length == 4) _unlockPin(); },
          ),
          const SizedBox(height: 40),
          ShwakelButton(label: 'فتح القفل بـ PIN', icon: Icons.lock_open_rounded, onPressed: _unlockPin, isLoading: _isUnlocking),
          if (_bio) ...[
            const SizedBox(height: 16),
            ShwakelButton(label: 'فتح بواسطة البصمة', icon: Icons.fingerprint_rounded, isSecondary: true, onPressed: _unlockBio),
          ],
        ],
      ),
    );
  }

  Widget _buildDecor() => Stack(children: [
    Positioned(top: -100, right: -100, child: CircleAvatar(radius: 200, backgroundColor: AppTheme.primary.withOpacity(0.05))),
    Positioned(bottom: -50, left: -50, child: CircleAvatar(radius: 150, backgroundColor: AppTheme.accent.withOpacity(0.05))),
  ]);
}
