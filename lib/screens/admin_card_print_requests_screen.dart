import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminCardPrintRequestsScreen extends StatefulWidget {
  const AdminCardPrintRequestsScreen({super.key});

  @override
  State<AdminCardPrintRequestsScreen> createState() =>
      _AdminCardPrintRequestsScreenState();
}

class _AdminCardPrintRequestsScreenState
    extends State<AdminCardPrintRequestsScreen> {
  final ApiService _apiService = ApiService();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  String _status = 'all';
  int _page = 1;
  int _lastPage = 1;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final payload = await _apiService.getCardPrintRequests(
        status: _status,
        query: _searchController.text,
        page: _page,
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = List<Map<String, dynamic>>.from(
          payload['requests'] as List? ?? const [],
        );
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: context.loc.text(
          'تعذر تحميل الطلبات',
          'Could not load requests',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _handleAction(Map<String, dynamic> request, String action) async {
    setState(() => _busyId = request['id']?.toString());
    try {
      switch (action) {
        case 'approve':
          await _apiService.approveCardPrintRequest(request['id'].toString());
          break;
        case 'start':
          await _apiService.startCardPrintRequest(request['id'].toString());
          break;
        case 'ready':
          await _apiService.readyCardPrintRequest(request['id'].toString());
          break;
        case 'complete':
          await _apiService.completeCardPrintRequest(request['id'].toString());
          break;
        case 'reject':
          await _apiService.rejectCardPrintRequest(request['id'].toString());
          break;
      }
      await _load();
    } catch (error) {
      if (mounted) {
        await AppAlertService.showError(
          context,
          title: context.loc.text(
            'تعذر تحديث الطلب',
            'Could not update request',
          ),
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.text('طلبات طباعة البطاقات', 'Card Print Requests')),
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShwakelCard(
                  padding: const EdgeInsets.all(28),
                  gradient: AppTheme.primaryGradient,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.text(
                          'إدارة طلبات طباعة البطاقات',
                          'Manage card print requests',
                        ),
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.text(
                          'هذا المسار مستقل بالكامل لمراجعة الطلبات ثم اعتمادها ثم بدء الطباعة ثم تجهيزها ثم إكمالها.',
                          'This workflow is fully separated for reviewing, approving, printing, preparing, and completing card print requests.',
                        ),
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AdminSectionHeader(
                  title: l.text('متابعة الطلبات', 'Request tracking'),
                  subtitle: l.text(
                    'فلترة وبحث ثم متابعة كل طلب حسب مرحلته الحالية.',
                    'Filter, search, and follow each request based on its current stage.',
                  ),
                  icon: Icons.print_rounded,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 760;
                    final searchField = Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: l.text(
                            'بحث بالاسم أو الرقم أو رقم الطلب',
                            'Search by name, phone, or request number',
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                        onSubmitted: (_) {
                          _page = 1;
                          _load();
                        },
                      ),
                    );
                    final filterField = SizedBox(
                      width: stacked ? double.infinity : 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: InputDecoration(
                          labelText: l.text('الحالة', 'Status'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(l.text('الكل', 'All')),
                          ),
                          DropdownMenuItem(
                            value: 'pending_review',
                            child: Text(
                              l.text('بانتظار المراجعة', 'Pending review'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text(l.text('تمت الموافقة', 'Approved')),
                          ),
                          DropdownMenuItem(
                            value: 'printing',
                            child: Text(l.text('قيد الطباعة', 'Printing')),
                          ),
                          DropdownMenuItem(
                            value: 'ready',
                            child: Text(l.text('جاهز للتسليم', 'Ready')),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text(l.text('مكتمل', 'Completed')),
                          ),
                          DropdownMenuItem(
                            value: 'rejected',
                            child: Text(l.text('مرفوض', 'Rejected')),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _status = value;
                            _page = 1;
                          });
                          _load();
                        },
                      ),
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          Row(children: [searchField]),
                          const SizedBox(height: 12),
                          filterField,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        searchField,
                        const SizedBox(width: 12),
                        filterField,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryChip(
                      l.text('مراجعة', 'Review'),
                      (_summary['pendingReviewCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      l.text('معتمد', 'Approved'),
                      (_summary['approvedCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      l.text('طباعة', 'Printing'),
                      (_summary['printingCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      l.text('جاهز', 'Ready'),
                      (_summary['readyCount'] as num?)?.toInt() ?? 0,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_requests.isEmpty)
                  ShwakelCard(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        l.text(
                          'لا توجد طلبات مطابقة حاليًا.',
                          'No matching requests at the moment.',
                        ),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  )
                else ...[
                  ..._requests.map(_buildRequestCard),
                  const SizedBox(height: 24),
                  AdminPaginationFooter(
                    currentPage: _page,
                    lastPage: _lastPage,
                    onPageChanged: (page) {
                      setState(() => _page = page);
                      _load();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final l = context.loc;
    final status = request['status']?.toString() ?? 'pending_review';
    final busy = _busyId == request['id']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ShwakelCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['fullName']?.toString().trim().isNotEmpty == true
                            ? request['fullName'].toString()
                            : (request['username']?.toString() ??
                                  l.text('عميل', 'Customer')),
                        style: AppTheme.h3,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request['whatsapp']?.toString() ?? '',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                ),
                _statusChip(request['statusLabel']?.toString() ?? status),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metaItem(l.text('الطلب', 'Request'), request['id']?.toString() ?? '-'),
                _metaItem(
                  l.text('النوع', 'Type'),
                  request['cardType'] == 'single_use'
                      ? l.text('مرة واحدة', 'Single use')
                      : l.text('عادية', 'Regular'),
                ),
                _metaItem(
                  l.text('العدد', 'Quantity'),
                  l.text(
                    '${request['quantity'] ?? 0} بطاقة',
                    '${request['quantity'] ?? 0} cards',
                  ),
                ),
                _metaItem(
                  l.text('القيمة', 'Value'),
                  CurrencyFormatter.ils(
                    (request['cardValue'] as num?)?.toDouble() ?? 0,
                  ),
                ),
                _metaItem(
                  l.text('الإجمالي', 'Total'),
                  CurrencyFormatter.ils(
                    (request['totalAmount'] as num?)?.toDouble() ?? 0,
                  ),
                ),
              ],
            ),
            if ((request['customerNotes']?.toString().trim().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  l.text(
                    'ملاحظات العميل: ${request['customerNotes']}',
                    'Customer notes: ${request['customerNotes']}',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (status == 'pending_review')
                  _actionButton(
                    l.text('موافقة', 'Approve'),
                    busy,
                    () => _handleAction(request, 'approve'),
                  ),
                if (status == 'pending_review')
                  _actionButton(
                    l.text('رفض', 'Reject'),
                    busy,
                    () => _handleAction(request, 'reject'),
                  ),
                if (status == 'approved')
                  _actionButton(
                    l.text('بدء الطباعة', 'Start printing'),
                    busy,
                    () => _handleAction(request, 'start'),
                  ),
                if (status == 'printing')
                  _actionButton(
                    l.text('جاهز للتسليم', 'Ready for delivery'),
                    busy,
                    () => _handleAction(request, 'ready'),
                  ),
                if (status == 'ready')
                  _actionButton(
                    l.text('إكمال الطلب', 'Complete request'),
                    busy,
                    () => _handleAction(request, 'complete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, bool busy, VoidCallback onPressed) {
    final l = context.loc;
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: Text(busy ? l.text('جارٍ المعالجة...', 'Processing...') : label),
    );
  }

  Widget _summaryChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTheme.bodyAction),
          const SizedBox(width: 8),
          Text('$value', style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
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

  Widget _statusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: AppTheme.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
