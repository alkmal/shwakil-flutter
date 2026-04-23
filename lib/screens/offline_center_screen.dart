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

class OfflineCenterScreen extends StatefulWidget {
  const OfflineCenterScreen({super.key});

  @override
  State<OfflineCenterScreen> createState() => _OfflineCenterScreenState();
}

class _OfflineCenterScreenState extends State<OfflineCenterScreen> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final OfflineCardService _offlineCardService = OfflineCardService();
  final DebtBookService _debtBookService = DebtBookService();

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _isSyncingCards = false;
  bool _isSyncingQueue = false;
  bool _isSyncingDebtBook = false;
  bool _isAuthorized = false;
  int _pendingCount = 0;
  double _pendingAmount = 0;
  int _rejectedCount = 0;
  int _availableCount = 0;
  int _debtPendingCount = 0;
  String? _debtLastSyncedAt;
  String? _lastOfflineSyncAt;
  Map<String, dynamic> _offlineSettings = const {};
  List<Map<String, dynamic>> _pendingItems = const [];
  List<Map<String, dynamic>> _historyItems = const [];
  List<Map<String, dynamic>> _unknownItems = const [];

  bool get _canOfflineScan =>
      AppPermissions.fromUser(_user).canOfflineCardScan && _user?['id'] != null;

  bool get _canManageDebtBook =>
      AppPermissions.fromUser(_user).canManageDebtBook && _user?['id'] != null;

  bool get _isOnline => ConnectivityService.instance.isOnline.value;

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
    final debtPendingOperations = _canManageDebtBook
        ? await _debtBookService.getPendingOperations(user['id'].toString())
        : const <Map<String, dynamic>>[];
    final debtSnapshot = _canManageDebtBook
        ? await _debtBookService.getSnapshot(user['id'].toString())
        : const <String, dynamic>{};
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
      _debtPendingCount = debtPendingOperations.length;
      _debtLastSyncedAt = debtSnapshot['syncedAt']?.toString();
      _lastOfflineSyncAt = overview['settings'] is Map
          ? (overview['settings'] as Map)['lastSyncAt']?.toString()
          : null;
      _pendingItems = List<Map<String, dynamic>>.from(
        summary['items'] as List? ?? const [],
      );
      _offlineSettings = Map<String, dynamic>.from(
        overview['settings'] as Map? ?? const {},
      );
      _historyItems = List<Map<String, dynamic>>.from(
        overview['history'] as List? ?? const [],
      );
      _unknownItems = List<Map<String, dynamic>>.from(
        overview['unknownLookups'] as List? ?? const [],
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
      await _resolveUnknownLookups();
      await _offlineCardService.recordLastSync(
        _user!['id'].toString(),
        source: 'inventory',
      );
      await _loadOverview();
      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: context.loc.tr('screens_offline_center_screen.003'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingCards = false);
      }
    }
  }

  Future<void> _resolveUnknownLookups() async {
    final l = context.loc;
    final userId = _user?['id']?.toString();
    if (userId == null) {
      return;
    }
    final lookups = await _offlineCardService.getUnknownCardLookups(userId);
    if (lookups.isEmpty) {
      return;
    }

    final foundCards = <VirtualCard>[];
    final unresolved = <Map<String, dynamic>>[];
    for (final item in lookups) {
      final barcode = item['barcode']?.toString().trim() ?? '';
      if (barcode.isEmpty) {
        continue;
      }
      try {
        final card = await _apiService.getCardByBarcode(barcode);
        if (card == null) {
          unresolved.add({
            ...item,
            'status': 'pending_lookup',
            'message': l.tr('screens_offline_center_screen.004'),
            'lastCheckedAt': DateTime.now().toIso8601String(),
          });
          continue;
        }
        foundCards.add(card);
      } catch (_) {
        unresolved.add({
          ...item,
          'status': 'pending_lookup',
          'message': l.tr('screens_offline_center_screen.005'),
          'lastCheckedAt': DateTime.now().toIso8601String(),
        });
      }
    }

    if (foundCards.isNotEmpty) {
      await _offlineCardService.cacheCards(userId: userId, cards: foundCards);
    }
    await _offlineCardService.replaceUnknownCardLookups(userId, unresolved);
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
        title: context.loc.tr('screens_offline_center_screen.006'),
        message: context.loc.tr('screens_offline_center_screen.007'),
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
      await _offlineCardService.recordLastSync(userId, source: 'queue');
      await _loadOverview();
      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: context.loc.tr('screens_offline_center_screen.010'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingQueue = false);
      }
    }
  }

  Future<void> _syncDebtBook() async {
    if (!_canManageDebtBook) {
      return;
    }
    if (!_isOnline) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showInfo(
        context,
        title: context.loc.tr('screens_debt_book_screen.002'),
        message: context.loc.tr('screens_debt_book_screen.003'),
      );
      return;
    }

    setState(() => _isSyncingDebtBook = true);
    try {
      await _debtBookService.syncPending(
        userId: _user!['id'].toString(),
        api: _apiService,
      );
      await _offlineCardService.recordLastSync(
        _user!['id'].toString(),
        source: 'debt_book',
      );
      await _loadOverview();
      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: context.loc.tr('screens_offline_center_screen.048'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingDebtBook = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          actions: [
            _buildSyncStatusAction(),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
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
          title: const SizedBox.shrink(),
          actions: [
            _buildSyncStatusAction(),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
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
                  context.loc.tr('screens_offline_center_screen.011'),
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
        title: const SizedBox.shrink(),
        actions: [
          _buildSyncStatusAction(),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOverviewCard(),
              const SizedBox(height: 18),
              _buildActionCard(),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _statCard(
                    label: context.loc.tr('screens_offline_center_screen.012'),
                    value: '$_availableCount',
                    hint: context.loc.tr('screens_offline_center_screen.013'),
                    color: AppTheme.success,
                    icon: Icons.credit_card_rounded,
                  ),
                  _statCard(
                    label: context.loc.tr('screens_offline_center_screen.014'),
                    value: '$_pendingCount / $maxPendingCount',
                    hint: CurrencyFormatter.ils(_pendingAmount),
                    color: AppTheme.primary,
                    icon: Icons.cloud_upload_rounded,
                  ),
                  _statCard(
                    label: context.loc.tr('screens_offline_center_screen.015'),
                    value: CurrencyFormatter.ils(maxPendingAmount),
                    hint: context.loc.tr('screens_offline_center_screen.016'),
                    color: AppTheme.warning,
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                  _statCard(
                    label: context.loc.tr('screens_offline_center_screen.017'),
                    value: '$_rejectedCount',
                    hint: context.loc.tr('screens_offline_center_screen.018'),
                    color: AppTheme.error,
                    icon: Icons.rule_folder_rounded,
                  ),
                  if (_canManageDebtBook)
                    _statCard(
                      label: context.loc.tr('screens_debt_book_screen.030'),
                      value: '$_debtPendingCount',
                      hint: _debtLastSyncedAt == null
                          ? context.loc.tr('screens_debt_book_screen.001')
                          : context.loc.tr(
                              'screens_debt_book_screen.033',
                              params: {'date': _debtLastSyncedAt!},
                            ),
                      color: const Color(0xFF7C3AED),
                      icon: Icons.menu_book_rounded,
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

  Widget _buildOverviewCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.loc.tr('screens_offline_center_screen.019'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 6),
          Text(
            context.loc.tr('screens_offline_center_screen.020'),
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _overviewPill(
                context.loc.tr(
                  'screens_offline_center_screen.021',
                  params: {'count': '$_availableCount'},
                ),
              ),
              _overviewPill(
                context.loc.tr(
                  'screens_offline_center_screen.022',
                  params: {'count': '$_pendingCount'},
                ),
              ),
              _overviewPill(
                context.loc.tr(
                  'screens_offline_center_screen.023',
                  params: {'count': '$_rejectedCount'},
                ),
              ),
              if (_canManageDebtBook)
                _overviewPill(
                  context.loc.tr(
                    'screens_offline_center_screen.049',
                    params: {'count': '$_debtPendingCount'},
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _overviewPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(fontWeight: FontWeight.w800),
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
          Text(
            context.loc.tr('screens_offline_center_screen.024'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 6),
          Text(
            context.loc.tr('screens_offline_center_screen.025'),
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 16),
          ShwakelButton(
            label: context.loc.tr('screens_offline_center_screen.026'),
            icon: Icons.qr_code_scanner_rounded,
            onPressed: () => Navigator.pushNamed(context, '/scan-card-offline'),
          ),
          const SizedBox(height: 12),
          ShwakelButton(
            label: context.loc.tr('screens_offline_center_screen.027'),
            icon: Icons.download_rounded,
            isSecondary: true,
            isLoading: _isSyncingCards,
            onPressed: _isSyncingQueue ? null : _syncCards,
          ),
          const SizedBox(height: 12),
          ShwakelButton(
            label: context.loc.tr('screens_offline_center_screen.028'),
            icon: Icons.cloud_upload_rounded,
            isSecondary: true,
            isLoading: _isSyncingQueue,
            onPressed: _isSyncingCards || _isSyncingDebtBook
                ? null
                : _syncQueue,
          ),
          if (_canManageDebtBook) ...[
            const SizedBox(height: 12),
            ShwakelButton(
              label: context.loc.tr('screens_home_screen.071'),
              icon: Icons.menu_book_rounded,
              isSecondary: true,
              onPressed: () => Navigator.pushNamed(context, '/debt-book'),
            ),
            const SizedBox(height: 12),
            ShwakelButton(
              label: context.loc.tr('screens_offline_center_screen.050'),
              icon: _isOnline ? Icons.sync_rounded : Icons.cloud_off_rounded,
              isSecondary: true,
              isLoading: _isSyncingDebtBook,
              onPressed: _isSyncingCards || _isSyncingQueue
                  ? null
                  : _syncDebtBook,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrackingList() {
    final items = [
      ..._pendingItems.map((item) => {...item, 'status': 'pending'}),
      ..._unknownItems.map((item) => {...item, 'status': 'pending_lookup'}),
      ..._historyItems.where((item) => item['status'] == 'rejected'),
    ];

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.loc.tr('screens_offline_center_screen.029'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 6),
          Text(
            context.loc.tr('screens_offline_center_screen.030'),
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
              child: Text(context.loc.tr('screens_offline_center_screen.031')),
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
      'pending_lookup' => AppTheme.primary,
      _ => AppTheme.warning,
    };
    final label = switch (status) {
      'rejected' => context.loc.tr('screens_offline_center_screen.032'),
      'pending_lookup' => context.loc.tr('screens_offline_center_screen.033'),
      _ => context.loc.tr('screens_offline_center_screen.045'),
    };
    final ownerName =
        item['offlineCardOwnerName']?.toString().trim().isNotEmpty == true
        ? item['offlineCardOwnerName'].toString().trim()
        : context.loc.tr('screens_offline_center_screen.034');
    final barcode =
        item['barcode']?.toString() ??
        context.loc.tr('screens_offline_center_screen.035');

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
              Text(
                context.loc.tr('screens_offline_center_screen.036'),
                style: AppTheme.h3,
              ),
              const SizedBox(height: 16),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.037'),
                item['offlineCardOwnerName']?.toString() ?? '-',
              ),
              _detailRow(
                context.loc.tr('screens_scan_card_screen.023'),
                item['barcode']?.toString() ?? '-',
              ),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.038'),
                usedAt == null
                    ? '-'
                    : '${usedAt.year}-${usedAt.month.toString().padLeft(2, '0')}-${usedAt.day.toString().padLeft(2, '0')} ${usedAt.hour.toString().padLeft(2, '0')}:${usedAt.minute.toString().padLeft(2, '0')}',
              ),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.039'),
                item['customerName']?.toString() ?? '-',
              ),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.040'),
                item['usedBy']?.toString() ?? '-',
              ),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.041'),
                item['offlineCardOwnerName']?.toString() ?? '-',
              ),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.042'),
                syncedDate == null
                    ? '-'
                    : '${syncedDate.year}-${syncedDate.month.toString().padLeft(2, '0')}-${syncedDate.day.toString().padLeft(2, '0')} ${syncedDate.hour.toString().padLeft(2, '0')}:${syncedDate.minute.toString().padLeft(2, '0')}',
              ),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.043'),
                item['status']?.toString() ?? '-',
              ),
              _detailRow(
                context.loc.tr('screens_offline_center_screen.044'),
                item['message']?.toString() ?? '-',
              ),
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

  Widget _buildSyncStatusAction() {
    final l = context.loc;
    final hasPending = _pendingCount > 0 || _debtPendingCount > 0;
    final isSyncing =
        _isSyncingCards || _isSyncingQueue || _isSyncingDebtBook;
    final iconColor = isSyncing
        ? AppTheme.warning
        : hasPending
        ? AppTheme.warning
        : AppTheme.success;
    final backgroundColor = isSyncing
        ? AppTheme.warning.withValues(alpha: 0.16)
        : hasPending
        ? AppTheme.warning.withValues(alpha: 0.16)
        : AppTheme.success.withValues(alpha: 0.14);

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: IconButton(
        tooltip: l.tr('screens_offline_center_screen.054'),
        onPressed: _showSyncStatusSheet,
        icon: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: isSyncing
              ? Padding(
                  padding: const EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                )
              : Icon(
                  Icons.check_rounded,
                  color: iconColor,
                  size: 20,
                ),
        ),
      ),
    );
  }

  Future<void> _showSyncStatusSheet() async {
    final status = (_isSyncingCards || _isSyncingQueue || _isSyncingDebtBook)
        ? context.loc.tr('screens_offline_center_screen.055')
        : (_pendingCount > 0 || _debtPendingCount > 0)
        ? context.loc.tr('screens_offline_center_screen.056')
        : context.loc.tr('screens_offline_center_screen.057');
    final l = context.loc;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.tr('screens_offline_center_screen.054'), style: AppTheme.h3),
              const SizedBox(height: 14),
              _detailRow(l.tr('screens_offline_center_screen.058'), status),
              _detailRow(
                l.tr('screens_offline_center_screen.059'),
                _formatSyncTimestamp(_lastOfflineSyncAt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSyncTimestamp(String? raw) {
    final date = raw == null ? null : DateTime.tryParse(raw);
    if (date == null) {
      return context.loc.tr('screens_offline_center_screen.060');
    }
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
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
