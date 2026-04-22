import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _notifications = const [];
  bool _isLoading = true;
  String _filter = 'all';
  int _unreadCount = 0;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  static const int _perPage = 20;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _notificationSubscription = RealtimeNotificationService.notificationsStream
        .listen((_) => _loadNotifications(silent: true));
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    final requestedPage = _page;
    try {
      final payload = await _apiService.getAppNotifications(
        filter: _filter,
        page: requestedPage,
        perPage: _perPage,
      );
      final summary = Map<String, dynamic>.from(
        payload['summary'] as Map? ?? const {},
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      final notifications = List<Map<String, dynamic>>.from(
        (payload['notifications'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
      final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? 1;
      final normalizedPage = currentPage.clamp(1, lastPage) as int;

      if (requestedPage > lastPage && lastPage > 0) {
        if (!mounted) {
          return;
        }
        setState(() => _page = lastPage);
        await _loadNotifications(silent: silent);
        return;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _notifications = notifications;
        _unreadCount = (summary['unreadCount'] as num?)?.toInt() ?? 0;
        _page = normalizedPage;
        _lastPage = lastPage;
        _total = (pagination['total'] as num?)?.toInt() ?? notifications.length;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_login_screen.002'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsAsRead();
      RealtimeNotificationService.notifyNotificationsUpdated();
      await _loadNotifications();
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_login_screen.002'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _openNotification(Map<String, dynamic> item) async {
    if (item['isRead'] != true) {
      await _apiService.markNotificationAsRead(item['id'].toString());
      RealtimeNotificationService.notifyNotificationsUpdated();
      await _loadNotifications(silent: true);
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _NotificationDetailsSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          context.loc.tr('widgets_app_top_actions.004'),
        ),
        actions: [
          IconButton(
            tooltip: context.loc.tr('screens_notifications_screen.036'),
            onPressed: _showSummarySheet,
            icon: const Icon(Icons.dashboard_customize_rounded),
          ),
          IconButton(
            tooltip: context.loc.tr('screens_inventory_screen.017'),
            onPressed: _showFiltersSheet,
            icon: const Icon(Icons.filter_alt_rounded),
          ),
          IconButton(
            tooltip: _t('screens_notifications_screen.042'),
            onPressed: _unreadCount > 0 ? _markAllAsRead : null,
            icon: const Icon(Icons.done_all_rounded),
          ),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: ResponsiveScaffoldContainer(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          child: _buildNotificationsList(),
        ),
      ),
    );
  }

  Widget _buildNotificationsList() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_notifications.isEmpty)
          _buildEmptyState()
        else ...[
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _t('screens_notifications_screen.037'),
                    style: AppTheme.bodyAction,
                  ),
                ),
                _UnreadPill(count: _unreadCount),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._notifications.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _NotificationCard(
                item: item,
                onTap: () => _openNotification(item),
              ),
            ),
          ),
          AdminPaginationFooter(
            currentPage: _page,
            lastPage: _lastPage,
            totalItems: _total,
            itemsPerPage: _perPage,
            onPageChanged: (page) {
              setState(() => _page = page);
              _loadNotifications();
            },
          ),
        ],
      ],
    );
  }

  Future<void> _showSummarySheet() async {
    final stats = _buildQuickStats();
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(
              _t('screens_notifications_screen.034'),
              style: AppTheme.h2,
            ),
            const SizedBox(height: 8),
            Text(
              _t('screens_notifications_screen.035'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ...stats.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildStatCard(item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFiltersSheet() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(
              _t('screens_notifications_screen.036'),
              style: AppTheme.h2,
            ),
            const SizedBox(height: 8),
            Text(
              _t('screens_notifications_screen.038'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildFilters(true),
          ],
        ),
      ),
    );
  }

  List<_NotificationStat> _buildQuickStats() {
    final financialCount = _notifications
        .where((item) => item['category'] == 'financial')
        .length;
    final readCount = _notifications
        .where((item) => item['isRead'] == true)
        .length;
    return [
      _NotificationStat(
        label: context.loc.tr('screens_notifications_screen.027'),
        value: '$_unreadCount',
        hint: context.loc.tr('screens_notifications_screen.028'),
        icon: Icons.mark_email_unread_rounded,
        color: AppTheme.error,
      ),
      _NotificationStat(
        label: context.loc.tr('screens_notifications_screen.029'),
        value: '$financialCount',
        hint: context.loc.tr('screens_notifications_screen.030'),
        icon: Icons.account_balance_wallet_rounded,
        color: AppTheme.primary,
      ),
      _NotificationStat(
        label: context.loc.tr('screens_notifications_screen.031'),
        value: '$readCount',
        hint: context.loc.tr('screens_notifications_screen.032'),
        icon: Icons.done_all_rounded,
        color: AppTheme.success,
      ),
    ];
  }

  Widget _buildStatCard(_NotificationStat item) {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(26),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(item.icon, color: item.color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.value,
                  style: AppTheme.h3.copyWith(color: item.color),
                ),
                const SizedBox(height: 4),
                Text(item.hint, style: AppTheme.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isCompact) {
    final chips = [
      _filterChip(_t('screens_transactions_screen.016'), 'all'),
      _filterChip(_t('screens_notifications_screen.027'), 'unread'),
      _filterChip(_t('screens_notifications_screen.029'), 'financial'),
    ];

    return ShwakelCard(
      padding: EdgeInsets.all(isCompact ? 16 : 20),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          SizedBox(
            width: isCompact ? double.infinity : 180,
            child: ShwakelButton(
              label: _t('screens_transactions_screen.011'),
              icon: Icons.refresh_rounded,
              isSecondary: true,
              onPressed: _loadNotifications,
            ),
          ),
          SizedBox(
            width: isCompact ? double.infinity : 190,
            child: ShwakelButton(
              label: _t('screens_notifications_screen.042'),
              icon: Icons.done_all_rounded,
              isSecondary: true,
              onPressed: _unreadCount > 0 ? _markAllAsRead : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = value;
          _page = 1;
        });
        _loadNotifications();
        Navigator.of(context).maybePop();
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.12),
      labelStyle: AppTheme.bodyAction.copyWith(
        color: selected ? AppTheme.primary : AppTheme.textSecondary,
        fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
      ),
    );
  }

  Widget _buildEmptyState() {
    return ShwakelCard(
      padding: const EdgeInsets.all(34),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.notifications_none_rounded,
              size: 66,
              color: AppTheme.textTertiary,
            ),
            const SizedBox(height: 18),
            Text(
              _t('screens_notifications_screen.043'),
              style: AppTheme.h3,
            ),
            const SizedBox(height: 6),
            Text(
              _t('screens_notifications_screen.044'),
              style: AppTheme.bodyText,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ShwakelButton(
              label: _t('screens_transactions_screen.011'),
              icon: Icons.refresh_rounded,
              isSecondary: true,
              onPressed: _loadNotifications,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRead = item['isRead'] == true;
    final data = Map<String, dynamic>.from(item['data'] as Map? ?? const {});
    final isFinancial = item['category'] == 'financial';
    final amount = (data['amount'] as num?)?.toDouble();
    final fee = (data['fee'] as num?)?.toDouble();

    return ShwakelCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      color: isRead ? AppTheme.surface : AppTheme.tabSurface,
      shadowLevel: isRead ? ShwakelShadowLevel.soft : ShwakelShadowLevel.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _categoryColor(isFinancial).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  isFinancial
                      ? Icons.account_balance_wallet_rounded
                      : Icons.notifications_rounded,
                  color: _categoryColor(isFinancial),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _categoryColor(
                              isFinancial,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isFinancial
                                ? context.loc.tr(
                                    'screens_notifications_screen.045',
                                  )
                                : context.loc.tr(
                                    'screens_notifications_screen.046',
                                  ),
                            style: AppTheme.caption.copyWith(
                              color: _categoryColor(isFinancial),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!isRead) const _UnreadDot(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item['title']?.toString() ?? '',
                      style: AppTheme.bodyBold.copyWith(
                        color: isRead
                            ? AppTheme.textPrimary
                            : AppTheme.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item['body']?.toString() ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyAction.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.schedule_rounded,
                label: item['createdAt']?.toString() ?? '',
              ),
              if (amount != null)
                _InfoChip(
                  icon: Icons.payments_rounded,
                  label: CurrencyFormatter.ils(amount),
                ),
              if (fee != null && fee > 0)
                _InfoChip(
                  icon: Icons.percent_rounded,
                  label: CurrencyFormatter.ils(fee),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _categoryColor(bool isFinancial) =>
      isFinancial ? AppTheme.primary : AppTheme.accent;
}

class _NotificationDetailsSheet extends StatelessWidget {
  const _NotificationDetailsSheet({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final data = Map<String, dynamic>.from(item['data'] as Map? ?? const {});
    final amount = (data['amount'] as num?)?.toDouble();
    final fee = (data['fee'] as num?)?.toDouble();
    final description = data['description']?.toString() ?? '';
    final type =
        data['transactionType']?.toString() ?? item['type']?.toString() ?? '';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['title']?.toString() ?? '', style: AppTheme.h2),
            const SizedBox(height: 10),
            Text(
              item['body']?.toString() ?? '',
              style: AppTheme.bodyText.copyWith(height: 1.6),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (type.isNotEmpty)
                  _InfoChip(icon: Icons.category_rounded, label: type),
                if (amount != null)
                  _InfoChip(
                    icon: Icons.payments_rounded,
                    label: CurrencyFormatter.ils(amount),
                  ),
                if (fee != null)
                  _InfoChip(
                    icon: Icons.percent_rounded,
                    label: CurrencyFormatter.ils(fee),
                  ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(description, style: AppTheme.bodyAction),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.loc.tr('screens_admin_customers_screen.046')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        context.loc.tr(
          'screens_notifications_screen.033',
          params: {'count': '$count'},
        ),
        style: AppTheme.bodyBold.copyWith(color: Colors.white),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: AppTheme.error,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.caption.copyWith(color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _NotificationStat {
  const _NotificationStat({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
}
