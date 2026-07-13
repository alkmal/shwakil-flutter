import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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

class WithdrawalRequestsScreen extends StatefulWidget {
  const WithdrawalRequestsScreen({super.key});

  @override
  State<WithdrawalRequestsScreen> createState() =>
      _WithdrawalRequestsScreenState();
}

enum _StatusFilter { all, pending, approved, rejected }

class _WithdrawalRequestsScreenState extends State<WithdrawalRequestsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isAuthorized = false;
  String? _busyId;
  _StatusFilter _filter = _StatusFilter.all;
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
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canReviewWithdrawals) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }
      final payload = await _apiService.getWithdrawalRequests(
        status: _statusQueryValue,
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
      }
      AppAlertService.showError(
        context,
        title: _t('screens_withdrawal_requests_screen.033'),
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
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_withdrawal_requests_screen.001')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const AppSidebar(),
        body: Center(
          child: ShwakelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 54,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  l.tr('screens_withdrawal_requests_screen.033'),
                  style: AppTheme.h3,
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('screens_withdrawal_requests_screen.034'),
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
        title: Text(l.tr('screens_withdrawal_requests_screen.001')),
        actions: [const AppNotificationAction(), const QuickLogoutAction()],
      ),
      drawer: const AppSidebar(),
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
              const Icon(Icons.outbox_rounded, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.loc.tr('screens_withdrawal_requests_screen.001'),
                  style: AppTheme.bodyBold,
                ),
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
                context.loc.tr('screens_withdrawal_requests_screen.035'),
                '$_totalRequests',
              ),
              _buildOverviewChip(
                context.loc.tr('screens_withdrawal_requests_screen.036'),
                '$pendingCount',
              ),
              _buildOverviewChip(
                context.loc.tr('screens_withdrawal_requests_screen.037'),
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
            labelText: l.tr('screens_withdrawal_requests_screen.004'),
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
            children: _StatusFilter.values.map((filter) {
              final isSelected = _filter == filter;
              final label = switch (filter) {
                _StatusFilter.all => l.tr(
                  'screens_withdrawal_requests_screen.005',
                ),
                _StatusFilter.pending => l.tr(
                  'screens_withdrawal_requests_screen.006',
                ),
                _StatusFilter.approved => l.tr(
                  'screens_withdrawal_requests_screen.007',
                ),
                _StatusFilter.rejected => l.tr(
                  'screens_withdrawal_requests_screen.008',
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
            _infoLine(
              l.tr('screens_withdrawal_requests_screen.009'),
              request['destinationTypeLabel'] ?? '-',
            ),
            _infoLine(
              l.tr('screens_withdrawal_requests_screen.010'),
              request['accountHolderName'] ?? '-',
            ),
            _infoLine(
              l.tr('screens_withdrawal_requests_screen.011'),
              request['destinationAccount'] ?? '-',
            ),
            if ((request['bankName']?.toString() ?? '').isNotEmpty)
              _infoLine(
                l.tr('screens_withdrawal_requests_screen.012'),
                request['bankName'] ?? '-',
              ),
            if ((request['notes']?.toString() ?? '').isNotEmpty)
              _infoLine(
                l.tr('screens_withdrawal_requests_screen.013'),
                request['notes'] ?? '-',
              ),
            if ((request['reviewNotes']?.toString() ?? '').isNotEmpty)
              _infoLine(
                l.text('ملاحظة الإدارة', 'Admin note'),
                request['reviewNotes'] ?? '-',
              ),
            if ((request['approvalReceiptUrl']?.toString() ?? '').isNotEmpty)
              _infoLine(
                l.text('صورة الإدارة', 'Admin image'),
                l.text('مرفقة', 'Attached'),
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
                      label: Text(
                        l.tr('screens_withdrawal_requests_screen.014'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busyId == request['id']
                          ? null
                          : () => _reject(request['id']?.toString() ?? ''),
                      icon: const Icon(Icons.close_rounded),
                      label: Text(
                        l.tr('screens_withdrawal_requests_screen.015'),
                      ),
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
    final l = context.loc;
    final color = switch (status) {
      'approved' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.warning,
    };
    final label = switch (status) {
      'approved' => l.tr('screens_withdrawal_requests_screen.016'),
      'rejected' => l.tr('screens_withdrawal_requests_screen.017'),
      _ => l.tr('screens_withdrawal_requests_screen.018'),
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
          Text(
            l.tr('screens_withdrawal_requests_screen.019'),
            style: AppTheme.h3,
          ),
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
    final l = context.loc;
    final review = await _showWithdrawalReviewDialog(approve: true);
    if (review == null) {
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
      return;
    }
    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.approvePendingWithdrawalRequest(
        requestId,
        approvalImageBase64: review.imageBase64,
        notes: review.notes,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_withdrawal_requests_screen.039'),
        message:
            response['message']?.toString() ??
            l.tr('screens_withdrawal_requests_screen.020'),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_withdrawal_requests_screen.040'),
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
    final l = context.loc;
    final review = await _showWithdrawalReviewDialog(approve: false);
    if (review == null) {
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
      return;
    }

    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.rejectPendingWithdrawalRequest(
        requestId,
        notes: review.notes,
        approvalImageBase64: review.imageBase64,
        otpCode: security.otpCode,
        securityPin: security.securityPin,
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_withdrawal_requests_screen.041'),
        message:
            response['message']?.toString() ??
            l.tr('screens_withdrawal_requests_screen.025'),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_withdrawal_requests_screen.042'),
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<_WithdrawalReviewResult?> _showWithdrawalReviewDialog({
    required bool approve,
  }) async {
    return Navigator.of(context).push<_WithdrawalReviewResult>(
      MaterialPageRoute(
        builder: (_) => _WithdrawalReviewScreen(approve: approve),
      ),
    );
  }

  String _formatDate(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) {
      return '-';
    }
    return DateFormat('yyyy/MM/dd - HH:mm').format(parsed.toLocal());
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

class _WithdrawalReviewResult {
  const _WithdrawalReviewResult({
    required this.notes,
    required this.imageBase64,
  });

  final String notes;
  final String imageBase64;
}

class _WithdrawalReviewScreen extends StatefulWidget {
  const _WithdrawalReviewScreen({required this.approve});

  final bool approve;

  @override
  State<_WithdrawalReviewScreen> createState() =>
      _WithdrawalReviewScreenState();
}

class _WithdrawalReviewScreenState extends State<_WithdrawalReviewScreen> {
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
      setState(
        () => _errorText = l.tr('screens_withdrawal_requests_screen.027'),
      );
      return;
    }
    if (!widget.approve && notes.isEmpty) {
      setState(
        () => _errorText = l.text(
          'اكتب سبب الرفض قبل المتابعة.',
          'Write the rejection reason before continuing.',
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _WithdrawalReviewResult(notes: notes, imageBase64: _imageBase64),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final title = widget.approve
        ? l.text('اعتماد طلب السحب', 'Approve withdrawal request')
        : l.text('رفض طلب السحب', 'Reject withdrawal request');

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
                  TextField(
                    controller: _notesController,
                    autofocus: !widget.approve,
                    minLines: 4,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: widget.approve
                          ? l.text('ملاحظة للمستخدم', 'Note for the user')
                          : l.tr('screens_withdrawal_requests_screen.022'),
                      hintText: l.tr('screens_withdrawal_requests_screen.028'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: Icon(
                      _imageBase64.isEmpty
                          ? Icons.attach_file_rounded
                          : Icons.check_circle_rounded,
                    ),
                    label: Text(
                      _imageBase64.isEmpty
                          ? l.text('إرفاق صورة', 'Attach image')
                          : l.text('تم إرفاق الصورة', 'Image attached'),
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
                                ? l.tr('screens_withdrawal_requests_screen.014')
                                : l.tr(
                                    'screens_withdrawal_requests_screen.024',
                                  ),
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
