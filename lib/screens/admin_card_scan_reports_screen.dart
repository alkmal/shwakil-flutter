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

class _AdminCardScanReportsScreenState
    extends State<AdminCardScanReportsScreen> {
  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();
  final TextEditingController _attendanceQueryC = TextEditingController();
  final TextEditingController _attendanceFromC = TextEditingController();
  final TextEditingController _attendanceToC = TextEditingController();

  bool _loading = true;
  bool _authorized = false;
  bool _attendanceMode = false;
  bool _exporting = false;
  int _page = 1;
  int _perPage = 12;
  int _pages = 1;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _attendanceSummary = const {};

  @override
  void dispose() {
    _attendanceQueryC.dispose();
    _attendanceFromC.dispose();
    _attendanceToC.dispose();
    super.dispose();
  }

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
      final payload = _attendanceMode
          ? await _api.getAdminAttendanceCardReports(
              page: targetPage,
              perPage: 25,
              from: _attendanceFromC.text,
              to: _attendanceToC.text,
              query: _attendanceQueryC.text,
            )
          : await _api.getAdminCardScanReportUsers(
              scope: 'private',
              page: targetPage,
              perPage: _perPage,
            );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      final attendanceSummary = Map<String, dynamic>.from(
        payload['summary'] as Map? ?? const {},
      );
      final items = List<Map<String, dynamic>>.from(
        (payload['items'] as List? ?? const []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      if (!mounted) return;
      setState(() {
        _authorized = true;
        _page = targetPage;
        _perPage = (pagination['perPage'] as num?)?.toInt() ?? _perPage;
        _pages = (pagination['pages'] as num?)?.toInt() ?? 1;
        _items = items;
        _attendanceSummary = _attendanceMode ? attendanceSummary : const {};
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

  Future<void> _setMode(bool attendanceMode) async {
    if (_attendanceMode == attendanceMode) return;
    setState(() {
      _attendanceMode = attendanceMode;
      _page = 1;
      _items = const [];
    });
    await _load(page: 1);
  }

  Future<void> _exportAttendance() async {
    if (_items.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final exportItems = <Map<String, dynamic>>[];
      final totalPages = _pages.clamp(1, 100);
      for (var page = 1; page <= totalPages; page++) {
        final payload = await _api.getAdminAttendanceCardReports(
          page: page,
          perPage: 100,
          from: _attendanceFromC.text,
          to: _attendanceToC.text,
          query: _attendanceQueryC.text,
        );
        final pageItems = List<Map<String, dynamic>>.from(
          (payload['items'] as List? ?? const []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        if (pageItems.isEmpty) break;
        exportItems.addAll(pageItems);
      }
      await _api.exportAttendanceCardReportsCsv(items: exportItems);
      if (!mounted) return;
      AppAlertService.showSnack(
        context,
        message:
            'تم تصدير ${exportItems.length} سجل من تقرير الحضور والانصراف.',
      );
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: 'تعذر التصدير',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportAttendanceDailySummary() async {
    final daily = _attendanceDailySummaries;
    if (daily.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      await _api.exportAttendanceDailySummaryCsv(items: daily);
      if (!mounted) return;
      AppAlertService.showSnack(
        context,
        message: 'تم تصدير ${daily.length} سجل من الملخص اليومي.',
      );
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: 'تعذر تصدير الملخص',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<Map<String, dynamic>> get _attendanceDailySummaries =>
      List<Map<String, dynamic>>.from(
        (_attendanceSummary['dailySummaries'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

  Future<void> _pickAttendanceDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    controller.text = picked.toIso8601String().split('T').first;
    await _load(page: 1);
  }

  void _clearAttendanceFilters() {
    _attendanceQueryC.clear();
    _attendanceFromC.clear();
    _attendanceToC.clear();
    _load(page: 1);
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
              _attendanceMode
                  ? 'تقارير الحضور والانصراف'
                  : 'تقارير فحص البطاقات (خاصة)',
              style: AppTheme.h2,
            ),
            const SizedBox(height: 6),
            Text(
              _attendanceMode
                  ? 'سجل قراءات بطاقات الحضور والانصراف مع بيانات الموظف ومكان القراءة.'
                  : 'ترتيب حسب أكثر قراءة. اضغط على المستخدم لعرض تفاصيل المواقع.',
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.query_stats_rounded),
                      label: Text('الفحص'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.badge_rounded),
                      label: Text('الحضور'),
                    ),
                  ],
                  selected: {_attendanceMode},
                  onSelectionChanged: (value) => _setMode(value.first),
                ),
                if (_attendanceMode)
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _attendanceQueryC,
                      decoration: const InputDecoration(
                        labelText: 'بحث',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _load(page: 1),
                    ),
                  ),
                if (_attendanceMode)
                  SizedBox(
                    width: 170,
                    child: TextField(
                      controller: _attendanceFromC,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'من تاريخ',
                        prefixIcon: Icon(Icons.date_range_rounded),
                        isDense: true,
                      ),
                      onTap: () => _pickAttendanceDate(_attendanceFromC),
                    ),
                  ),
                if (_attendanceMode)
                  SizedBox(
                    width: 170,
                    child: TextField(
                      controller: _attendanceToC,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'إلى تاريخ',
                        prefixIcon: Icon(Icons.event_available_rounded),
                        isDense: true,
                      ),
                      onTap: () => _pickAttendanceDate(_attendanceToC),
                    ),
                  ),
                if (_attendanceMode)
                  IconButton.filledTonal(
                    tooltip: 'تطبيق الفلاتر',
                    onPressed: () => _load(page: 1),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                if (_attendanceMode)
                  IconButton.outlined(
                    tooltip: 'مسح الفلاتر',
                    onPressed: _clearAttendanceFilters,
                    icon: const Icon(Icons.filter_alt_off_rounded),
                  ),
                if (_attendanceMode)
                  OutlinedButton.icon(
                    onPressed: _items.isEmpty || _exporting
                        ? null
                        : _exportAttendance,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(_exporting ? 'جاري التصدير' : 'تصدير CSV'),
                  ),
                if (_attendanceMode)
                  OutlinedButton.icon(
                    onPressed: _attendanceDailySummaries.isEmpty || _exporting
                        ? null
                        : _exportAttendanceDailySummary,
                    icon: const Icon(Icons.summarize_rounded),
                    label: const Text('تصدير الملخص'),
                  ),
              ],
            ),
            if (_attendanceMode) ...[
              const SizedBox(height: 12),
              _buildAttendanceSummary(),
              const SizedBox(height: 12),
              _buildAttendanceDailySummaries(),
            ],
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
                    if (_attendanceMode) {
                      return _buildAttendanceItem(item);
                    }

                    final user = Map<String, dynamic>.from(
                      item['user'] as Map? ?? const {},
                    );
                    final displayName = UserDisplayName.fromMap(user);
                    final scanCount = (item['scanCount'] as num?)?.toInt() ?? 0;
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

  Widget _buildAttendanceSummary() {
    final total =
        (_attendanceSummary['total'] as num?)?.toInt() ?? _items.length;
    final checkIns = (_attendanceSummary['checkIns'] as num?)?.toInt() ?? 0;
    final checkOuts = (_attendanceSummary['checkOuts'] as num?)?.toInt() ?? 0;
    final employeeCount =
        (_attendanceSummary['employeeCount'] as num?)?.toInt() ?? 0;
    final systemCount =
        (_attendanceSummary['systemCount'] as num?)?.toInt() ?? 0;
    final dailyCount = (_attendanceSummary['dailyCount'] as num?)?.toInt() ?? 0;
    final completeDays =
        (_attendanceSummary['completeDays'] as num?)?.toInt() ?? 0;
    final incompleteDays =
        (_attendanceSummary['incompleteDays'] as num?)?.toInt() ?? 0;
    final truncated = _attendanceSummary['truncated'] == true;

    return ShwakelCard(
      padding: const EdgeInsets.all(14),
      color: AppTheme.surfaceElevated,
      borderColor: AppTheme.success.withValues(alpha: 0.12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          _metricChip(
            label: truncated ? 'الإجمالي+' : 'الإجمالي',
            value: '$total',
            color: AppTheme.primary,
          ),
          _metricChip(
            label: 'حضور',
            value: '$checkIns',
            color: AppTheme.success,
          ),
          _metricChip(
            label: 'انصراف',
            value: '$checkOuts',
            color: AppTheme.accent,
          ),
          _metricChip(
            label: 'موظفون',
            value: '$employeeCount',
            color: AppTheme.warning,
          ),
          _metricChip(
            label: 'أنظمة',
            value: '$systemCount',
            color: AppTheme.info,
          ),
          _metricChip(
            label: 'أيام',
            value: '$dailyCount',
            color: AppTheme.primary,
          ),
          _metricChip(
            label: 'مكتملة',
            value: '$completeDays',
            color: AppTheme.success,
          ),
          _metricChip(
            label: 'ناقصة',
            value: '$incompleteDays',
            color: AppTheme.warning,
          ),
          _metricChip(
            label: 'هذه الصفحة',
            value: '${_items.length}',
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceDailySummaries() {
    final daily = _attendanceDailySummaries.take(8).toList();
    if (daily.isEmpty) {
      return const SizedBox.shrink();
    }

    return ShwakelCard(
      padding: const EdgeInsets.all(14),
      color: AppTheme.surfaceElevated,
      borderColor: AppTheme.primary.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ملخص يومي مختصر', style: AppTheme.bodyBold),
          const SizedBox(height: 10),
          ...daily.map((item) {
            final complete = item['status'] == 'complete';
            final workedMinutes = (item['workedMinutes'] as num?)?.toInt();
            final duration = workedMinutes == null
                ? 'غير مكتمل'
                : '${workedMinutes ~/ 60}س ${workedMinutes % 60}د';
            final employee = item['employeeName']?.toString().trim() ?? '';
            final code = item['employeeCode']?.toString().trim() ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (complete ? AppTheme.success : AppTheme.warning)
                        .withValues(alpha: 0.12),
                  ),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _metricChip(
                      label: 'اليوم',
                      value: item['date']?.toString() ?? '',
                      color: AppTheme.primary,
                    ),
                    _metricChip(
                      label: 'الموظف',
                      value: [
                        if (employee.isNotEmpty) employee,
                        if (code.isNotEmpty) code,
                      ].join(' - '),
                      color: AppTheme.info,
                    ),
                    _metricChip(
                      label: 'الحضور',
                      value: item['firstCheckInAt']?.toString() ?? '-',
                      color: AppTheme.success,
                    ),
                    _metricChip(
                      label: 'الانصراف',
                      value: item['lastCheckOutAt']?.toString() ?? '-',
                      color: AppTheme.accent,
                    ),
                    _metricChip(
                      label: 'المدة',
                      value: duration,
                      color: complete ? AppTheme.success : AppTheme.warning,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAttendanceItem(Map<String, dynamic> item) {
    final employeeName = item['employeeName']?.toString().trim() ?? '';
    final employeeCode = item['employeeCode']?.toString().trim() ?? '';
    final department = item['department']?.toString().trim() ?? '';
    final system = item['attendanceSystem']?.toString().trim() ?? '';
    final barcode = item['barcode']?.toString() ?? '';
    final scanner = item['scannerName']?.toString().trim() ?? '';
    final createdAt = item['createdAt']?.toString() ?? '';
    final location = item['locationKey']?.toString() ?? 'غير متوفر';
    final action = Map<String, dynamic>.from(
      item['attendanceAction'] as Map? ?? const {},
    );
    final actionLabel = action['label']?.toString() ?? 'قراءة حضور';
    final isCheckOut = action['action'] == 'check_out';
    final actionColor = isCheckOut ? AppTheme.accent : AppTheme.success;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        padding: const EdgeInsets.all(16),
        color: AppTheme.surfaceElevated,
        borderColor: actionColor.withValues(alpha: 0.14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isCheckOut ? Icons.logout_rounded : Icons.login_rounded,
                color: actionColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employeeName.isEmpty ? 'موظف غير مسمى' : employeeName,
                    style: AppTheme.bodyBold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (employeeCode.isNotEmpty) 'كود: $employeeCode',
                      if (department.isNotEmpty) department,
                      if (system.isNotEmpty) system,
                    ].join(' · '),
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _metricChip(
                        label: 'الحركة',
                        value: actionLabel,
                        color: actionColor,
                      ),
                      _metricChip(
                        label: 'البطاقة',
                        value: barcode,
                        color: AppTheme.primary,
                      ),
                      _metricChip(
                        label: 'القارئ',
                        value: scanner.isEmpty ? '-' : scanner,
                        color: AppTheme.accent,
                      ),
                      _metricChip(
                        label: 'الموقع',
                        value: location,
                        color: AppTheme.warning,
                      ),
                      _metricChip(
                        label: 'الوقت',
                        value: createdAt,
                        color: AppTheme.success,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
        (payload['items'] as List? ?? const []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
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
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final scanCount = (item['scanCount'] as num?)?.toInt() ?? 0;
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
                              _chip(
                                'استخدام',
                                '$redeemCount',
                                AppTheme.success,
                              ),
                              _chip(
                                'بدون استخدام',
                                '$scanWithoutUse',
                                AppTheme.warning,
                              ),
                              _chip(
                                'نسبة الاستخدام',
                                '${ratio.toStringAsFixed(2)}%',
                                AppTheme.accent,
                              ),
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
