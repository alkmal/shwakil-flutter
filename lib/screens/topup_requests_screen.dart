import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class TopupRequestsScreen extends StatefulWidget {
  const TopupRequestsScreen({super.key});

  @override
  State<TopupRequestsScreen> createState() => _TopupRequestsScreenState();
}

enum _TopupStatusFilter { all, pending, approved, rejected }

class _TopupRequestsScreenState extends State<TopupRequestsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  bool _isAuthorized = false;
  String? _busyId;
  _TopupStatusFilter _filter = _TopupStatusFilter.all;
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
      final user = await _authService.currentUser();
      final role = user?['role']?.toString() ?? '';
      final isAdmin = role == 'admin' || user?['id']?.toString() == '1';
      if (!isAdmin) {
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
        query: _searchController.text,
        page: _page,
        perPage: _perPage,
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted) {
        return;
      }
      final requests = List<Map<String, dynamic>>.from(
        (payload['requests'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      setState(() {
        _isAuthorized = true;
        _requests = requests;
        _summary = {
          'pending': requests
              .where((item) => item['status']?.toString() == 'pending')
              .length,
        };
        _lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _totalRequests =
            (pagination['total'] as num?)?.toInt() ?? _requests.length;
        _isLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppAlertService.showError(
          context,
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
        appBar: AppBar(title: Text(l.tr('screens_topup_requests_screen.001'))),
        drawer: const AppSidebar(),
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
                  l.text(
                    'هذه الشاشة مخصصة لعضوية الإدارة فقط.',
                    'This screen is available for administrators only.',
                  ),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l.tr('screens_topup_requests_screen.002'))),
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
    final l = context.loc;
    final pending = (_summary['pending'] as num?)?.toInt() ?? 0;
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 760;
          final iconBox = Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.add_card_rounded,
              color: Colors.white,
              size: 34,
            ),
          );
          final content = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.text('مراجعة طلبات شحن الرصيد', 'Review top-up requests'),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  l.text(
                    'راجع بيانات الحوالة وطريقة الدفع قبل اعتماد الشحن للمستخدم أو رفض الطلب.',
                    'Review transfer details and payment method before approving or rejecting the top-up request.',
                  ),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          );
          final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l.tr(
                'screens_topup_requests_screen.003',
                params: {'pending': '$pending'},
              ),
              style: AppTheme.bodyBold.copyWith(color: Colors.white),
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [iconBox, const SizedBox(width: 16), badge]),
                const SizedBox(height: 18),
                content,
              ],
            );
          }

          return Row(
            children: [iconBox, const SizedBox(width: 24), content, badge],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar() {
    final l = context.loc;
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: l.text(
              'ابحث باسم المستخدم أو رقم المرجع...',
              'Search by username or reference number...',
            ),
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 350), () {
              if (!mounted) {
                return;
              }
              setState(() => _page = 1);
              _load();
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
                        user['fullName'] ?? user['username'] ?? '-',
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

  Future<String?> _pickApprovalImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) {
      return null;
    }
    final extension = (result?.files.single.extension ?? 'png').toLowerCase();
    final mimeType = extension == 'jpg' || extension == 'jpeg'
        ? 'image/jpeg'
        : 'image/png';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Future<void> _approve(String requestId) async {
    final l = context.loc;
    final approvalImage = await _pickApprovalImage();
    if (approvalImage == null || approvalImage.isEmpty) {
      if (mounted) {
        AppAlertService.showError(
          context,
          message: l.text(
            'يجب إرفاق صورة إثبات قبل اعتماد طلب شحن الرصيد.',
            'A proof image is required before approving the top-up request.',
          ),
        );
      }
      return;
    }
    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.approvePendingTopupRequest(
        requestId,
        approvalImageBase64: approvalImage,
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        message:
            response['message']?.toString() ??
            l.text(
              'تم اعتماد طلب شحن الرصيد.',
              'The top-up request has been approved.',
            ),
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
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _reject(String requestId) async {
    final l = context.loc;
    final notesController = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.tr('screens_topup_requests_screen.020')),
        content: TextField(
          controller: notesController,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: l.tr('screens_topup_requests_screen.021'),
            hintText: l.text(
              'اكتب ملاحظة مختصرة للمستخدم',
              'Write a short note for the user',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.tr('screens_topup_requests_screen.022')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.tr('screens_topup_requests_screen.023')),
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
      final response = await _apiService.rejectPendingTopupRequest(
        requestId,
        notes: notesController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        message:
            response['message']?.toString() ??
            l.tr('screens_topup_requests_screen.024'),
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
}
