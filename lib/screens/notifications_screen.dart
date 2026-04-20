import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
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

  String _text(String arabic, String english) =>
      context.loc.text(arabic, english);

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

    try {
      final payload = await _apiService.getAppNotifications(
        filter: _filter,
        page: _page,
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
      if (!mounted) {
        return;
      }
      setState(() {
        _notifications = notifications;
        _unreadCount = (summary['unreadCount'] as num?)?.toInt() ?? 0;
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
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
        title: _text('\u062e\u0637\u0623', 'Error'),
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
        title: _text('\u062e\u0637\u0623', 'Error'),
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
          _text(
            '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a',
            'Notifications',
          ),
        ),
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 760;
                final quickStats = _buildQuickStats();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(isCompact),
                    const SizedBox(height: 18),
                    _buildSectionHeader(
                      title: 'ملخص الإشعارات',
                      subtitle:
                          'نظرة سريعة على عدد الرسائل وحالة القراءة وتوزيع المتابعة.',
                    ),
                    const SizedBox(height: 16),
                    if (isCompact)
                      Column(
                        children: quickStats
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildStatCard(item),
                              ),
                            )
                            .toList(),
                      )
                    else
                      Row(
                        children: quickStats
                            .map(
                              (item) => Expanded(
                                child: Padding(
                                  padding: EdgeInsetsDirectional.only(
                                    start: item == quickStats.first ? 0 : 12,
                                  ),
                                  child: _buildStatCard(item),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 18),
                    _buildSectionHeader(
                      title: 'التصفية والإجراءات',
                      subtitle:
                          'اختر نوع العرض وحدّث القائمة أو علّم الإشعارات كمقروءة.',
                    ),
                    const SizedBox(height: 16),
                    _buildFilters(isCompact),
                    const SizedBox(height: 18),
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(48),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_notifications.isEmpty)
                      _buildEmptyState()
                    else ...[
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
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(bool isCompact) {
    return ShwakelCard(
      gradient: const LinearGradient(
        colors: [Color(0xFF0C4A6E), Color(0xFF0F766E), Color(0xFF14B8A6)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      padding: EdgeInsets.all(isCompact ? 22 : 28),
      shadowLevel: ShwakelShadowLevel.premium,
      child: Flex(
        direction: isCompact ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: isCompact
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
          SizedBox(width: isCompact ? 0 : 18, height: isCompact ? 18 : 0),
          if (isCompact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'لوحة التنبيهات',
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _text(
                    '\u0645\u0631\u0643\u0632 \u0625\u0634\u0639\u0627\u0631\u0627\u062a\u0643',
                    'Your notification center',
                  ),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  _text(
                    '\u0647\u0646\u0627 \u062a\u062a\u0627\u0628\u0639 \u0643\u0644 \u0627\u0644\u062d\u0631\u0643\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629 \u0648\u0623\u064a \u062a\u0646\u0628\u064a\u0647\u0627\u062a \u062e\u0627\u0635\u0629 \u0628\u0627\u0644\u062a\u0637\u0628\u064a\u0642 \u0628\u0634\u0643\u0644 \u0645\u0631\u062a\u0628.',
                    'Track financial movements and app notifications in one organized place.',
                  ),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
              ],
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'لوحة التنبيهات',
                    style: AppTheme.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _text(
                      '\u0645\u0631\u0643\u0632 \u0625\u0634\u0639\u0627\u0631\u0627\u062a\u0643',
                      'Your notification center',
                    ),
                    style: AppTheme.h2.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _text(
                      '\u0647\u0646\u0627 \u062a\u062a\u0627\u0628\u0639 \u0643\u0644 \u0627\u0644\u062d\u0631\u0643\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629 \u0648\u0623\u064a \u062a\u0646\u0628\u064a\u0647\u0627\u062a \u062e\u0627\u0635\u0629 \u0628\u0627\u0644\u062a\u0637\u0628\u064a\u0642 \u0628\u0634\u0643\u0644 \u0645\u0631\u062a\u0628.',
                      'Track financial movements and app notifications in one organized place.',
                    ),
                    style: AppTheme.bodyAction.copyWith(
                      color: Colors.white70,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          if (!isCompact) const SizedBox(width: 16),
          if (!isCompact) _UnreadPill(count: _unreadCount),
          if (isCompact) ...[
            const SizedBox(height: 18),
            _UnreadPill(count: _unreadCount),
          ],
        ],
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
        label: 'غير مقروء',
        value: '$_unreadCount',
        hint: 'إشعارات تحتاج متابعة',
        icon: Icons.mark_email_unread_rounded,
        color: AppTheme.error,
      ),
      _NotificationStat(
        label: 'إشعارات مالية',
        value: '$financialCount',
        hint: 'حركات وتنبيهات الرصيد',
        icon: Icons.account_balance_wallet_rounded,
        color: AppTheme.primary,
      ),
      _NotificationStat(
        label: 'مقروءة',
        value: '$readCount',
        hint: 'إشعارات تم الاطلاع عليها',
        icon: Icons.done_all_rounded,
        color: AppTheme.success,
      ),
    ];
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.h2),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: AppTheme.bodyAction.copyWith(
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
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
      _filterChip(_text('\u0627\u0644\u0643\u0644', 'All'), 'all'),
      _filterChip(
        _text('\u063a\u064a\u0631 \u0645\u0642\u0631\u0648\u0621', 'Unread'),
        'unread',
      ),
      _filterChip(
        _text('\u0645\u0627\u0644\u064a\u0629', 'Financial'),
        'financial',
      ),
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
              label: _text('\u062a\u062d\u062f\u064a\u062b', 'Refresh'),
              icon: Icons.refresh_rounded,
              isSecondary: true,
              onPressed: _loadNotifications,
            ),
          ),
          SizedBox(
            width: isCompact ? double.infinity : 190,
            child: ShwakelButton(
              label: _text(
                '\u062a\u0639\u0644\u064a\u0645 \u0627\u0644\u0643\u0644 \u0643\u0645\u0642\u0631\u0648\u0621',
                'Mark all read',
              ),
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
              _text(
                '\u0644\u0627 \u062a\u0648\u062c\u062f \u0625\u0634\u0639\u0627\u0631\u0627\u062a \u062d\u0627\u0644\u064a\u0627\u064b',
                'No notifications yet',
              ),
              style: AppTheme.h3,
            ),
            const SizedBox(height: 6),
            Text(
              _text(
                '\u0633\u062a\u0638\u0647\u0631 \u0647\u0646\u0627 \u0627\u0644\u062d\u0631\u0643\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629 \u0648\u0627\u0644\u062a\u0646\u0628\u064a\u0647\u0627\u062a \u0627\u0644\u062e\u0627\u0635\u0629 \u0641\u0648\u0631 \u0648\u0635\u0648\u0644\u0647\u0627.',
                'Financial movements and custom alerts will appear here.',
              ),
              style: AppTheme.bodyText,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            ShwakelButton(
              label: _text('\u062a\u062d\u062f\u064a\u062b', 'Refresh'),
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
                            isFinancial ? 'مالي' : 'عام',
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
                child: Text(
                  context.loc.text('\u0625\u063a\u0644\u0627\u0642', 'Close'),
                ),
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
        context.loc.text(
          '\u063a\u064a\u0631 \u0645\u0642\u0631\u0648\u0621: $count',
          'Unread: $count',
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
