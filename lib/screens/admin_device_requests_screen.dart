import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_device_request_card.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminDeviceRequestsScreen extends StatefulWidget {
  const AdminDeviceRequestsScreen({super.key});

  @override
  State<AdminDeviceRequestsScreen> createState() =>
      _AdminDeviceRequestsScreenState();
}

class _AdminDeviceRequestsScreenState extends State<AdminDeviceRequestsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _requests = const [];
  bool _isLoading = true;
  bool _isAuthorized = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canReviewDevices) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }
      final data = await _apiService.getPendingDeviceAccessRequests();
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
        title: context.loc.tr(
          'screens_admin_device_requests_screen.load_error_title',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _handle(Map<String, dynamic> request, bool approve) async {
    setState(() => _busyId = request['id']?.toString());
    try {
      await _apiService.reviewDeviceAccessRequest(
        request['id'].toString(),
        approve: approve,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        await AppAlertService.showError(
          context,
          title: context.loc.tr(
            'screens_admin_device_requests_screen.update_error_title',
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_admin_device_requests_screen.001')),
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
                  l.text(
                    'لا تملك صلاحية مراجعة طلبات الأجهزة',
                    'You do not have permission to review device requests.',
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
      appBar: AppBar(
        title: Text(l.tr('screens_admin_device_requests_screen.001')),
        actions: [
          IconButton(
            tooltip: l.text('مساعدة', 'Help'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
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
                if (_requests.isEmpty)
                  ShwakelCard(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        l.tr(
                          'screens_admin_device_requests_screen.empty_state',
                        ),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  )
                else
                  ..._requests.map(
                    (request) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AdminDeviceRequestCard(
                        request: request,
                        isProcessing: _busyId == request['id']?.toString(),
                        onAction: (approve) => _handle(request, approve),
                        onTap: () {},
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.text('مساعدة سريعة', 'Quick help'),
      message: l.text(
        'تظهر هنا طلبات الوصول للأجهزة فقط. راجع البطاقة المناسبة ثم وافق أو ارفض حسب الحالة.',
        'Only device access requests appear here. Review the relevant card, then approve or reject it as needed.',
      ),
    );
  }
}
