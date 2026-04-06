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
        title: 'تعذر تحميل الطلبات',
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
          title: 'تعذر تحديث الطلب',
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('طلبات طباعة البطاقات')),
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
                        'إدارة طلبات طباعة البطاقات',
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'هذا المسار مستقل بالكامل لمراجعة الطلبات ثم اعتمادها ثم بدء الطباعة ثم تجهيزها ثم إكمالها.',
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AdminSectionHeader(
                  title: 'متابعة الطلبات',
                  subtitle: 'فلترة وبحث ثم متابعة كل طلب حسب مرحلته الحالية.',
                  icon: Icons.print_rounded,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'بحث بالاسم أو الرقم أو رقم الطلب',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onSubmitted: (_) {
                          _page = 1;
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'الحالة'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('الكل')),
                          DropdownMenuItem(
                            value: 'pending_review',
                            child: Text('بانتظار المراجعة'),
                          ),
                          DropdownMenuItem(
                            value: 'approved',
                            child: Text('تمت الموافقة'),
                          ),
                          DropdownMenuItem(
                            value: 'printing',
                            child: Text('قيد الطباعة'),
                          ),
                          DropdownMenuItem(
                            value: 'ready',
                            child: Text('جاهز للتسليم'),
                          ),
                          DropdownMenuItem(
                            value: 'completed',
                            child: Text('مكتمل'),
                          ),
                          DropdownMenuItem(
                            value: 'rejected',
                            child: Text('مرفوض'),
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
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryChip(
                      'مراجعة',
                      (_summary['pendingReviewCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      'معتمد',
                      (_summary['approvedCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      'طباعة',
                      (_summary['printingCount'] as num?)?.toInt() ?? 0,
                    ),
                    _summaryChip(
                      'جاهز',
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
                        'لا توجد طلبات مطابقة حاليًا.',
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
                            : (request['username']?.toString() ?? 'عميل'),
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
                _metaItem('الطلب', request['id']?.toString() ?? '-'),
                _metaItem('النوع', request['cardType'] == 'single_use' ? 'مرة واحدة' : 'عادية'),
                _metaItem('العدد', '${request['quantity'] ?? 0} بطاقة'),
                _metaItem(
                  'القيمة',
                  CurrencyFormatter.ils(
                    (request['cardValue'] as num?)?.toDouble() ?? 0,
                  ),
                ),
                _metaItem(
                  'الإجمالي',
                  CurrencyFormatter.ils(
                    (request['totalAmount'] as num?)?.toDouble() ?? 0,
                  ),
                ),
              ],
            ),
            if ((request['customerNotes']?.toString().trim().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('ملاحظات العميل: ${request['customerNotes']}'),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (status == 'pending_review')
                  _actionButton('موافقة', busy, () => _handleAction(request, 'approve')),
                if (status == 'pending_review')
                  _actionButton('رفض', busy, () => _handleAction(request, 'reject')),
                if (status == 'approved')
                  _actionButton('بدء الطباعة', busy, () => _handleAction(request, 'start')),
                if (status == 'printing')
                  _actionButton('جاهز للتسليم', busy, () => _handleAction(request, 'ready')),
                if (status == 'ready')
                  _actionButton('إكمال الطلب', busy, () => _handleAction(request, 'complete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, bool busy, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: busy ? null : onPressed,
      child: Text(busy ? 'جارٍ المعالجة...' : label),
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
