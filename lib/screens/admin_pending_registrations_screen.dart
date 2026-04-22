import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminPendingRegistrationsScreen extends StatefulWidget {
  const AdminPendingRegistrationsScreen({super.key});

  @override
  State<AdminPendingRegistrationsScreen> createState() =>
      _AdminPendingRegistrationsScreenState();
}

class _AdminPendingRegistrationsScreenState
    extends State<AdminPendingRegistrationsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _requests = const [];
  bool _isLoading = true;
  bool _isAuthorized = false;
  String? _busyId;
  String _searchQuery = '';

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
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canManageUsers) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }

      final data = await _apiService.getPendingRegistrationRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthorized = true;
        _requests = data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: 'تعذر تحميل طلبات التسجيل',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _approve(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }
    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.approvePendingRegistrationRequest(
        requestId,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم اعتماد الطلب',
        message:
            response['message']?.toString() ??
            'تم اعتماد طلب التسجيل بنجاح.',
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر اعتماد الطلب',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: const Text(
          'سيتم حذف الطلب المعلق عند الرفض. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('رفض'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.rejectPendingRegistrationRequest(
        requestId,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: 'تم رفض الطلب',
        message:
            response['message']?.toString() ??
            'تم رفض طلب التسجيل وحذفه من المتابعة.',
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر رفض الطلب',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredRequests {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _requests;
    }
    return _requests.where((request) {
      final haystack = [
        request['fullName'],
        request['username'],
        request['whatsapp'],
        request['nationalId'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const Text('طلبات التسجيل المعلقة')),
        drawer: const AppSidebar(),
        body: Center(
          child: ShwakelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 54,
                  color: AppTheme.textTertiary,
                ),
                SizedBox(height: 14),
                Text('لا تملك صلاحية مراجعة طلبات التسجيل.'),
              ],
            ),
          ),
        ),
      );
    }

    final requests = _filteredRequests;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('طلبات التسجيل المعلقة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ResponsiveScaffoldContainer(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShwakelCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'راجع طلبات التسجيل التي أكملت خطوة التسجيل وتنتظر قرار الإدارة.',
                          style: AppTheme.bodyAction.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'بحث بالاسم أو اسم المستخدم أو الجوال',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (value) {
                            setState(() => _searchQuery = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (requests.isEmpty)
                    ShwakelCard(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text(
                          _searchQuery.trim().isEmpty
                              ? 'لا توجد طلبات تسجيل معلقة حاليًا.'
                              : 'لا توجد نتائج مطابقة للبحث.',
                          style: AppTheme.bodyAction,
                        ),
                      ),
                    )
                  else
                    ...requests.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _requestCard(request),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final requestId = request['id']?.toString() ?? '';
    final isBusy = _busyId == requestId;
    final otpVerified = (request['otpVerifiedAt']?.toString().trim().isNotEmpty ??
        false);
    final createdAt = request['createdAt']?.toString() ?? '';

    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['fullName']?.toString().trim().isNotEmpty == true
                          ? request['fullName'].toString()
                          : 'بدون اسم',
                      style: AppTheme.h3,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${request['username']?.toString() ?? '-'}',
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(
                label: otpVerified
                    ? 'جاهز للمراجعة'
                    : 'بانتظار تأكيد الواتساب',
                color: otpVerified ? AppTheme.success : AppTheme.warning,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip(Icons.call_rounded, request['whatsapp']?.toString() ?? '-'),
              if ((request['nationalId']?.toString().trim().isNotEmpty ?? false))
                _infoChip(Icons.badge_rounded, request['nationalId'].toString()),
              if (createdAt.isNotEmpty)
                _infoChip(Icons.schedule_rounded, createdAt),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : () => _reject(request),
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                  ),
                  label: const Text('رفض وحذف الطلب'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (isBusy || !otpVerified)
                      ? null
                      : () => _approve(request),
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('اعتماد وإنشاء الحساب'),
                ),
              ),
            ],
          ),
          if (!otpVerified) ...[
            const SizedBox(height: 12),
            Text(
              'لن يظهر زر الاعتماد إلا بعد أن يؤكد صاحب الطلب رمز التحقق من واتساب.',
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: AppTheme.caption),
        ],
      ),
    );
  }
}
