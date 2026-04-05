import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart';
import '../services/index.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_logo.dart';
import '../widgets/app_sidebar.dart';

class QuickTransferScreen extends StatefulWidget {
  const QuickTransferScreen({super.key});
  @override
  State<QuickTransferScreen> createState() => _QuickTransferScreenState();
}

class _QuickTransferScreenState extends State<QuickTransferScreen>
    with RouteAware {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();
  final MobileScannerController _camC = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _canTransfer = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _camC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final u = await _auth.currentUser();
      if (mounted)
        setState(() {
          _user = u;
          _canTransfer = u?['permissions']?['canTransfer'] == true;
          _isLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _payload() => jsonEncode({
    'type': 'shwakel_transfer',
    'userId': _user?['id']?.toString() ?? '',
    'username': _user?['username']?.toString() ?? '',
    'phone': _user?['whatsapp']?.toString() ?? '',
  });

  Future<void> _scan() async {
    await showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ShwakelCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('امسح رمز المستلم', style: AppTheme.h3),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: AppTheme.radiusMd,
                  child: SizedBox(
                    height: 320,
                    child: MobileScanner(
                      controller: _camC,
                      onDetect: (cap) {
                        final val = cap.barcodes.first.rawValue ?? '';
                        if (val.isNotEmpty) {
                          Navigator.pop(c, val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ShwakelButton(
                  label: 'إلغاء',
                  isSecondary: true,
                  onPressed: () => Navigator.pop(c),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((v) {
      if (v != null && v is String) _startTransfer(v);
    });
  }

  Future<void> _startTransfer(String raw) async {
    try {
      final p = Map<String, dynamic>.from(jsonDecode(raw));
      if (p['type'] != 'shwakel_transfer') throw 'الرمز غير مدعوم.';
      if (p['userId'] == _user?['id']?.toString())
        throw 'لا يمكن التحويل لنفسك.';

      final amt = await _askAmount(p['username'], p['phone']);
      if (amt == null) return;

      final sec = await TransferSecurityService.confirmTransfer(context);
      if (!sec.isVerified) return;

      final loc = await TransactionLocationService.captureCurrentLocation();
      await _api.transferBalance(
        recipientId: p['userId'],
        amount: amt,
        otpCode: sec.otpCode,
        location: loc,
      );
      await _load();
      if (mounted)
        AppAlertService.showSuccess(
          context,
          message: 'تم تنفيذ التحويل بنجاح.',
        );
    } catch (e) {
      if (mounted) AppAlertService.showError(context, message: e.toString());
    }
  }

  Future<double?> _askAmount(String name, String phone) => showDialog<double>(
    context: context,
    builder: (c) {
      final cur = TextEditingController();
      return AlertDialog(
        title: const Text('تحويل رصيد مباشر'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('إلى: $name ($phone)', style: AppTheme.bodyBold),
            const SizedBox(height: 24),
            TextField(
              controller: cur,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ المراد تحويله (₪)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('إلغاء'),
          ),
          ShwakelButton(
            label: 'متابعة',
            onPressed: () => Navigator.pop(c, double.tryParse(cur.text) ?? 0),
            width: 140,
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_canTransfer)
      return Scaffold(
        body: Center(child: Text('لا تملك صلاحية استخدام التحويل السريع.')),
      );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('النقل السريع')),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            children: [
              ShwakelCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: AppTheme.primary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('فتح الكاميرا', style: AppTheme.h3),
                              const SizedBox(height: 4),
                              Text(
                                'امسح رمز المستلم لبدء التحويل مباشرة.',
                                style: AppTheme.bodyAction,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ShwakelButton(
                      label: 'فتح الكاميرا والمسح',
                      icon: Icons.qr_code_scanner_rounded,
                      onPressed: _scan,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildMyCode(),
              const SizedBox(height: 24),
              ShwakelCard(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    const Icon(
                      Icons.send_to_mobile_rounded,
                      color: AppTheme.primary,
                      size: 48,
                    ),
                    const SizedBox(height: 24),
                    Text('تحويل رصيد مباشر', style: AppTheme.h2),
                    const SizedBox(height: 12),
                    Text(
                      'امسح رمز المستخدم الآخر لتحويل الرصيد إليه بسرعة وأمان.',
                      textAlign: TextAlign.center,
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyCode() {
    return ShwakelCard(
      padding: const EdgeInsets.all(40),
      gradient: AppTheme.darkGradient,
      child: Column(
        children: [
          Text(
            'رمز استلام الرصيد',
            style: AppTheme.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            'اعرض هذا الرمز للمرسل ليتمكن من تحويل الرصيد إليك مباشرة.',
            style: AppTheme.caption.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppTheme.radiusMd,
            ),
            child: QrImageView(data: _payload(), size: 240),
          ),
          const SizedBox(height: 32),
          Text(
            _user?['username'] ?? '',
            style: AppTheme.h1.copyWith(color: Colors.white),
          ),
          Text(
            _user?['whatsapp'] ?? '',
            style: AppTheme.bodyBold.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
