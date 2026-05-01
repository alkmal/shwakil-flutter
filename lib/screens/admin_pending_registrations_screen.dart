import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/user_display_name.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/rejection_reason_dialog.dart';
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
    final l = context.loc;
    setState(() => _isLoading = true);
    try {
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canManageUsers &&
          !permissions.canManageMarketingAccounts) {
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
        title: l.tr('screens_admin_pending_registrations_screen.004'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _approve(Map<String, dynamic> request) async {
    final l = context.loc;
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }
    String deliveryMethod = 'whatsapp';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l.tr('screens_admin_pending_registrations_screen.005')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.tr('screens_admin_pending_registrations_screen.033')),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                    value: 'whatsapp',
                    icon: Icon(Icons.chat_rounded),
                    label: Text(l.tr('shared.delivery_whatsapp')),
                  ),
                  ButtonSegment<String>(
                    value: 'sms',
                    icon: Icon(Icons.sms_rounded),
                    label: Text(l.tr('shared.delivery_sms')),
                  ),
                ],
                selected: {deliveryMethod},
                onSelectionChanged: (selection) {
                  setDialogState(() => deliveryMethod = selection.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                l.tr('screens_admin_pending_registrations_screen.010'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                l.tr('screens_admin_pending_registrations_screen.030'),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.approvePendingRegistrationRequest(
        requestId,
        allowUnverifiedWhatsapp: true,
        deliveryMethod: deliveryMethod,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.005'),
        message:
            response['message']?.toString() ??
            l.tr('screens_admin_pending_registrations_screen.006'),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.007'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final l = context.loc;
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    final reason = await showRejectionReasonDialog(
      context,
      title: l.tr('screens_admin_pending_registrations_screen.008'),
      confirmText: l.tr('shared.confirm_rejection'),
    );

    if (reason == null) {
      return;
    }

    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.rejectPendingRegistrationRequest(
        requestId,
        reason: reason,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.012'),
        message:
            response['message']?.toString() ??
            l.tr('screens_admin_pending_registrations_screen.013'),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.014'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _resendOtp(Map<String, dynamic> request) async {
    final l = context.loc;
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    setState(() => _busyId = requestId);
    try {
      final result = await _authService.requestOtp(
        purpose: 'register',
        pendingRegistrationId: requestId,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.025'),
        message:
            result.message ??
            l.tr('screens_admin_pending_registrations_screen.026'),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.027'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _confirmWithoutOtp(Map<String, dynamic> request) async {
    final l = context.loc;
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_admin_pending_registrations_screen.028')),
        content: Text(l.tr('screens_admin_pending_registrations_screen.029')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.tr('screens_admin_pending_registrations_screen.010')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.tr('screens_admin_pending_registrations_screen.030')),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _busyId = requestId);
    try {
      final response = await _apiService.confirmPendingRegistrationWithoutOtp(
        requestId,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.028'),
        message:
            response['message']?.toString() ??
            l.tr('screens_admin_pending_registrations_screen.031'),
      );
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_pending_registrations_screen.032'),
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
        request['displayName'],
        request['businessName'],
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
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_admin_pending_registrations_screen.015')),
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
                Text(l.tr('screens_admin_pending_registrations_screen.016')),
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
        title: Text(l.tr('screens_admin_pending_registrations_screen.015')),
        actions: [
          IconButton(
            tooltip: l.tr('screens_admin_pending_registrations_screen.017'),
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
                          l.tr(
                            'screens_admin_pending_registrations_screen.018',
                          ),
                          style: AppTheme.bodyAction.copyWith(
                            color: AppTheme.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            labelText: context.loc.tr(
                              'screens_admin_pending_registrations_screen.001',
                            ),
                            prefixIcon: const Icon(Icons.search_rounded),
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
                              ? context.loc.tr(
                                  'screens_admin_pending_registrations_screen.002',
                                )
                              : context.loc.tr(
                                  'screens_admin_pending_registrations_screen.003',
                                ),
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
    final l = context.loc;
    final requestId = request['id']?.toString() ?? '';
    final isBusy = _busyId == requestId;
    final otpVerified =
        (request['otpVerifiedAt']?.toString().trim().isNotEmpty ?? false);
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
                      UserDisplayName.fromMap(
                        request,
                        fallback: l.tr(
                          'screens_admin_pending_registrations_screen.019',
                        ),
                      ),
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
                    ? l.tr('screens_admin_pending_registrations_screen.020')
                    : l.tr('screens_admin_pending_registrations_screen.021'),
                color: otpVerified ? AppTheme.success : AppTheme.warning,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _infoChip(
                Icons.call_rounded,
                request['whatsapp']?.toString() ?? '-',
              ),
              if ((request['nationalId']?.toString().trim().isNotEmpty ??
                  false))
                _infoChip(
                  Icons.badge_rounded,
                  request['nationalId'].toString(),
                ),
              if (createdAt.isNotEmpty)
                _infoChip(Icons.schedule_rounded, createdAt),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _actionButton(
                onPressed: isBusy ? null : () => _reject(request),
                icon: Icons.close_rounded,
                label: l.tr('screens_admin_pending_registrations_screen.022'),
                isBusy: isBusy,
                outlined: true,
                foregroundColor: AppTheme.error,
              ),
              if (!otpVerified) ...[
                _actionButton(
                  onPressed: isBusy ? null : () => _resendOtp(request),
                  icon: Icons.refresh_rounded,
                  label: l.tr('screens_admin_pending_registrations_screen.025'),
                  isBusy: isBusy,
                ),
                _actionButton(
                  onPressed: isBusy ? null : () => _confirmWithoutOtp(request),
                  icon: Icons.verified_user_rounded,
                  label: l.tr('screens_admin_pending_registrations_screen.030'),
                  isBusy: isBusy,
                  outlined: true,
                ),
              ] else
                _actionButton(
                  onPressed: isBusy ? null : () => _approve(request),
                  icon: Icons.check_rounded,
                  label: l.tr('screens_admin_pending_registrations_screen.023'),
                  isBusy: isBusy,
                ),
            ],
          ),
          if (!otpVerified) ...[
            const SizedBox(height: 12),
            Text(
              l.tr('screens_admin_pending_registrations_screen.024'),
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required bool isBusy,
    bool outlined = false,
    Color? foregroundColor,
  }) {
    final buttonIcon = isBusy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: outlined ? foregroundColor : Colors.white,
            ),
          )
        : Icon(icon);
    final child = Text(label);

    return SizedBox(
      width: 210,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: buttonIcon,
              style: OutlinedButton.styleFrom(foregroundColor: foregroundColor),
              label: child,
            )
          : FilledButton.icon(
              onPressed: onPressed,
              icon: buttonIcon,
              label: child,
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
