import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_device_request_card.dart';
import '../widgets/admin/admin_section_header.dart';
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
  List<Map<String, dynamic>> _requests = const [];
  bool _isLoading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getPendingDeviceAccessRequests();
      if (!mounted) {
        return;
      }
      setState(() {
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
        title: context.loc.text(
          'تعذر تحميل الطلبات',
          'Could not load requests',
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l.text('طلبات الأجهزة', 'Device Requests'))),
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
                        l.text('طلبات الأجهزة', 'Device requests'),
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.text(
                          'هذه الشاشة مخصصة فقط لمراجعة طلبات الأجهزة الجديدة بدون أي تحميل إداري إضافي.',
                          'This screen is dedicated to reviewing new device requests without loading extra admin data.',
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
                  title: l.text('الطلبات المعلقة', 'Pending requests'),
                  subtitle: l.text(
                    'وافق أو ارفض طلبات الربط من هذه الشاشة مباشرة.',
                    'Approve or reject device linking requests directly from this screen.',
                  ),
                  icon: Icons.devices_other_rounded,
                ),
                const SizedBox(height: 16),
                if (_requests.isEmpty)
                  ShwakelCard(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        l.text(
                          'لا توجد طلبات أجهزة معلقة حاليًا.',
                          'There are no pending device requests right now.',
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
}
