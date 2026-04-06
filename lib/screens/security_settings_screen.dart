import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _hasPin = false;
  bool _biometricEnabled = false;
  bool _canUseBiometrics = false;
  bool _isTrustedDevice = false;
  String _trustedUsername = '';
  String _lastAuthMethod = '';
  int _relockTimeout = 30;
  List<Map<String, dynamic>> _devices = const [];
  String? _busyDeviceId;
  bool _isUpdatingBiometric = false;

  @override
  void initState() {
    super.initState();
    _load();
    LocalSecurityService.securityStateListenable.addListener(_onChanged);
  }

  @override
  void dispose() {
    LocalSecurityService.securityStateListenable.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load();

  Future<void> _load() async {
    final hasPin = await LocalSecurityService.hasPin();
    final canUseBiometrics = await LocalSecurityService.canUseBiometrics();
    final biometricEnabled =
        await LocalSecurityService.isBiometricEnabled() && canUseBiometrics;
    final isTrustedDevice = await LocalSecurityService.isTrustedDevice();
    final trustedUsername = await LocalSecurityService.trustedUsername() ?? '';
    final lastAuthMethod =
        await LocalSecurityService.lastLocalAuthMethod() ?? '';
    final relockTimeout = await LocalSecurityService.relockTimeoutInSeconds();

    List<Map<String, dynamic>> devices = const [];
    try {
      final payload = await _apiService.getMyDevices();
      devices = List<Map<String, dynamic>>.from(
        (payload['devices'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
    } catch (_) {}

    if (!mounted) {
      return;
    }
    setState(() {
      _hasPin = hasPin;
      _biometricEnabled = biometricEnabled;
      _canUseBiometrics = canUseBiometrics;
      _isTrustedDevice = isTrustedDevice;
      _trustedUsername = trustedUsername;
      _lastAuthMethod = lastAuthMethod;
      _relockTimeout = relockTimeout;
      _devices = devices;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('أمان الجهاز')),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSecurityHero(),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 920;
                  if (isCompact) {
                    return Column(
                      children: [
                        _buildStatusOverview(),
                        const SizedBox(height: 16),
                        _buildPinSection(),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _buildStatusOverview()),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: _buildPinSection()),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildTimeoutSection(),
              const SizedBox(height: 16),
              _buildDevicesSection(),
              if (_isTrustedDevice) ...[
                const SizedBox(height: 20),
                ShwakelButton(
                  label: 'إلغاء توثيق هذا الجهاز',
                  icon: Icons.phonelink_erase_rounded,
                  isSecondary: true,
                  onPressed: _clearTrusted,
                  width: double.infinity,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityHero() {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: AppTheme.darkGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إعدادات الحماية',
                      style: AppTheme.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدر PIN والبصمة والأجهزة الموثقة وإعادة القفل من مكان واحد.',
                      style: AppTheme.bodyAction.copyWith(
                        color: Colors.white70,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroChip(
                icon: Icons.verified_user_rounded,
                label: _isTrustedDevice ? 'الجهاز موثق' : 'الجهاز غير موثق',
              ),
              _heroChip(
                icon: Icons.pin_rounded,
                label: _hasPin ? 'PIN مفعل' : 'PIN غير مفعل',
              ),
              _heroChip(
                icon: Icons.fingerprint_rounded,
                label: _biometricEnabled ? 'البصمة مفعلة' : 'البصمة غير مفعلة',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusOverview() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ملخص الأمان', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'حالة طرق التحقق والجهاز الموثق ووسيلة الدخول الأخيرة.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 18),
          _statusLine(
            'توثيق الجهاز',
            _isTrustedDevice ? 'موثوق' : 'غير موثوق',
            _isTrustedDevice ? AppTheme.success : AppTheme.error,
          ),
          _statusLine(
            'رمز PIN المحلي',
            _hasPin ? 'مفعل' : 'غير مفعل',
            _hasPin ? AppTheme.success : AppTheme.warning,
          ),
          _statusLine(
            'البصمة',
            _biometricEnabled ? 'مفعلة' : 'غير مفعلة',
            _biometricEnabled ? AppTheme.success : AppTheme.textTertiary,
          ),
          _statusLine(
            'آخر وسيلة تحقق',
            _lastAuthMethod == 'biometric'
                ? 'البصمة'
                : (_lastAuthMethod == 'pin' ? 'رمز PIN' : 'OTP'),
            AppTheme.primary,
          ),
          if (_trustedUsername.isNotEmpty)
            _statusLine(
              'الحساب الموثق على الجهاز',
              '@$_trustedUsername',
              AppTheme.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildPinSection() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('وسائل القفل المحلي', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'فعّل رمز PIN أو البصمة أو كليهما لتسريع فتح التطبيق وتأكيد العمليات.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasPin ? 'تغيير رمز PIN' : 'إعداد رمز PIN',
                        style: AppTheme.bodyBold,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'لفتح التطبيق وتأكيد العمليات الحساسة.',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ShwakelButton(
                  label: _hasPin ? 'تحديث' : 'إعداد',
                  icon: Icons.pin_rounded,
                  onPressed: _createOrChangePin,
                  isSecondary: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.secondary.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تفعيل البصمة', style: AppTheme.bodyBold),
                      const SizedBox(height: 4),
                      Text(
                        _canUseBiometrics
                            ? _hasPin
                                  ? 'يمكنك استخدام البصمة أو PIN، وتعمل البصمة حتى بدون PIN.'
                                  : 'يمكنك تفعيل البصمة مباشرة حتى لو لم تقم بإعداد PIN.'
                            : 'هذا الجهاز لا يدعم البصمة أو لم يتم إعدادها على النظام.',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: _biometricEnabled,
                  onChanged: (_canUseBiometrics && !_isUpdatingBiometric)
                      ? _toggleBiometric
                      : null,
                  activeThumbColor: AppTheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeoutSection() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('إعادة القفل التلقائي', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'حدد متى يطلب التطبيق التحقق المحلي مجددًا بعد تركه في الخلفية.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<int>(
            initialValue: _relockTimeout,
            items: LocalSecurityService.relockTimeoutOptionsInSeconds
                .map(
                  (seconds) => DropdownMenuItem(
                    value: seconds,
                    child: Text(_timeoutLabel(seconds)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                _updateTimeout(value);
              }
            },
            decoration: const InputDecoration(
              labelText: 'إعادة قفل التطبيق بعد',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesSection() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الأجهزة النشطة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'يمكنك إزالة أي جهاز لطلب توثيق جديد عليه عند تسجيل الدخول لاحقًا.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 18),
          if (_devices.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.devices_other_rounded,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'لا توجد أجهزة نشطة ظاهرة حاليًا.',
                      style: AppTheme.bodyText,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._devices.map(_buildDeviceTile),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(Map<String, dynamic> device) {
    final isActive = device['isActiveDevice'] == true;
    final isBusy = _busyDeviceId == device['id']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? AppTheme.primary.withValues(alpha: 0.25)
                : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor:
                  (isActive ? AppTheme.primary : AppTheme.secondary).withValues(
                    alpha: 0.12,
                  ),
              child: Icon(
                Icons.smartphone_rounded,
                color: isActive ? AppTheme.primary : AppTheme.secondary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device['deviceName']?.toString() ?? 'جهاز غير معروف',
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'معرف الجهاز: ${device['deviceId'] ?? '-'}',
                    style: AppTheme.caption,
                  ),
                  if (isActive) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'الجهاز الحالي',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'حذف الجهاز',
              onPressed: isBusy ? null : () => _releaseDevice(device),
              icon: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.error,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusLine(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.bodyAction)),
          const SizedBox(width: 12),
          Text(value, style: AppTheme.bodyBold.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _heroChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _timeoutLabel(int seconds) {
    if (seconds == 0) {
      return 'فورًا';
    }
    if (seconds < 60) {
      return '$seconds ثانية';
    }
    return '${seconds ~/ 60} دقيقة';
  }

  Future<void> _createOrChangePin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => _StyledPinDialog(isEdit: _hasPin),
    );
    if (pin != null && pin.length == 4) {
      await LocalSecurityService.savePin(pin);
      _load();
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    setState(() => _isUpdatingBiometric = true);
    try {
      if (value && !await LocalSecurityService.authenticateWithBiometrics()) {
        return;
      }
      await LocalSecurityService.setBiometricEnabled(value);
      await _load();
    } finally {
      if (mounted) {
        setState(() => _isUpdatingBiometric = false);
      }
    }
  }

  Future<void> _updateTimeout(int seconds) async {
    await LocalSecurityService.setRelockTimeoutInSeconds(seconds);
    _load();
  }

  Future<void> _releaseDevice(Map<String, dynamic> device) async {
    final id = device['id']?.toString();
    if (id == null || id.isEmpty) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الجهاز'),
        content: const Text('هل تريد إزالة هذا الجهاز من الأجهزة النشطة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _busyDeviceId = id);
    try {
      final response = await _apiService.releaseMyDevice(deviceRecordId: id);
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = List<Map<String, dynamic>>.from(
          (response['devices'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
      });
      AppAlertService.showSuccess(
        context,
        title: 'تم الحذف',
        message:
            response['message']?.toString() ?? 'تم حذف الجهاز من الحساب بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر الحذف',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyDeviceId = null);
      }
    }
  }

  Future<void> _clearTrusted() async {
    await _authService.logout();
    await LocalSecurityService.clearTrustedState();
    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, '/login');
  }
}

class _StyledPinDialog extends StatelessWidget {
  _StyledPinDialog({required this.isEdit});

  final bool isEdit;
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? 'تحديث رمز PIN' : 'رمز PIN جديد'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pinController,
            maxLength: 4,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'أدخل 4 أرقام'),
          ),
          TextField(
            controller: _confirmController,
            maxLength: 4,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'تأكيد الرمز'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ShwakelButton(
          label: 'حفظ',
          onPressed: () {
            if (_pinController.text.length != 4 ||
                _pinController.text != _confirmController.text) {
              AppAlertService.showError(
                context,
                title: 'الرمز غير صحيح',
                message: 'تأكد من إدخال 4 أرقام متطابقة.',
              );
              return;
            }
            Navigator.pop(context, _pinController.text);
          },
        ),
      ],
    );
  }
}
