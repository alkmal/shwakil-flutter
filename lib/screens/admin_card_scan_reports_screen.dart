import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/user_display_name.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminCardScanReportsScreen extends StatefulWidget {
  const AdminCardScanReportsScreen({super.key});

  @override
  State<AdminCardScanReportsScreen> createState() =>
      _AdminCardScanReportsScreenState();
}

class _AdminCardScanReportsScreenState extends State<AdminCardScanReportsScreen> {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();

  bool _loading = true;
  bool _authorized = false;
  int _page = 1;
  int _perPage = 12;
  int _pages = 1;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    final targetPage = page ?? _page;
    setState(() {
      _loading = true;
    });
    final user = AuthService.peekCurrentUser() ?? await _auth.currentUser();
    final perms = AppPermissions.fromUser(user);
    final authorized = perms.hasAdminWorkspaceAccess && perms.canManageUsers;
    if (!authorized) {
      if (!mounted) return;
      setState(() {
        _authorized = false;
        _loading = false;
      });
      return;
    }

    try {
      final payload = await _api.getAdminCardScanReportUsers(
        scope: 'private',
        page: targetPage,
        perPage: _perPage,
      );
      final pagination =
          Map<String, dynamic>.from(payload['pagination'] as Map? ?? const {});
      final items = List<Map<String, dynamic>>.from(
        (payload['items'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      if (!mounted) return;
      setState(() {
        _authorized = true;
        _page = targetPage;
        _perPage = (pagination['perPage'] as num?)?.toInt() ?? _perPage;
        _pages = (pagination['pages'] as num?)?.toInt() ?? 1;
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authorized = true;
        _loading = false;
      });
      rethrow;
    }
  }

  Future<void> _openUserLocations(Map<String, dynamic> item) async {
    final user = Map<String, dynamic>.from(item['user'] as Map? ?? const {});
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      builder: (ctx) => _UserLocationsSheet(userId: userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_authorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            'لا تملك صلاحية عرض هذه الصفحة',
            style: AppTheme.bodyBold,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: const [AppNotificationAction()],
      ),
      drawer: const AppSidebar(),
      body: ResponsiveScaffoldContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            Text(
              'تقارير فحص البطاقات (خاصة)',
              style: AppTheme.h2,
            ),
            const SizedBox(height: 6),
            Text(
              'ترتيب حسب أكثر قراءة. اضغط على المستخدم لعرض تفاصيل المواقع.',
              style: AppTheme.bodyAction.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(page: _page),
                child: ListView.builder(
                  itemCount: _items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _items.length) {
                      return AdminPaginationFooter(
                        currentPage: _page,
                        totalPages: _pages,
                        onPageChanged: (p) => _load(page: p),
                      );
                    }

                    final item = _items[index];
                    final user = Map<String, dynamic>.from(
                      item['user'] as Map? ?? const {},
                    );
                    final displayName = UserDisplayName.fromMap(user);
                    final scanCount =
                        (item['scanCount'] as num?)?.toInt() ?? 0;
                    final redeemCount =
                        (item['redeemCount'] as num?)?.toInt() ?? 0;
                    final scanWithoutUse =
                        (item['scanWithoutUse'] as num?)?.toInt() ?? 0;
                    final ratio =
                        (item['redeemRatioPercent'] as num?)?.toDouble() ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ShwakelCard(
                        onTap: () => _openUserLocations(item),
                        padding: const EdgeInsets.all(16),
                        color: AppTheme.surfaceElevated,
                        borderColor: AppTheme.primary.withValues(alpha: 0.10),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.bodyBold,
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    children: [
                                      _metricChip(
                                        label: 'قراءات',
                                        value: '$scanCount',
                                        color: AppTheme.primary,
                                      ),
                                      _metricChip(
                                        label: 'استخدام',
                                        value: '$redeemCount',
                                        color: AppTheme.success,
                                      ),
                                      _metricChip(
                                        label: 'بدون استخدام',
                                        value: '$scanWithoutUse',
                                        color: AppTheme.warning,
                                      ),
                                      _metricChip(
                                        label: 'نسبة الاستخدام',
                                        value: '${ratio.toStringAsFixed(2)}%',
                                        color: AppTheme.accent,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              l.isArabic
                                  ? Icons.arrow_back_rounded
                                  : Icons.arrow_forward_rounded,
                              color: AppTheme.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Text(
        '$label: $value',
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _UserLocationsSheet extends StatefulWidget {
  final String userId;

  const _UserLocationsSheet({required this.userId});

  @override
  State<_UserLocationsSheet> createState() => _UserLocationsSheetState();
}

class _UserLocationsSheetState extends State<_UserLocationsSheet> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await _api.getAdminCardScanReportUserLocations(
        widget.userId,
        scope: 'private',
      );
      final items = List<Map<String, dynamic>>.from(
        (payload['items'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorMessageService.sanitize(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تعذر تحميل التفاصيل', style: AppTheme.h3),
              const SizedBox(height: 10),
              Text(_error!, style: AppTheme.bodyAction),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تفاصيل المواقع', style: AppTheme.h3),
            const SizedBox(height: 6),
            Text(
              'يعرض أكثر الأماكن التي حصل فيها فحص بدون استخدام/مع استخدام.',
              style: AppTheme.bodyAction.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final scanCount =
                      (item['scanCount'] as num?)?.toInt() ?? 0;
                  final redeemCount =
                      (item['redeemCount'] as num?)?.toInt() ?? 0;
                  final scanWithoutUse =
                      (item['scanWithoutUse'] as num?)?.toInt() ?? 0;
                  final ratio =
                      (item['redeemRatioPercent'] as num?)?.toDouble() ?? 0;
                  final locationKey = item['locationKey']?.toString() ?? '-';
                  final lat = (item['latitude'] as num?)?.toDouble();
                  final lng = (item['longitude'] as num?)?.toDouble();
                  final coords = (lat != null && lng != null)
                      ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                      : 'غير متوفر';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ShwakelCard(
                      padding: const EdgeInsets.all(14),
                      color: AppTheme.surfaceElevated,
                      borderColor: AppTheme.primary.withValues(alpha: 0.10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            locationKey,
                            style: AppTheme.bodyBold,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            coords,
                            style: AppTheme.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            children: [
                              _chip('قراءات', '$scanCount', AppTheme.primary),
                              _chip('استخدام', '$redeemCount', AppTheme.success),
                              _chip('بدون استخدام', '$scanWithoutUse',
                                  AppTheme.warning),
                              _chip('نسبة الاستخدام', '${ratio.toStringAsFixed(2)}%',
                                  AppTheme.accent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Text(
        '$label: $value',
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
