import 'dart:async';

import 'package:flutter/material.dart';

import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final TextEditingController _search = TextEditingController();

  List<VirtualCard> _subscriptions = const [];
  bool _loading = true;
  bool _authorized = false;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final user = await _auth.currentUser();
      final permissions = AppPermissions.fromUser(user);
      if (!permissions.canManageSubscriptions) {
        if (mounted) {
          setState(() {
            _authorized = false;
            _loading = false;
          });
        }
        return;
      }
      final payload = await _api.getMyCards(page: 1, perPage: 100);
      final cards =
          List<VirtualCard>.from(
            payload['cards'] as List? ?? const <VirtualCard>[],
          ).where((card) => card.isSubscription).toList()..sort((a, b) {
            final aDate = a.validUntil ?? DateTime(9999);
            final bDate = b.validUntil ?? DateTime(9999);
            return aDate.compareTo(bDate);
          });
      if (!mounted) return;
      setState(() {
        _authorized = true;
        _subscriptions = cards;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorMessageService.sanitize(error);
      });
    }
  }

  bool _isExpired(VirtualCard card) {
    final end = card.validUntil;
    return end != null && end.isBefore(DateTime.now());
  }

  bool _isExpiringSoon(VirtualCard card) {
    final end = card.validUntil;
    if (end == null || _isExpired(card)) return false;
    return end.isBefore(DateTime.now().add(const Duration(days: 30)));
  }

  List<VirtualCard> get _visibleSubscriptions {
    final query = _search.text.trim().toLowerCase();
    return _subscriptions
        .where((card) {
          final matchesFilter = switch (_filter) {
            'active' => !_isExpired(card),
            'expiring' => _isExpiringSoon(card),
            'expired' => _isExpired(card),
            _ => true,
          };
          if (!matchesFilter) return false;
          if (query.isEmpty) return true;
          return [
            card.subscriptionName,
            card.customerName,
            card.barcode,
            card.allowedPhoneNumbers.join(' '),
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  void _createSubscription() {
    Navigator.pushNamed(
      context,
      '/create-card',
      arguments: const {'cardType': 'subscription'},
    ).then((_) => _load());
  }

  Future<void> _renew(VirtualCard card) async {
    var days = 30;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.loc.text('تجديد الاشتراك', 'Renew subscription'),
                  style: AppTheme.h2,
                ),
                const SizedBox(height: 6),
                Text(
                  card.subscriptionName ??
                      context.loc.text('اشتراك', 'Subscription'),
                  style: AppTheme.bodyAction,
                ),
                const SizedBox(height: 18),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 30,
                      label: Text(context.loc.text('شهر', '1 month')),
                    ),
                    ButtonSegment(
                      value: 90,
                      label: Text(context.loc.text('3 أشهر', '3 months')),
                    ),
                    ButtonSegment(
                      value: 365,
                      label: Text(context.loc.text('سنة', '1 year')),
                    ),
                  ],
                  selected: {days},
                  onSelectionChanged: (value) =>
                      setSheetState(() => days = value.first),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.autorenew_rounded),
                  label: Text(context.loc.text('متابعة التجديد', 'Continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) return;
    try {
      await _api.renewSubscriptionCard(
        cardId: card.id,
        durationDays: days,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
        localAuthMethod: security.method,
      );
      await _load();
      if (!mounted) return;
      await AppAlertService.showSuccess(
        context,
        title: context.loc.text('تم التجديد', 'Subscription renewed'),
        message: context.loc.text(
          'تم تحديث مدة الاشتراك بنجاح.',
          'The subscription period was updated successfully.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: context.loc.text('تعذر التجديد', 'Renewal failed'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      drawer: AppSidebar.drawerFor(context, currentRouteName: '/subscriptions'),
      appBar: AppBar(
        title: Text(l.text('إدارة الاشتراكات', 'Subscriptions')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: l.text('تحديث', 'Refresh'),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      floatingActionButton: _authorized
          ? FloatingActionButton.extended(
              onPressed: _createSubscription,
              icon: const Icon(Icons.add_rounded),
              label: Text(l.text('اشتراك جديد', 'New subscription')),
            )
          : null,
      body: ResponsiveScaffoldContainer(
        padding: AppTheme.pagePadding(context, top: 12),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_authorized
            ? Center(child: Text(l.text('لا تملك الصلاحية.', 'No access.')))
            : _error != null
            ? _errorView()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _summary(),
                    const SizedBox(height: 14),
                    _filters(),
                    const SizedBox(height: 14),
                    if (_visibleSubscriptions.isEmpty)
                      _emptyState()
                    else
                      ..._visibleSubscriptions.map(_subscriptionCard),
                    const SizedBox(height: 88),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summary() {
    final active = _subscriptions.where((card) => !_isExpired(card)).length;
    final expiring = _subscriptions.where(_isExpiringSoon).length;
    final expired = _subscriptions.where(_isExpired).length;
    final items = [
      (context.loc.text('نشط', 'Active'), '$active', Icons.verified_rounded),
      (
        context.loc.text('قريب الانتهاء', 'Expiring'),
        '$expiring',
        Icons.schedule_rounded,
      ),
      (
        context.loc.text('منتهي', 'Expired'),
        '$expired',
        Icons.event_busy_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: constraints.maxWidth < 700 ? 3 : 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: constraints.maxWidth < 420 ? 96 : 108,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return ShwakelCard(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.$3, color: AppTheme.primary, size: 24),
                const SizedBox(height: 6),
                Text(item.$2, style: AppTheme.h3),
                Text(
                  item.$1,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filters() => ShwakelCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: context.loc.text(
              'بحث بالاسم أو المشترك أو الرقم',
              'Search name, subscriber or number',
            ),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('all', context.loc.text('الكل', 'All')),
              _filterChip('active', context.loc.text('النشطة', 'Active')),
              _filterChip(
                'expiring',
                context.loc.text('قريبة الانتهاء', 'Expiring'),
              ),
              _filterChip('expired', context.loc.text('المنتهية', 'Expired')),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filterChip(String value, String label) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: ChoiceChip(
      selected: _filter == value,
      label: Text(label),
      onSelected: (_) => setState(() => _filter = value),
    ),
  );

  Widget _subscriptionCard(VirtualCard card) {
    final expired = _isExpired(card);
    final expiring = _isExpiringSoon(card);
    final color = expired
        ? AppTheme.error
        : expiring
        ? AppTheme.warning
        : AppTheme.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ShwakelCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.event_repeat_rounded, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.subscriptionName ??
                        context.loc.text('اشتراك', 'Subscription'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyBold,
                  ),
                  if ((card.customerName ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(card.customerName!, style: AppTheme.caption),
                  ],
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _statusPill(
                        expired
                            ? context.loc.text('منتهي', 'Expired')
                            : expiring
                            ? context.loc.text('قريب الانتهاء', 'Expiring')
                            : context.loc.text('نشط', 'Active'),
                        color,
                      ),
                      if (card.validUntil != null)
                        _statusPill(_date(card.validUntil!), AppTheme.primary),
                      if (card.value > 0)
                        _statusPill(
                          CurrencyFormatter.ils(card.value),
                          AppTheme.secondary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () => _renew(card),
              tooltip: context.loc.text('تجديد', 'Renew'),
              icon: const Icon(Icons.autorenew_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: AppTheme.caption.copyWith(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _emptyState() => ShwakelCard(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
    child: Column(
      children: [
        const Icon(
          Icons.event_repeat_rounded,
          size: 46,
          color: AppTheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          context.loc.text('لا توجد اشتراكات مطابقة', 'No subscriptions found'),
          style: AppTheme.h3,
        ),
        const SizedBox(height: 8),
        Text(
          context.loc.text(
            'أنشئ اشتراكًا للجيم أو الإنترنت أو الكهرباء أو أي خدمة دورية.',
            'Create a gym, internet, electricity or recurring service plan.',
          ),
          textAlign: TextAlign.center,
          style: AppTheme.bodyAction,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _createSubscription,
          icon: const Icon(Icons.add_rounded),
          label: Text(context.loc.text('إنشاء اشتراك', 'Create subscription')),
        ),
      ],
    ),
  );

  Widget _errorView() => Center(
    child: ShwakelCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error),
          const SizedBox(height: 10),
          Text(_error ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.loc.text('إعادة المحاولة', 'Retry')),
          ),
        ],
      ),
    ),
  );

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
