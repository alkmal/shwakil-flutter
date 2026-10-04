import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class TopupRequestsScreen extends StatefulWidget {
  const TopupRequestsScreen({super.key});

  @override
  State<TopupRequestsScreen> createState() => _TopupRequestsScreenState();
}

enum _TopupStatusFilter { all, pending, approved, rejected }
enum _AccountingFilter { all, unreviewed, settled }

class _TopupRequestsScreenState extends State<TopupRequestsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isAuthorized = false;
  bool _isPrincipalAdmin = false;
  String? _busyId;
  _TopupStatusFilter _filter = _TopupStatusFilter.all;
  _AccountingFilter _accountingFilter = _AccountingFilter.all;
  int _page = 1;
  static const int _perPage = 8;
  int _lastPage = 1;
  int _totalRequests = 0;
  Timer? _searchDebounce;
  int _loadRequestId = 0;
  String _lastSubmittedQuery = '';

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool preserveContent = false}) async {
    final requestId = ++_loadRequestId;
    final shouldKeepVisible = preserveContent && _requests.isNotEmpty;
    setState(() {
      if (shouldKeepVisible) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });
    final requestedPage = _page;
    try {
      try {
        await _authService.tryRefreshCurrentUser();
      } catch (_) {}
      final user = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(user);
      _isPrincipalAdmin = (user?['role']?.toString().toLowerCase() == 'admin');
      if (!permissions.canReviewTopups) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }

      final payload = await _apiService.getTopupRequests(
        status: _statusQueryValue,
        accountingStatus: _accountingStatusQueryValue,
        query: _searchController.text.trim(),
        page: requestedPage,
        perPage: _perPage,
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      final requests = List<Map<String, dynamic>>.from(
        (payload['requests'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
      final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? 1;
      final normalizedPage = currentPage.clamp(1, lastPage);

      if (requestedPage > lastPage && lastPage > 0) {
        if (!mounted) {
          return;
        }
        setState(() => _page = lastPage);
        await _load();
        return;
      }
      setState(() {
        _isAuthorized = true;
        _requests = requests;
        _page = normalizedPage;
        _lastPage = lastPage;
        _totalRequests =
            (pagination['total'] as num?)?.toInt() ?? _requests.length;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        AppAlertService.showError(
          context,
          title: _t('screens_topup_requests_screen.036'),
          message: ErrorMessageService.sanitize(error),
        );
      }
    }
  }

  String? get _statusQueryValue {
    return switch (_filter) {
      _TopupStatusFilter.all => null,
      _TopupStatusFilter.pending => 'pending',
      _TopupStatusFilter.approved => 'approved',
      _TopupStatusFilter.rejected => 'rejected',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_topup_requests_screen.001')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: AppSidebar.drawerFor(context),
        body: Center(
          child: ShwakelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.admin_panel_settings_rounded,
                  size: 54,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  l.tr('screens_topup_requests_screen.036'),
                  style: AppTheme.h3,
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('screens_topup_requests_screen.037'),
                  style: AppTheme.bodyAction,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_topup_requests_screen.002')),
        actions: [const AppNotificationAction(), const QuickLogoutAction()],
      ),
      drawer: AppSidebar.drawerFor(context),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _requests.isEmpty ? 2 : _requests.length + 2,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildRequestsHeader();
              }
              if (_requests.isEmpty) {
                return _buildEmptyState();
              }
              final requestIndex = index - 1;
              if (requestIndex < _requests.length) {
                return _buildRequestTile(_requests[requestIndex]);
              }
              return AdminPaginationFooter(
                currentPage: _page,
                lastPage: _lastPage,
                totalItems: _totalRequests,
                itemsPerPage: _perPage,
                onPageChanged: (page) {
                  setState(() => _page = page);
                  _load();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard() {
    final pendingCount = _requests
        .where((item) => item['status']?.toString() == 'pending')
        .length;
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.add_card_rounded, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.loc.tr('screens_topup_requests_screen.002'),
                  style: AppTheme.bodyBold,
                ),
              ),
              IconButton(
                tooltip: 'تقارير التحويلات',
                onPressed: _showTransferReport,
                icon: const Icon(Icons.bar_chart_rounded),
              ),
              IconButton(
                tooltip: 'تصدير التقرير',
                onPressed: _exportTransferReport,
                icon: const Icon(Icons.download_rounded),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_totalRequests',
                  style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildOverviewChip(
                context.loc.tr('screens_topup_requests_screen.038'),
                '$_totalRequests',
              ),
              _buildOverviewChip(
                context.loc.tr('screens_topup_requests_screen.039'),
                '$pendingCount',
              ),
              _buildOverviewChip(
                context.loc.tr('screens_topup_requests_screen.040'),
                '$_page / $_lastPage',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: AppTheme.caption.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildRequestsHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isRefreshing) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 12),
        ],
        _buildOverviewCard(),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
          ),
          child: _buildFilterBar(),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    final l = context.loc;
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: l.tr('screens_topup_requests_screen.028'),
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 550), () {
              if (!mounted) {
                return;
              }
              _submitSearch();
            });
          },
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _TopupStatusFilter.values.map((filter) {
              final isSelected = _filter == filter;
              final label = switch (filter) {
                _TopupStatusFilter.all => l.tr(
                  'screens_topup_requests_screen.004',
                ),
                _TopupStatusFilter.pending => l.tr(
                  'screens_topup_requests_screen.005',
                ),
                _TopupStatusFilter.approved => l.tr(
                  'screens_topup_requests_screen.006',
                ),
                _TopupStatusFilter.rejected => l.tr(
                  'screens_topup_requests_screen.007',
                ),
              };
              return Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _filter = filter;
                      _page = 1;
                    });
                    _load(preserveContent: true);
                  },
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            children: _AccountingFilter.values.map((filter) {
              final selected = _accountingFilter == filter;
              final label = switch (filter) {
                _AccountingFilter.all => 'كل المحاسبة',
                _AccountingFilter.unreviewed => 'غير مراجعة',
                _AccountingFilter.settled => 'تمت المحاسبة',
              };
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) {
                  setState(() { _accountingFilter = filter; _page = 1; });
                  _load(preserveContent: true);
                },
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> request) {
    final l = context.loc;
    final user = Map<String, dynamic>.from(request['user'] as Map? ?? const {});
    final isPending = request['status'] == 'pending';
    final color = isPending
        ? AppTheme.warning
        : (request['status'] == 'approved' ? AppTheme.success : AppTheme.error);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ShwakelCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.1),
                  child: Icon(Icons.person_rounded, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UserDisplayName.fromMap(user, fallback: '-'),
                        style: AppTheme.bodyBold,
                      ),
                      Text(
                        '@${user['username'] ?? '-'}',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.ils(
                    (request['amount'] as num?)?.toDouble() ?? 0,
                  ),
                  style: AppTheme.h3.copyWith(color: AppTheme.primary),
                ),
                if (_isPrincipalAdmin && request['status'] != 'approved')
                  IconButton(
                    tooltip: 'حذف السجل',
                    onPressed: _busyId == request['id']
                        ? null
                        : () => _deleteRequest(request['id']?.toString() ?? ''),
                    icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                  ),
              ],
            ),
            const Divider(height: 32),
            _infoLine(
              l.tr('screens_topup_requests_screen.008'),
              request['paymentMethodTitle']?.toString() ?? '-',
            ),
            _infoLine(
              l.tr('screens_topup_requests_screen.009'),
              request['paymentMethodNumber']?.toString() ?? '-',
            ),
            _infoLine(
              l.tr('screens_topup_requests_screen.010'),
              request['senderName']?.toString().isNotEmpty == true
                  ? request['senderName'].toString()
                  : '-',
            ),
            _infoLine(
              l.tr('screens_topup_requests_screen.011'),
              request['senderPhone']?.toString().isNotEmpty == true
                  ? request['senderPhone'].toString()
                  : '-',
            ),
            _infoLine(
              l.tr('screens_topup_requests_screen.012'),
              request['transferReference']?.toString().isNotEmpty == true
                  ? request['transferReference'].toString()
                  : '-',
            ),
            if ((request['notes']?.toString() ?? '').isNotEmpty)
              _infoLine(
                l.tr('screens_topup_requests_screen.013'),
                request['notes']?.toString() ?? '-',
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatusBadge(request['status']?.toString() ?? ''),
                const Spacer(),
                Text(
                  _formatDate(request['createdAt']?.toString()),
                  style: AppTheme.caption,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: request['followUpChecked'] == true,
                    onChanged: _busyId == request['id']
                        ? null
                        : (value) => _updateFollowUp(
                              request,
                              checked: value ?? false,
                              deliveryStatus: request['deliveryStatus']?.toString() ?? 'unknown',
                            ),
                  ),
                  const Expanded(child: Text('تمت مراجعة وصول التحويل')),
                  PopupMenuButton<String>(
                    initialValue: request['deliveryStatus']?.toString() ?? 'unknown',
                    onSelected: (value) => _updateFollowUp(
                      request,
                      checked: request['followUpChecked'] == true,
                      deliveryStatus: value,
                    ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'received', child: Text('وصلت')),
                      PopupMenuItem(value: 'not_received', child: Text('لم تصل')),
                      PopupMenuItem(value: 'unknown', child: Text('غير محدد')),
                    ],
                    child: Text(switch (request['deliveryStatus']?.toString()) {
                      'received' => 'وصلت',
                      'not_received' => 'لم تصل',
                      _ => 'حالة الوصول',
                    }),
                  ),
                ],
              ),
            ),
            if (_isPrincipalAdmin) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('الربح: ${CurrencyFormatter.ils((request['profitAmount'] as num?)?.toDouble() ?? 0)} (${(request['profitRate'] as num?)?.toStringAsFixed(2) ?? '0'}%)')),
                TextButton.icon(
                  onPressed: request['accountingStatus'] == 'settled' || _busyId == request['id'] ? null : () => _settleAccounting(request),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(request['accountingStatus'] == 'settled' ? 'تمت المحاسبة' : 'تأكيد المحاسبة'),
                ),
              ]),
            ],
            if (isPending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _busyId == request['id']
                          ? null
                          : () => _approve(request['id']?.toString() ?? ''),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(l.tr('screens_topup_requests_screen.014')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busyId == request['id']
                          ? null
                          : () => _reject(request['id']?.toString() ?? ''),
                      icon: const Icon(Icons.close_rounded),
                      label: Text(l.tr('screens_topup_requests_screen.015')),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferReport() async {
    Map<String, dynamic> report;
    try {
      report = await _apiService.getTopupRequestsReport();
    } catch (error) {
      if (mounted) AppAlertService.showError(context, title: 'تعذر تحميل التقرير', message: ErrorMessageService.sanitize(error));
      return;
    }
    if (!mounted) return;
    var selectedPeriod = 'day';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) {
        final totals = Map<String, dynamic>.from(report['totals'] as Map? ?? const {});
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          title: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.bar_chart_rounded, color: AppTheme.primary)),
            const SizedBox(width: 12),
            const Expanded(child: Text('تقرير التحويلات والمحاسبة')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<String>(
              initialValue: selectedPeriod,
              decoration: const InputDecoration(labelText: 'نوع التقرير'),
              items: const [
                DropdownMenuItem(value: 'day', child: Text('يومي')),
                DropdownMenuItem(value: 'week', child: Text('أسبوعي')),
                DropdownMenuItem(value: 'month', child: Text('شهري')),
              ],
              onChanged: (value) async {
                if (value == null) return;
                selectedPeriod = value;
                try {
                  report = await _apiService.getTopupRequestsReport(period: selectedPeriod);
                  setDialogState(() {});
                } catch (_) {}
              },
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _reportMetric('التحويلات', '${totals['transfers'] ?? 0}', AppTheme.primary),
              _reportMetric('القيم', CurrencyFormatter.ils((totals['amount'] as num?)?.toDouble() ?? 0), AppTheme.info),
              _reportMetric('الأرباح', CurrencyFormatter.ils((totals['profit'] as num?)?.toDouble() ?? 0), AppTheme.success),
              _reportMetric('غير مراجعة', '${totals['unreviewed'] ?? 0}', AppTheme.warning),
              _reportMetric('تمت المحاسبة', '${totals['settled'] ?? 0}', AppTheme.success),
            ]),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إغلاق'))],
        );
      }),
    );
  }

  Future<void> _exportTransferReport() async {
    try {
      final report = await _apiService.getTopupRequestsReport(period: 'day');
      final rows = List<Map<String, dynamic>>.from((report['rows'] as List? ?? const []).map((item) => Map<String, dynamic>.from(item as Map)));
      final buffer = StringBuffer('\uFEFFالفترة,الموظف,عدد التحويلات,إجمالي القيم,إجمالي الأرباح,غير مراجعة,تمت المحاسبة\n');
      for (final row in rows) {
        final values = [row['period'], row['employeeName'], row['transfers'], row['totalAmount'], row['totalProfit'], row['unreviewed'], row['settled']];
        buffer.writeln(values.map((value) => '"${(value ?? '').toString().replaceAll('"', '""')}"').join(','));
      }
      await FileSaver.instance.saveFile(name: 'shwakel_transfer_report_${DateTime.now().toIso8601String().substring(0, 10)}', bytes: Uint8List.fromList(utf8.encode(buffer.toString())), fileExtension: 'csv', mimeType: MimeType.csv);
      if (mounted) AppAlertService.showSuccess(context, title: 'تم التصدير', message: 'تم حفظ تقرير التحويلات بصيغة CSV.');
    } catch (error) {
      if (mounted) AppAlertService.showError(context, title: 'تعذر التصدير', message: ErrorMessageService.sanitize(error));
    }
  }

  Widget _reportMetric(String label, String value, Color color) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: .18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTheme.caption.copyWith(color: AppTheme.textSecondary)),
        const SizedBox(height: 5),
        Text(value, style: AppTheme.bodyBold.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  String? get _accountingStatusQueryValue => switch (_accountingFilter) {
    _AccountingFilter.all => null,
    _AccountingFilter.unreviewed => 'unreviewed',
    _AccountingFilter.settled => 'settled',
  };

  Future<void> _settleAccounting(Map<String, dynamic> request) async {
    final id = request['id']?.toString() ?? '';
    if (id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    try {
      final amount = (request['amount'] as num?)?.toDouble() ?? 0;
      final rate = (request['profitRate'] as num?)?.toDouble() ?? 0;
      final profit = (request['profitAmount'] as num?)?.toDouble() ?? amount * rate / 100;
      await _apiService.updateTopupFollowUp(requestId: id, deliveryStatus: request['deliveryStatus']?.toString() ?? 'unknown', checked: request['followUpChecked'] == true, accountingStatus: 'settled', profitRate: rate, profitAmount: profit);
      if (mounted) { setState(() { request['accountingStatus'] = 'settled'; request['profitAmount'] = profit; }); AppAlertService.showSuccess(context, title: 'تمت المحاسبة', message: 'تم اعتماد مستحقات الموظف.'); }
    } catch (error) { if (mounted) AppAlertService.showError(context, title: 'تعذر الحفظ', message: ErrorMessageService.sanitize(error)); }
    finally { if (mounted) setState(() => _busyId = null); }
  }

  Future<void> _deleteRequest(String id) async {
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف سجل التحويل؟'),
        content: const Text('سيتم حذف السجل غير المعتمد نهائيًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true || _busyId != null) return;
    setState(() => _busyId = id);
    try {
      await _apiService.deleteTopupRequest(id);
      if (mounted) { AppAlertService.showSuccess(context, title: 'تم الحذف', message: 'تم حذف السجل.'); await _load(); }
    } catch (error) {
      if (mounted) AppAlertService.showError(context, title: 'تعذر الحذف', message: ErrorMessageService.sanitize(error));
    } finally { if (mounted) setState(() => _busyId = null); }
  }

  Future<void> _updateFollowUp(
    Map<String, dynamic> request, {
    required bool checked,
    required String deliveryStatus,
  }) async {
    final id = request['id']?.toString() ?? '';
    if (id.isEmpty || _busyId != null) return;
    setState(() => _busyId = id);
    try {
      await _apiService.updateTopupFollowUp(
        requestId: id,
        deliveryStatus: deliveryStatus,
        checked: checked,
      );
      if (!mounted) return;
      setState(() {
        request['followUpChecked'] = checked;
        request['deliveryStatus'] = deliveryStatus;
      });
      AppAlertService.showSuccess(context, title: 'تم التحديث', message: 'تم حفظ متابعة وصول التحويل.');
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(context, title: 'تعذر التحديث', message: ErrorMessageService.sanitize(error));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Widget _buildStatusBadge(String status) {
    final l = context.loc;
    final color = switch (status) {
      'approved' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.warning,
    };
    final label = switch (status) {
      'approved' => l.tr('screens_topup_requests_screen.016'),
      'rejected' => l.tr('screens_topup_requests_screen.017'),
      _ => l.tr('screens_topup_requests_screen.018'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(
            Icons.inbox_rounded,
            size: 56,
            color: AppTheme.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(l.tr('screens_topup_requests_screen.019'), style: AppTheme.h3),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: AppTheme.bodyText)),
        ],
      ),
    );
  }

  Future<void> _approve(String requestId) async {
    if (_busyId != null || requestId.isEmpty) return;
    final l = context.loc;
    setState(() => _busyId = requestId);
    final review = await Navigator.of(context).push<_TopupReviewResult>(
      MaterialPageRoute(
        builder: (_) => const _TopupReviewScreen(approve: true),
      ),
    );
    if (review == null) {
      if (mounted) setState(() => _busyId = null);
      return;
    }
    if (!mounted) {
      return;
    }
    final security = await TransferSecurityService.confirmTransfer(
      context,
      allowOtpFallback: true,
    );
    if (!mounted || !security.isVerified) {
      if (mounted) setState(() => _busyId = null);
      return;
    }
    try {
      final response = await _apiService.approvePendingTopupRequest(
        requestId,
        approvalImageBase64: review.imageBase64,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
        localAuthMethod: security.method,
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_topup_requests_screen.042'),
        message:
            response['message']?.toString() ??
            l.tr('screens_topup_requests_screen.030'),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_topup_requests_screen.043'),
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _reject(String requestId) async {
    if (_busyId != null || requestId.isEmpty) return;
    final l = context.loc;
    setState(() => _busyId = requestId);
    final review = await Navigator.of(context).push<_TopupReviewResult>(
      MaterialPageRoute(
        builder: (_) => const _TopupReviewScreen(approve: false),
      ),
    );

    if (review == null) {
      if (mounted) setState(() => _busyId = null);
      return;
    }
    if (!mounted) return;

    try {
      final response = await _apiService.rejectPendingTopupRequest(
        requestId,
        notes: review.notes,
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_topup_requests_screen.044'),
        message:
            response['message']?.toString() ??
            l.tr('screens_topup_requests_screen.024'),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_topup_requests_screen.045'),
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    return DateFormat('yyyy/MM/dd - hh:mm a').format(parsed.toLocal());
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query == _lastSubmittedQuery) {
      return;
    }
    _lastSubmittedQuery = query;
    setState(() => _page = 1);
    _load(preserveContent: true);
  }
}

class _TopupReviewResult {
  const _TopupReviewResult({required this.notes, required this.imageBase64});

  final String notes;
  final String imageBase64;
}

class _TopupReviewScreen extends StatefulWidget {
  const _TopupReviewScreen({required this.approve});

  final bool approve;

  @override
  State<_TopupReviewScreen> createState() => _TopupReviewScreenState();
}

class _TopupReviewScreenState extends State<_TopupReviewScreen> {
  final TextEditingController _notesController = TextEditingController();
  String _imageBase64 = '';
  String _errorText = '';

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) {
      return;
    }
    final extension = (result?.files.single.extension ?? 'png').toLowerCase();
    final mimeType = extension == 'jpg' || extension == 'jpeg'
        ? 'image/jpeg'
        : 'image/png';
    setState(() {
      _imageBase64 = 'data:$mimeType;base64,${base64Encode(bytes)}';
      _errorText = '';
    });
  }

  void _submit() {
    final l = context.loc;
    final notes = _notesController.text.trim();
    if (widget.approve && _imageBase64.isEmpty) {
      setState(() => _errorText = l.tr('screens_topup_requests_screen.029'));
      return;
    }
    if (!widget.approve && notes.isEmpty) {
      setState(() => _errorText = l.tr('screens_topup_requests_screen.031'));
      return;
    }
    Navigator.pop(
      context,
      _TopupReviewResult(notes: notes, imageBase64: _imageBase64),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final title = widget.approve
        ? l.tr('screens_topup_requests_screen.014')
        : l.tr('screens_topup_requests_screen.020');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
      ),
      body: ResponsiveScaffoldContainer(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: ListView(
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.approve
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: widget.approve
                            ? AppTheme.success
                            : AppTheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(title, style: AppTheme.h3)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (widget.approve)
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: Icon(
                        _imageBase64.isEmpty
                            ? Icons.attach_file_rounded
                            : Icons.check_circle_rounded,
                      ),
                      label: Text(
                        _imageBase64.isEmpty
                            ? l.text(
                                'إرفاق صورة الاعتماد',
                                'Attach approval image',
                              )
                            : l.text('تم إرفاق الصورة', 'Image attached'),
                      ),
                    )
                  else
                    TextField(
                      controller: _notesController,
                      minLines: 4,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_topup_requests_screen.021'),
                        hintText: l.tr('screens_topup_requests_screen.031'),
                      ),
                    ),
                  if (_errorText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorText,
                      style: AppTheme.caption.copyWith(color: AppTheme.error),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l.tr('shared.cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _submit,
                          icon: Icon(
                            widget.approve
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                          ),
                          label: Text(
                            widget.approve
                                ? l.tr('screens_topup_requests_screen.014')
                                : l.tr('screens_topup_requests_screen.023'),
                          ),
                        ),
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
