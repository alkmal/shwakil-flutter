import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class IssuedCardUsageReportScreen extends StatefulWidget {
  const IssuedCardUsageReportScreen({super.key});

  @override
  State<IssuedCardUsageReportScreen> createState() =>
      _IssuedCardUsageReportScreenState();
}

class _IssuedCardUsageReportScreenState
    extends State<IssuedCardUsageReportScreen> {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final TextEditingController _queryC = TextEditingController();
  final TextEditingController _fromC = TextEditingController();
  final TextEditingController _toC = TextEditingController();

  bool _loading = true;
  bool _authorized = false;
  String _scope = 'all';
  int _page = 1;
  int _lastPage = 1;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _items = const [];
  StateSetter? _toolsSetState;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _toolsSetState = null;
    _queryC.dispose();
    _fromC.dispose();
    _toC.dispose();
    super.dispose();
  }

  Future<void> _load({int? page}) async {
    final user = AuthService.peekCurrentUser() ?? await _auth.currentUser();
    final permissions = AppPermissions.fromUser(user);
    final authorized =
        permissions.canIssueCards ||
        permissions.canRequestCardPrinting ||
        permissions.canViewInventory;
    if (!authorized) {
      if (!mounted) return;
      setState(() {
        _authorized = false;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    final targetPage = page ?? _page;
    final payload = await _api.getMyIssuedCardUsageReport(
      scope: _scope,
      from: _fromC.text,
      to: _toC.text,
      query: _queryC.text,
      page: targetPage,
      perPage: 20,
    );
    final pagination = Map<String, dynamic>.from(
      payload['pagination'] as Map? ?? const {},
    );
    if (!mounted) return;
    setState(() {
      _authorized = true;
      _summary = Map<String, dynamic>.from(
        payload['summary'] as Map? ?? const {},
      );
      _items = List<Map<String, dynamic>>.from(
        (payload['items'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      _page = (pagination['currentPage'] as num?)?.toInt() ?? targetPage;
      _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.text('تقارير استخدام البطاقات', 'Card usage reports')),
        actions: [
          IconButton(
            tooltip: l.text('أدوات التقرير', 'Report tools'),
            onPressed: _authorized ? _openReportTools : null,
            icon: const Icon(Icons.tune_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: () => _load(page: 1),
        child: ResponsiveScaffoldContainer(
          useSafeArea: false,
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: !_authorized && !_loading
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [_unauthorized()],
                )
              : _loading
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                )
              : _items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [_emptyState()],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _items.length + 1,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index < _items.length) {
                      return _row(_items[index]);
                    }
                    return _pagination();
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _openReportTools() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            _toolsSetState = setSheetState;
            return DraggableScrollableSheet(
              initialChildSize: 0.78,
              minChildSize: 0.44,
              maxChildSize: 0.94,
              expand: false,
              builder: (context, scrollController) {
                return DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(AppTheme.spacingLg),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppTheme.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _headerCard(),
                      const SizedBox(height: 14),
                      _filtersCard(),
                      const SizedBox(height: 14),
                      _summaryGrid(),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    _toolsSetState = null;
  }

  Widget _unauthorized() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Text(
        'لا تملك صلاحية عرض تقارير استخدام البطاقات.',
        style: AppTheme.bodyBold,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _headerCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        colors: [AppTheme.secondary, AppTheme.primary],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'استخدام البطاقات',
            style: AppTheme.h2.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'تابع الحالة والاستخدام بسرعة.',
            style: AppTheme.bodyAction.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _filtersCard() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(22),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: _scope,
              decoration: InputDecoration(labelText: l.text('النطاق', 'Scope')),
              items: [
                DropdownMenuItem(value: 'all', child: Text(l.text('كل البطاقات', 'All cards'))),
                DropdownMenuItem(value: 'private', child: Text(l.text('الخاصة', 'Private'))),
                DropdownMenuItem(value: 'public', child: Text(l.text('العامة', 'Public'))),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _scope = value);
                _toolsSetState?.call(() {});
              },
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _fromC,
              decoration: InputDecoration(labelText: l.text('من تاريخ', 'From date')),
              keyboardType: TextInputType.datetime,
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _toC,
              decoration: const InputDecoration(labelText: 'إلى تاريخ'),
              keyboardType: TextInputType.datetime,
            ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _queryC,
              decoration: const InputDecoration(
                labelText: 'بحث',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: (_) => _load(page: 1),
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).maybePop();
              _load(page: 1);
            },
            icon: const Icon(Icons.filter_alt_rounded),
            label: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _metric(
          'إجمالي البطاقات',
          _int('totalCards'),
          Icons.credit_card_rounded,
        ),
        _metric('المستخدمة', _int('usedCards'), Icons.task_alt_rounded),
        _metric('المستخدمة اليوم', _int('usedToday'), Icons.today_rounded),
        _metric('الخاصة', _int('privateCards'), Icons.lock_rounded),
        _metric('العامة', _int('publicCards'), Icons.public_rounded),
        _metric(
          'قيمة مستخدمة',
          CurrencyFormatter.ils(
            (_summary['usedAmount'] as num?)?.toDouble() ?? 0,
          ),
          Icons.payments_rounded,
          isText: true,
        ),
      ],
    );
  }

  String _int(String key) => '${(_summary[key] as num?)?.toInt() ?? 0}';

  Widget _metric(
    String label,
    String value,
    IconData icon, {
    bool isText = false,
  }) {
    return SizedBox(
      width: 190,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTheme.caption),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: isText
                        ? AppTheme.bodyBold.copyWith(fontSize: 13)
                        : AppTheme.h3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Text(
        'لا توجد بطاقات ضمن الفلتر الحالي.',
        style: AppTheme.bodyAction,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _row(Map<String, dynamic> card) {
    final isUsed = card['status']?.toString() == 'used';
    final isPrivate = card['visibilityScope']?.toString() == 'restricted';
    final usedBy =
        (card['redeemedByDisplayName'] ??
                card['redeemedByUsername'] ??
                'غير مستخدمة')
            .toString();
    final usedAt = card['redeemedAt']?.toString() ?? '-';
    final barcode = card['barcode']?.toString() ?? '';
    final value = (card['value'] as num?)?.toDouble() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ShwakelCard(
        padding: const EdgeInsets.all(14),
        color: isUsed
            ? AppTheme.success.withValues(alpha: 0.06)
            : AppTheme.surface,
        borderColor: isUsed
            ? AppTheme.success.withValues(alpha: 0.18)
            : AppTheme.border,
        child: Row(
          children: [
            Icon(
              isUsed ? Icons.check_circle_rounded : Icons.schedule_rounded,
              color: isUsed ? AppTheme.success : AppTheme.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isPrivate ? 'بطاقة خاصة' : 'بطاقة عامة'} - $barcode',
                    style: AppTheme.bodyBold,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isUsed ? '$usedBy - $usedAt' : 'لم تستخدم بعد',
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (value > 0)
              Text(CurrencyFormatter.ils(value), style: AppTheme.bodyBold),
          ],
        ),
      ),
    );
  }

  Widget _pagination() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _page <= 1 ? null : () => _load(page: _page - 1),
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('السابق'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text('$_page / $_lastPage', style: AppTheme.bodyBold),
        ),
        OutlinedButton.icon(
          onPressed: _page >= _lastPage ? null : () => _load(page: _page + 1),
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('التالي'),
        ),
      ],
    );
  }
}
