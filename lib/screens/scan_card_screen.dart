import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

class ScanCardScreen extends StatefulWidget {
  const ScanCardScreen({super.key, this.initialBarcode});

  final String? initialBarcode;

  @override
  State<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends State<ScanCardScreen> with RouteAware {
  final MobileScannerController _camC = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _bcC = TextEditingController();
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();

  VirtualCard? _card;
  Map<String, dynamic>? _user;
  bool _isSearching = false;
  bool _isSubmitting = false;
  bool _camActive = false;
  bool _showDetails = false;
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialBarcode?.isNotEmpty == true) {
      _bcC.text = widget.initialBarcode!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _camC.dispose();
    _bcC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    if (mounted) {
      setState(() => _user = user);
    }
  }

  Future<void> _search() async {
    final barcode = _bcC.text.trim();
    if (barcode.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      final result = await _api.getCardByBarcode(barcode);
      if (!mounted) return;
      setState(() {
        _card = result;
        _showDetails = false;
        _isSearching = false;
      });
      if (result == null) {
        AppAlertService.showError(
          context,
          title: 'تعذر الفحص',
          message: 'تعذر العثور على البطاقة.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      AppAlertService.showError(
        context,
        title: 'تعذر الفحص',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _redeem() async {
    if (_card == null) return;

    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    if (permissions['canRedeemCards'] != true) {
      AppAlertService.showError(
        context,
        title: 'غير متاح',
        message: 'يمكنك فحص البطاقة فقط. استلام الرصيد يتطلب توثيق الحساب.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _api.redeemCard(
        cardId: _card!.id,
        customerName: _user?['fullName'] ?? _user?['username'] ?? 'مستخدم',
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      await _search();
      if (!mounted) return;
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
      AppAlertService.showSuccess(
        context,
        title: 'تم الاعتماد',
        message: 'تم اعتماد البطاقة وإضافة الرصيد بنجاح.',
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: 'تعذر التنفيذ',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resell() async {
    if (_card == null) return;

    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    if (permissions['canResellCards'] != true) {
      AppAlertService.showError(
        context,
        title: 'غير متاح',
        message: 'لا تملك صلاحية إعادة تفعيل البطاقات المستخدمة.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد إعادة التفعيل'),
        content: const Text(
          'سيتم إعادة تفعيل هذه البطاقة لتصبح جاهزة للاستخدام مرة أخرى. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.autorenew_rounded),
            label: const Text('إعادة التفعيل'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _api.resellCard(
        cardId: _card!.id,
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      await _search();
      if (!mounted) return;
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
      AppAlertService.showSuccess(
        context,
        title: 'تمت إعادة التفعيل',
        message: 'تمت إعادة تفعيل البطاقة بنجاح وأصبحت جاهزة للاستخدام.',
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: 'تعذر التنفيذ',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _statusLabel(VirtualCard card) {
    switch (card.status) {
      case CardStatus.used:
        return 'مستخدمة';
      case CardStatus.archived:
        return 'مؤرشفة';
      case CardStatus.unused:
        return 'متاحة';
    }
  }

  String _cardTypeLabel(VirtualCard card) {
    return card.isSingleUse ? 'استخدام واحد' : 'رصيد';
  }

  String _visibilityLabel(VirtualCard card) {
    return card.isPrivate ? 'خاصة' : 'عامة';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('فحص الباركود')),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            children: [
              _buildHero(),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  if (!isWide) {
                    return Column(
                      children: [
                        _buildScannerPanel(),
                        const SizedBox(height: 18),
                        _card == null ? _buildEmptyPreview() : _buildDetails(),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildScannerPanel()),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: _card == null
                            ? _buildEmptyPreview()
                            : _buildDetails(),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final balance = (_user?['balance'] as num?)?.toDouble() ?? 0;
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: const LinearGradient(
        colors: [Color(0xFF25C4D9), Color(0xFF17A79A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      withBorder: false,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'فحص البطاقات',
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'الرصيد الحالي: ${CurrencyFormatter.ils(balance)}',
                  style: AppTheme.bodyBold.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerPanel() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('البحث عن البطاقة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text('أدخل الباركود أو افتح الكاميرا.', style: AppTheme.bodyAction),
          const SizedBox(height: 18),
          TextField(
            controller: _bcC,
            decoration: InputDecoration(
              labelText: 'رقم الباركود',
              prefixIcon: const Icon(Icons.qr_code_rounded),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 520;
              if (isCompact) {
                return Column(
                  children: [
                    ShwakelButton(
                      label: _camActive ? 'إغلاق الكاميرا' : 'فتح الكاميرا',
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: () => setState(() => _camActive = !_camActive),
                    ),
                    const SizedBox(height: 12),
                    ShwakelButton(
                      label: 'بحث',
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: ShwakelButton(
                      label: _camActive ? 'إغلاق الكاميرا' : 'فتح الكاميرا',
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: () => setState(() => _camActive = !_camActive),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShwakelButton(
                      label: 'بحث',
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
                  ),
                ],
              );
            },
          ),
          if (_camActive) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 320,
                child: MobileScanner(
                  controller: _camC,
                  onDetect: (capture) {
                    final value = capture.barcodes.first.rawValue ?? '';
                    if (value.isEmpty) return;
                    setState(() {
                      _bcC.text = value;
                      _camActive = false;
                    });
                    _search();
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final card = _card!;
    final isUsed = card.status == CardStatus.used;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    final canRedeemCards = permissions['canRedeemCards'] == true;
    final canResellCards = permissions['canResellCards'] == true;
    final canReviewCards = permissions['canReviewCards'] == true;
    final canViewCardDetails = canReviewCards || canResellCards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShwakelCard(
          padding: const EdgeInsets.all(24),
          color: accent.withValues(alpha: 0.08),
          borderColor: accent.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(30),
          shadowLevel: ShwakelShadowLevel.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isUsed ? Icons.cancel_rounded : Icons.verified_rounded,
                      color: accent,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نتيجة الفحص',
                          style: AppTheme.caption.copyWith(color: accent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isUsed ? 'البطاقة مستخدمة' : 'البطاقة صالحة وجاهزة',
                          style: AppTheme.h2.copyWith(color: accent),
                        ),
                      ],
                    ),
                  ),
                  if (isUsed && canResellCards)
                    IconButton.filledTonal(
                      tooltip: 'إعادة تفعيل البطاقة',
                      onPressed: _isSubmitting ? null : _resell,
                      icon: const Icon(Icons.autorenew_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isUsed
                      ? 'هذه البطاقة مستعملة سابقًا ولا يمكن اعتمادها مرة أخرى.'
                      : 'هذه البطاقة سليمة ويمكن اعتمادها أو مراجعة تفاصيلها.',
                  style: AppTheme.bodyBold.copyWith(color: accent),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _resultBadge('الحالة', _statusLabel(card), accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _resultBadge(
                      'القيمة',
                      CurrencyFormatter.ils(card.value),
                      AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!isUsed && canRedeemCards) ...[
          ShwakelButton(
            label: 'اعتماد البطاقة واستلام الرصيد',
            icon: Icons.download_done_rounded,
            onPressed: _redeem,
            isLoading: _isSubmitting,
          ),
          const SizedBox(height: 16),
        ],
        if (isUsed && canResellCards) ...[
          ShwakelButton(
            label: 'إعادة تفعيل البطاقة',
            icon: Icons.autorenew_rounded,
            onPressed: _resell,
            isLoading: _isSubmitting,
          ),
          const SizedBox(height: 16),
        ],
        if (!isUsed && !canRedeemCards) ...[
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            color: AppTheme.warning.withValues(alpha: 0.08),
            borderColor: AppTheme.warning.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, color: AppTheme.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'يمكنك فحص البطاقة فقط. استلام الرصيد يتطلب توثيق الحساب.',
                    style: AppTheme.bodyText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (canViewCardDetails)
          OutlinedButton.icon(
            onPressed: () => setState(() => _showDetails = !_showDetails),
            icon: Icon(
              _showDetails
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
            label: Text(
              _showDetails ? 'إخفاء تفاصيل البطاقة' : 'عرض تفاصيل البطاقة',
            ),
          ),
        if (_showDetails && canViewCardDetails) ...[
          const SizedBox(height: 16),
          ShwakelCard(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(28),
            shadowLevel: ShwakelShadowLevel.medium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ShwakelLogo(size: 40, framed: true),
                    const SizedBox(width: 12),
                    Expanded(child: Text('تفاصيل البطاقة', style: AppTheme.h2)),
                    Text(
                      CurrencyFormatter.ils(card.value),
                      style: AppTheme.h2.copyWith(color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 620;
                    final items = [
                      _detailTile('الباركود', card.barcode),
                      _detailTile('الحالة', _statusLabel(card)),
                      _detailTile('نوع البطاقة', _cardTypeLabel(card)),
                      _detailTile('الإتاحة', _visibilityLabel(card)),
                      _detailTile(
                        'قيمة البطاقة',
                        CurrencyFormatter.ils(card.value),
                      ),
                      _detailTile(
                        'تكلفة الإصدار',
                        CurrencyFormatter.ils(card.issueCost),
                      ),
                      _detailTile('المالك', card.ownerUsername ?? '-'),
                      _detailTile('أصدرها', card.issuedByUsername ?? '-'),
                      _detailTile('استُخدمت بواسطة', card.usedBy ?? '-'),
                      _detailTile('اسم العميل', card.customerName ?? '-'),
                      _detailTile('تاريخ الإصدار', _formatDate(card.createdAt)),
                      _detailTile('تاريخ الاستخدام', _formatDate(card.usedAt)),
                      _detailTile(
                        'آخر إعادة بيع',
                        _formatDate(card.lastResoldAt),
                      ),
                      _detailTile('مرات الاستخدام', '${card.useCount}'),
                      _detailTile('مرات إعادة البيع', '${card.resaleCount}'),
                      _detailTile(
                        'إجمالي القيمة المستخدمة',
                        CurrencyFormatter.ils(card.totalRedeemedValue),
                      ),
                      _detailTile(
                        'المستخدمون المسموح لهم',
                        card.allowedUsernames.isEmpty
                            ? '-'
                            : card.allowedUsernames.join('، '),
                        spanTwo: true,
                      ),
                    ];

                    if (isCompact) {
                      return Column(
                        children: items
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: item,
                              ),
                            )
                            .toList(),
                      );
                    }

                    return Wrap(spacing: 12, runSpacing: 12, children: items);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _resultBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _detailTile(String label, String value, {bool spanTwo = false}) {
    return SizedBox(
      width: spanTwo ? 420 : 204,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(value, style: AppTheme.bodyBold),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPreview() {
    return ShwakelCard(
      padding: const EdgeInsets.all(40),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        children: [
          Icon(
            Icons.credit_card_off_rounded,
            size: 56,
            color: AppTheme.textTertiary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 18),
          Text('تفاصيل البطاقة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'ابحث عن البطاقة أو استخدم الكاميرا لعرض بياناتها.',
            style: AppTheme.bodyAction,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
