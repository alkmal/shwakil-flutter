import 'package:flutter/material.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

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
  bool _isLoading = true;
  bool _isSyncingCards = false;
  bool _isSyncingQueue = false;
  bool _isAuthorized = false;
  int _pendingCount = 0;
  double _pendingAmount = 0;
  int _rejectedCount = 0;
  int _availableCount = 0;
  Map<String, dynamic> _offlineSettings = const {};
  List<Map<String, dynamic>> _pendingItems = const [];
  List<Map<String, dynamic>> _historyItems = const [];

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
      _availableCount = (overview['availableCount'] as num?)?.toInt() ?? 0;
      _pendingCount = (summary['count'] as num?)?.toInt() ?? 0;
      _pendingAmount = (summary['amount'] as num?)?.toDouble() ?? 0;
      _rejectedCount = (summary['rejectedCount'] as num?)?.toInt() ?? 0;
      _pendingItems = List<Map<String, dynamic>>.from(
        summary['items'] as List? ?? const [],
      );
      _offlineSettings = Map<String, dynamic>.from(
        overview['settings'] as Map? ?? const {},
      );
      _historyItems = List<Map<String, dynamic>>.from(
        overview['history'] as List? ?? const [],
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
      final syncedAt = DateTime.now().toIso8601String();
      final historyEntries = queue.map((entry) {
        final barcode = entry['barcode']?.toString() ?? '';
        Map<String, dynamic>? matchedResult;
        for (final item in resultItems) {
          if (item['barcode']?.toString() == barcode) {
            matchedResult = item;
            break;
          }
        }
        final ok = matchedResult?['ok'] == true;
        return {
          ...entry,
          'status': ok ? 'confirmed' : 'rejected',
          'message': matchedResult?['message']?.toString(),
          'syncedAt': syncedAt,
          'confirmedOffline': true,
        };
      }).toList();
      final rejectedHistoryEntries = historyEntries
          .where((item) => item['status'] == 'rejected')
          .toList();

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
        rejectedHistoryEntries,
      );
      await _offlineCardService.appendSyncHistory(
        userId,
        rejectedHistoryEntries,
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
        appBar: AppBar(
          title: const Text('مركز الأوفلاين'),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
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
        appBar: AppBar(
          title: const Text('مركز الأوفلاين'),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
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
                Text(
                  'لا تملك صلاحية استخدام مركز الأوفلاين',
                  style: AppTheme.h3,
                ),
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
      appBar: AppBar(
        title: const Text('مركز الأوفلاين'),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
      ),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(),
              const SizedBox(height: 18),
              _buildActionCard(),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _statCard(
                    label: 'بطاقات جاهزة',
                    value: '$_availableCount',
                    hint: 'للقراءة فقط',
                    color: AppTheme.success,
                    icon: Icons.credit_card_rounded,
                  ),
                  _statCard(
                    label: 'معلّق للمزامنة',
                    value: '$_pendingCount / $maxPendingCount',
                    hint: CurrencyFormatter.ils(_pendingAmount),
                    color: AppTheme.primary,
                    icon: Icons.cloud_upload_rounded,
                  ),
                  _statCard(
                    label: 'حد الأوف لاين',
                    value: CurrencyFormatter.ils(maxPendingAmount),
                    hint: 'قبل طلب المزامنة',
                    color: AppTheme.warning,
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  _statCard(
                    label: 'بحاجة مراجعة',
                    value: '$_rejectedCount',
                    hint: 'بعد عودة الإنترنت',
                    color: AppTheme.error,
                    icon: Icons.rule_folder_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildTrackingList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: const LinearGradient(
        colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      withBorder: false,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const ShwakelLogo(size: 82, framed: true),
          const SizedBox(height: 18),
          Text(
            'العمل أوف لاين',
            style: AppTheme.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'ابدأ بقراءة البطاقة محليًا، ثم مزامن العمليات عند عودة الإنترنت.',
            style: AppTheme.bodyAction.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill('بطاقات جاهزة: $_availableCount'),
              _heroPill('عمليات معلقة: $_pendingCount'),
              _heroPill('مرفوض للمراجعة: $_rejectedCount'),
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
          Text('مساحة القراءة السريعة', style: AppTheme.h3),
          const SizedBox(height: 6),
          Text(
            'واجهة بسيطة لقراءة البطاقة ثم اعتمادها ومزامنتها لاحقًا.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: 'فتح القراءة للبطاقة',
            icon: Icons.qr_code_scanner_rounded,
            onPressed: () => Navigator.pushNamed(context, '/scan-card-offline'),
          ),
          const SizedBox(height: 12),
          ShwakelButton(
            label: 'تحديث مخزون الأوف لاين',
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

  Widget _buildTrackingList() {
    final items = [
      ..._pendingItems.map((item) => {...item, 'status': 'pending'}),
      ..._historyItems.where((item) => item['status'] == 'rejected'),
    ];

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('متابعة بطاقات الأوف لاين', style: AppTheme.h3),
          const SizedBox(height: 6),
          Text(
            'تظهر هنا البطاقات المعلقة حاليًا، وأي بطاقة فشلت مزامنتها بعد العودة إلى الأون لاين. اضغط على أي بطاقة لعرض التفاصيل.',
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text('لا توجد بطاقات محفوظة للمراجعة حاليًا.'),
            )
          else
            ...items.map(_buildTrackedItem),
        ],
      ),
    );
  }

  Widget _buildTrackedItem(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'pending';
    final color = switch (status) {
      'rejected' => AppTheme.error,
      _ => AppTheme.warning,
    };
    final label = switch (status) {
      'rejected' => 'لم يتم تأكيدها',
      _ => 'معلقة للمزامنة',
    };
    final ownerName =
        item['offlineCardOwnerName']?.toString().trim().isNotEmpty == true
        ? item['offlineCardOwnerName'].toString().trim()
        : 'بدون اسم';
    final barcode = item['barcode']?.toString() ?? 'غير متوفر';

    return InkWell(
      onTap: () => _showTrackedItemDetails(item),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.credit_card_rounded, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ownerName, style: AppTheme.bodyBold),
                  const SizedBox(height: 4),
                  Text(barcode, style: AppTheme.caption),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: AppTheme.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Future<void> _showTrackedItemDetails(Map<String, dynamic> item) async {
    final syncedAt = item['syncedAt']?.toString();
    final queuedAt = item['queuedAt']?.toString();
    final usedAt = DateTime.tryParse(queuedAt ?? '');
    final syncedDate = DateTime.tryParse(syncedAt ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تفاصيل البطاقة', style: AppTheme.h3),
              const SizedBox(height: 16),
              _detailRow(
                'الاسم المضاف',
                item['offlineCardOwnerName']?.toString() ?? '-',
              ),
              _detailRow('الباركود', item['barcode']?.toString() ?? '-'),
              _detailRow(
                'آخر استخدام',
                usedAt == null
                    ? '-'
                    : '${usedAt.year}-${usedAt.month.toString().padLeft(2, '0')}-${usedAt.day.toString().padLeft(2, '0')} ${usedAt.hour.toString().padLeft(2, '0')}:${usedAt.minute.toString().padLeft(2, '0')}',
              ),
              _detailRow(
                'اسم منفذ العملية',
                item['customerName']?.toString() ?? '-',
              ),
              _detailRow('من استخدمها', item['usedBy']?.toString() ?? '-'),
              _detailRow(
                'من الذي أحضر البطاقة',
                item['offlineCardOwnerName']?.toString() ?? '-',
              ),
              _detailRow(
                'وقت المزامنة',
                syncedDate == null
                    ? '-'
                    : '${syncedDate.year}-${syncedDate.month.toString().padLeft(2, '0')}-${syncedDate.day.toString().padLeft(2, '0')} ${syncedDate.hour.toString().padLeft(2, '0')}:${syncedDate.minute.toString().padLeft(2, '0')}',
              ),
              _detailRow('النتيجة', item['status']?.toString() ?? '-'),
              _detailRow('ملاحظة', item['message']?.toString() ?? '-'),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold),
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
}
