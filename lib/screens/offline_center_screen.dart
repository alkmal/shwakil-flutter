import 'package:flutter/material.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class OfflineCenterScreen extends StatefulWidget {
  const OfflineCenterScreen({super.key});

  @override
  State<OfflineCenterScreen> createState() => _OfflineCenterScreenState();
}

class _OfflineCenterScreenState extends State<OfflineCenterScreen> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final OfflineCardService _offlineCardService = OfflineCardService();

  Map<String, dynamic>? _user;
  List<VirtualCard> _cachedCards = const [];
  List<Map<String, dynamic>> _rejectedItems = const [];
  bool _isLoading = true;
  bool _isSyncingCards = false;
  bool _isSyncingQueue = false;
  bool _isAuthorized = false;
  int _pendingCount = 0;
  double _pendingAmount = 0;
  int _rejectedCount = 0;
  int _availableCount = 0;
  int _usedCount = 0;
  Map<String, dynamic> _offlineSettings = const {};

  bool get _canOfflineScan =>
      AppPermissions.fromUser(_user).canOfflineCardScan && _user?['id'] != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await _authService.currentUser();
    if (!mounted) {
      return;
    }
    setState(() {
      _user = user;
      _isAuthorized = AppPermissions.fromUser(user).canOfflineCardScan;
    });
    await _loadOverview();
  }

  Future<void> _loadOverview() async {
    final user = _user ?? await _authService.currentUser();
    if (user == null || user['id'] == null || !_isAuthorized) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final overview = await _offlineCardService.offlineOverview(
      user['id'].toString(),
    );
    final summary = Map<String, dynamic>.from(
      overview['summary'] as Map? ?? const {},
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _cachedCards = const [];
      _availableCount = (overview['availableCount'] as num?)?.toInt() ?? 0;
      _usedCount = (overview['usedCount'] as num?)?.toInt() ?? 0;
      _pendingCount = (summary['count'] as num?)?.toInt() ?? 0;
      _pendingAmount = (summary['amount'] as num?)?.toDouble() ?? 0;
      _rejectedCount = (summary['rejectedCount'] as num?)?.toInt() ?? 0;
      _rejectedItems = const [];
      _offlineSettings = Map<String, dynamic>.from(
        overview['settings'] as Map? ?? const {},
      );
      _isLoading = false;
    });
  }

  Future<void> _syncCards() async {
    if (!_canOfflineScan) {
      return;
    }
    setState(() => _isSyncingCards = true);
    try {
      final payload = await _apiService.getOfflineCardCache();
      await _offlineCardService.cacheCards(
        userId: _user!['id'].toString(),
        cards: List<VirtualCard>.from(payload['cards'] as List? ?? const []),
        settings: Map<String, dynamic>.from(
          payload['settings'] as Map? ?? const {},
        ),
      );
      await _loadOverview();
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        title: 'تم تحديث بيانات الأوفلاين',
        message: 'أصبح أحدث مخزون البطاقات متاحًا على هذا الجهاز.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر تحديث بيانات الأوفلاين',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingCards = false);
      }
    }
  }

  Future<void> _syncQueue() async {
    if (!_canOfflineScan) {
      return;
    }
    final userId = _user!['id'].toString();
    final queue = await _offlineCardService.getRedeemQueue(userId);
    if (queue.isEmpty) {
      if (!mounted) {
        return;
      }
      AppAlertService.showInfo(
        context,
        title: 'لا توجد عمليات معلقة',
        message: 'كل عمليات الأوفلاين تمت مزامنتها بالفعل.',
      );
      return;
    }

    setState(() => _isSyncingQueue = true);
    try {
      final result = await _apiService.syncOfflineCardRedeems(items: queue);
      final resultItems = List<Map<String, dynamic>>.from(
        (result['results'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final rejectedBarcodes = <String>{
        for (final item in resultItems)
          if (item['ok'] != true) (item['barcode'] ?? '').toString(),
      }..remove('');
      final acceptedBarcodes = <String>{
        for (final item in resultItems)
          if (item['ok'] == true) (item['barcode'] ?? '').toString(),
      }..remove('');

      await _offlineCardService.replaceRedeemQueue(
        userId,
        queue
            .where(
              (item) => rejectedBarcodes.contains(item['barcode']?.toString()),
            )
            .toList(),
      );
      await _offlineCardService.replaceRejectedRedeems(
        userId,
        resultItems.where((item) => item['ok'] != true).toList(),
      );
      await _offlineCardService.removeCardsByBarcode(
        userId: userId,
        barcodes: acceptedBarcodes,
      );
      final updatedBalance = (result['balance'] as num?)?.toDouble();
      if (updatedBalance != null) {
        await _authService.patchCurrentUser({'balance': updatedBalance});
        _user = await _authService.currentUser();
      }
      await _loadOverview();
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        title: 'اكتملت المزامنة',
        message:
            'تمت مزامنة ${acceptedBarcodes.length} بطاقة، والمتبقي للمراجعة $_rejectedCount.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر مزامنة العمليات',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingQueue = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const Text('مركز الأوفلاين')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const Text('مركز الأوفلاين')),
        body: Center(
          child: ShwakelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 54,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 14),
                Text('لا تملك صلاحية استخدام مركز الأوفلاين', style: AppTheme.h3),
              ],
            ),
          ),
        ),
      );
    }

    final maxPendingCount =
        (_offlineSettings['maxPendingCount'] as num?)?.toInt() ?? 50;
    final maxPendingAmount =
        (_offlineSettings['maxPendingAmount'] as num?)?.toDouble() ?? 500;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('مركز الأوفلاين')),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 760;
                        final children = [
                          _statCard(
                            label: 'بطاقات متاحة',
                            value: '$_availableCount',
                            hint: 'جاهزة للفحص والاستخدام محليًا',
                            color: AppTheme.success,
                            icon: Icons.credit_card_rounded,
                          ),
                          _statCard(
                            label: 'عمليات معلقة',
                            value: '$_pendingCount / $maxPendingCount',
                            hint: CurrencyFormatter.ils(_pendingAmount),
                            color: AppTheme.primary,
                            icon: Icons.cloud_upload_rounded,
                          ),
                          _statCard(
                            label: 'حد الأوفلاين',
                            value: CurrencyFormatter.ils(maxPendingAmount),
                            hint: 'السقف قبل الحاجة للمزامنة',
                            color: AppTheme.warning,
                            icon: Icons.account_balance_wallet_rounded,
                          ),
                          _statCard(
                            label: 'مرفوض للمراجعة',
                            value: '$_rejectedCount',
                            hint: 'عمليات تحتاج مراجعة بعد الاتصال',
                            color: AppTheme.error,
                            icon: Icons.rule_folder_rounded,
                          ),
                        ];

                        if (isCompact) {
                          return Column(
                            children: children
                                .map(
                                  (child) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: child,
                                  ),
                                )
                                .toList(),
                          );
                        }

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: children
                              .map(
                                (child) => SizedBox(
                                  width: (constraints.maxWidth - 12) / 2,
                                  child: child,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _buildActionCard(),
                    const SizedBox(height: 18),
                    _buildCachedCardsCard(),
                    if (_rejectedItems.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildRejectedCard(),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final name = _user?['fullName']?.toString().trim().isNotEmpty == true
        ? _user!['fullName'].toString().trim()
        : (_user?['username']?.toString() ?? 'المستخدم');
    final balance = (_user?['balance'] as num?)?.toDouble() ?? 0;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      gradient: const LinearGradient(
        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      withBorder: false,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الوضع الحالي: أوفلاين',
            style: AppTheme.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, style: AppTheme.h2.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'يمكنك متابعة الفحص المحلي ومراجعة المعلّق حتى يعود الاتصال.',
            style: AppTheme.bodyAction.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill('الرصيد المخزن: ${CurrencyFormatter.ils(balance)}'),
              _heroPill('بطاقات الكاش: $_availableCount'),
              _heroPill('مستخدمة محليًا: $_usedCount'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('إدارة الأوفلاين', style: AppTheme.h3),
          const SizedBox(height: 6),
          Text(
            'افتح شاشة الفحص السريعة أو حدّث المخزون وعمليات المزامنة فور عودة الاتصال.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: 'فتح فحص البطاقات',
            icon: Icons.qr_code_scanner_rounded,
            onPressed: () =>
                Navigator.pushNamed(context, '/scan-card-offline'),
          ),
          const SizedBox(height: 12),
          ShwakelButton(
            label: 'تحديث مخزون الأوفلاين',
            icon: Icons.download_rounded,
            isSecondary: true,
            isLoading: _isSyncingCards,
            onPressed: _isSyncingQueue ? null : _syncCards,
          ),
          const SizedBox(height: 12),
          ShwakelButton(
            label: 'مزامنة العمليات المعلقة',
            icon: Icons.cloud_upload_rounded,
            isSecondary: true,
            isLoading: _isSyncingQueue,
            onPressed: _isSyncingCards ? null : _syncQueue,
          ),
        ],
      ),
    );
  }

  Widget _buildCachedCardsCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('بطاقات الأوفلاين المحفوظة', style: AppTheme.h3),
          const SizedBox(height: 6),
          Text(
            'هذه البطاقات متاحة محليًا حتى بدون اتصال، ويمكنك فحصها من شاشة الفحص مباشرة.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          if (_cachedCards.isEmpty)
            Text(
              'لا توجد بطاقات محفوظة حاليًا على هذا الجهاز.',
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            )
          else
            ..._cachedCards.take(8).map(_buildCardRow),
        ],
      ),
    );
  }

  Widget _buildRejectedCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('عناصر بحاجة إلى مراجعة', style: AppTheme.h3),
          const SizedBox(height: 6),
          Text(
            'هذه العناصر لم تُعتمد بعد المزامنة وتحتاج متابعة عند العودة للأونلاين.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          ..._rejectedItems.take(6).map(_buildRejectedRow),
        ],
      ),
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required String hint,
    required Color color,
    required IconData icon,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(24),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTheme.caption),
                const SizedBox(height: 4),
                Text(value, style: AppTheme.h3.copyWith(color: color)),
                const SizedBox(height: 4),
                Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardRow(VirtualCard card) {
    final isUsed = card.status == CardStatus.used;
    final color = isUsed ? AppTheme.error : AppTheme.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            isUsed ? Icons.check_circle_rounded : Icons.credit_card_rounded,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.barcode, style: AppTheme.bodyBold),
                const SizedBox(height: 4),
                Text(
                  '${CurrencyFormatter.ils(card.value)} - ${isUsed ? 'مستخدمة' : 'متاحة'}',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedRow(Map<String, dynamic> item) {
    final barcode = item['barcode']?.toString().trim();
    final reason = item['message']?.toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barcode?.isNotEmpty == true ? barcode! : 'بطاقة غير معروفة',
                  style: AppTheme.bodyBold,
                ),
                if (reason?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    reason!,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
