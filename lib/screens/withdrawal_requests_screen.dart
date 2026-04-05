import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class WithdrawalRequestsScreen extends StatefulWidget {
  const WithdrawalRequestsScreen({super.key});

  @override
  State<WithdrawalRequestsScreen> createState() =>
      _WithdrawalRequestsScreenState();
}

enum _StatusFilter { all, pending, approved, rejected }

class _WithdrawalRequestsScreenState extends State<WithdrawalRequestsScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  String? _busyId;
  _StatusFilter _filter = _StatusFilter.all;
  int _page = 1;
  static const int _perPage = 8;
  int _lastPage = 1;
  int _totalRequests = 0;
  Timer? _searchDebounce;

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

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final payload = await _apiService.getWithdrawalRequests(
        status: _statusQueryValue,
        query: _searchController.text,
        page: _page,
        perPage: _perPage,
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted) return;
      setState(() {
        _requests = List<Map<String, dynamic>>.from(
          (payload['requests'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _totalRequests = (pagination['total'] as num?)?.toInt() ?? _requests.length;
        _isLoading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  String? get _statusQueryValue {
    return switch (_filter) {
      _StatusFilter.all => null,
      _StatusFilter.pending => 'pending',
      _StatusFilter.approved => 'approved',
      _StatusFilter.rejected => 'rejected',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('طلبات السحب')),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              children: [
                _buildHero(),
                const SizedBox(height: 24),
                _buildFilterBar(),
                const SizedBox(height: 24),
                if (_requests.isEmpty)
                  _buildEmptyState()
                else ...[
                  ..._requests.map(_buildRequestTile),
                  const SizedBox(height: 24),
                  AdminPaginationFooter(
                    currentPage: _page,
                    lastPage: _lastPage,
                    totalItems: _totalRequests,
                    itemsPerPage: _perPage,
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

  Widget _buildHero() {
    final pending = (_summary['pending'] as num?)?.toInt() ?? 0;
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_rounded,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'متابعة طلبات السحب',
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                Text(
                  'راجع طلبات تحويل الرصيد إلى الحسابات البنكية أو المحافظ الإلكترونية قبل اعتمادها.',
                  style: AppTheme.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$pending طلب معلق',
              style: AppTheme.bodyBold.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'ابحث عن طلب...',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 350), () {
              if (!mounted) return;
              setState(() => _page = 1);
              _load();
            });
          },
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _StatusFilter.values.map((filter) {
              final isSelected = _filter == filter;
              final label = switch (filter) {
                _StatusFilter.all => 'الكل',
                _StatusFilter.pending => 'المعلقة',
                _StatusFilter.approved => 'المكتملة',
                _StatusFilter.rejected => 'المرفوضة',
              };
              return Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() {
                      _filter = filter;
                      _page = 1;
                    });
                    _load();
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
      ],
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> request) {
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
                  backgroundColor: color.withOpacity(0.1),
                  child: Icon(Icons.person_rounded, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['fullName'] ?? user['username'] ?? '-',
                        style: AppTheme.bodyBold,
                      ),
                      Text('@${user['username']}', style: AppTheme.caption),
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.ils(
                    (request['amount'] as num?)?.toDouble() ?? 0,
                  ),
                  style: AppTheme.h3.copyWith(color: AppTheme.primary),
                ),
              ],
            ),
            const Divider(height: 32),
            _infoLine('جهة التحويل', request['destinationTypeLabel'] ?? '-'),
            _infoLine('اسم المستفيد', request['accountHolderName'] ?? '-'),
            _infoLine('رقم الحساب', request['destinationAccount'] ?? '-'),
            if ((request['bankName']?.toString() ?? '').isNotEmpty)
              _infoLine('اسم البنك', request['bankName'] ?? '-'),
            if ((request['notes']?.toString() ?? '').isNotEmpty)
              _infoLine('الملاحظات', request['notes'] ?? '-'),
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
                      label: const Text('اعتماد'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busyId == request['id']
                          ? null
                          : () => _reject(request['id']?.toString() ?? ''),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('رفض'),
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

  Widget _buildStatusBadge(String status) {
    final color = switch (status) {
      'approved' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.warning,
    };
    final label = switch (status) {
      'approved' => 'تم الاعتماد',
      'rejected' => 'مرفوض',
      _ => 'قيد المراجعة',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEmptyState() {
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
          Text('لا توجد طلبات مطابقة حاليًا', style: AppTheme.h3),
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
    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.approvePendingWithdrawalRequest(requestId);
      if (!mounted) return;
      AppAlertService.showSuccess(
        context,
        message: response['message']?.toString() ?? 'تم اعتماد الطلب.',
      );
      await _load();
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(String requestId) async {
    final notesController = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: TextField(
          controller: notesController,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'سبب الرفض',
            hintText: 'اكتب ملاحظة مختصرة للمستخدم',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );

    if (approved != true) {
      notesController.dispose();
      return;
    }

    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.rejectPendingWithdrawalRequest(
        requestId,
        notes: notesController.text,
      );
      if (!mounted) return;
      AppAlertService.showSuccess(
        context,
        message: response['message']?.toString() ?? 'تم رفض الطلب.',
      );
      await _load();
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      notesController.dispose();
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _formatDate(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) return '-';
    return DateFormat('yyyy/MM/dd - HH:mm').format(parsed.toLocal());
  }
}
