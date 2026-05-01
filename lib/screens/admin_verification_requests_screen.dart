import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AdminVerificationRequestsScreen extends StatefulWidget {
  const AdminVerificationRequestsScreen({super.key});

  @override
  State<AdminVerificationRequestsScreen> createState() =>
      _AdminVerificationRequestsScreenState();
}

class _AdminVerificationRequestsScreenState
    extends State<AdminVerificationRequestsScreen> {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _requests = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) {
      return;
    }
    setState(() {
      if (silent) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });
    try {
      final requests = await _apiService.getPendingVerificationRequests();
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = requests;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_verification_requests_screen.001'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _approveRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }
    try {
      final response = await _apiService.approvePendingVerificationRequest(
        requestId,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: _t('screens_admin_verification_requests_screen.002'),
        message:
            response['message']?.toString() ??
            _t('screens_admin_verification_requests_screen.003'),
      );
      await _load(silent: true);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_verification_requests_screen.004'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }
    final notesController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('screens_admin_verification_requests_screen.005')),
        content: TextField(
          controller: notesController,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: _t('screens_admin_verification_requests_screen.006'),
            hintText: _t('screens_admin_verification_requests_screen.007'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('screens_supported_locations_screen.027')),
          ),
          FilledButton(
            onPressed: () async {
              final notes = notesController.text.trim();
              if (notes.isEmpty) {
                await AppAlertService.showError(
                  dialogContext,
                  title: _t('screens_admin_verification_requests_screen.008'),
                  message: _t('screens_admin_verification_requests_screen.009'),
                );
                return;
              }
              Navigator.pop(dialogContext);
              try {
                final response = await _apiService
                    .rejectPendingVerificationRequest(requestId, notes: notes);
                if (!mounted) {
                  return;
                }
                await AppAlertService.showSuccess(
                  context,
                  title: _t('screens_admin_verification_requests_screen.010'),
                  message:
                      response['message']?.toString() ??
                      _t('screens_admin_verification_requests_screen.011'),
                );
                await _load(silent: true);
                if (mounted) {
                  Navigator.of(context).maybePop();
                }
              } catch (error) {
                if (!mounted) {
                  return;
                }
                await AppAlertService.showError(
                  context,
                  title: _t('screens_admin_verification_requests_screen.012'),
                  message: ErrorMessageService.sanitize(error),
                );
              }
            },
            child: Text(_t('screens_admin_verification_requests_screen.013')),
          ),
        ],
      ),
    );
    notesController.dispose();
  }

  Future<void> _downloadFile(
    Map<String, dynamic> request,
    String fileType,
    String fileName,
  ) async {
    final requestId = request['id']?.toString() ?? '';
    if (requestId.isEmpty) {
      return;
    }
    try {
      await _apiService.downloadAdminVerificationFile(
        requestId: requestId,
        fileType: fileType,
        fileName: fileName,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: _t('screens_admin_verification_requests_screen.014'),
        message: _t('screens_admin_verification_requests_screen.015'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_verification_requests_screen.016'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _openDetails(Map<String, dynamic> request) async {
    final user = Map<String, dynamic>.from(
      request['user'] as Map? ?? const <String, dynamic>{},
    );
    final title = user['fullName']?.toString().trim().isNotEmpty == true
        ? user['fullName'].toString().trim()
        : '@${user['username']?.toString() ?? '-'}';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(title, style: AppTheme.h2),
              const SizedBox(height: 8),
              Text(
                _t('screens_admin_verification_requests_screen.017'),
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              _detailCard(
                children: [
                  _detailRow(
                    _t('screens_admin_verification_requests_screen.018'),
                    user['username']?.toString() ?? '-',
                  ),
                  _detailRow(
                    _t('screens_admin_verification_requests_screen.019'),
                    user['whatsapp']?.toString() ?? '-',
                  ),
                  _detailRow(
                    _t('screens_admin_verification_requests_screen.020'),
                    request['nationalId']?.toString() ?? '-',
                  ),
                  _detailRow(
                    _t('screens_admin_verification_requests_screen.021'),
                    request['birthDate']?.toString() ?? '-',
                  ),
                  _detailRow(
                    _t('screens_admin_verification_requests_screen.022'),
                    request['requestedRoleLabel']?.toString() ?? '-',
                  ),
                  _detailRow(
                    _t('screens_admin_verification_requests_screen.023'),
                    request['createdAt']?.toString() ?? '-',
                  ),
                  if ((request['notes']?.toString().trim().isNotEmpty ?? false))
                    _detailRow(
                      _t('screens_admin_verification_requests_screen.024'),
                      request['notes'].toString(),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _t('screens_admin_verification_requests_screen.025'),
                style: AppTheme.h3,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ShwakelButton(
                      label: _t(
                        'screens_admin_verification_requests_screen.026',
                      ),
                      icon: Icons.badge_rounded,
                      isSecondary: true,
                      onPressed: () => _downloadFile(
                        request,
                        'identity',
                        'identity-${request['id']}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShwakelButton(
                      label: _t(
                        'screens_admin_verification_requests_screen.027',
                      ),
                      icon: Icons.face_retouching_natural_rounded,
                      isSecondary: true,
                      onPressed: () => _downloadFile(
                        request,
                        'selfie',
                        'selfie-${request['id']}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ShwakelButton(
                      label: _t(
                        'screens_admin_verification_requests_screen.013',
                      ),
                      icon: Icons.close_rounded,
                      isSecondary: true,
                      onPressed: () => _rejectRequest(request),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShwakelButton(
                      label: _t(
                        'screens_admin_verification_requests_screen.028',
                      ),
                      icon: Icons.check_circle_rounded,
                      onPressed: () => _approveRequest(request),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailCard({required List<Widget> children}) {
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surfaceVariant,
      shadowLevel: ShwakelShadowLevel.none,
      child: Column(
        children:
            children
                .expand((item) => [item, const SizedBox(height: 10)])
                .toList()
              ..removeLast(),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTheme.bodyBold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_t('screens_admin_verification_requests_screen.029')),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: _t('screens_transactions_screen.011'),
            onPressed: () => _load(silent: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppNotificationAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: ResponsiveScaffoldContainer(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: RefreshIndicator(
          onRefresh: () => _load(silent: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ShwakelCard(
                padding: const EdgeInsets.all(18),
                borderRadius: BorderRadius.circular(22),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: AppTheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t(
                              'screens_admin_verification_requests_screen.030',
                            ),
                            style: AppTheme.h3,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _t(
                              'screens_admin_verification_requests_screen.031',
                              params: {'count': _requests.length.toString()},
                            ),
                            style: AppTheme.bodyAction.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_requests.isEmpty)
                ShwakelCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 62,
                        color: AppTheme.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _t('screens_admin_verification_requests_screen.032'),
                        style: AppTheme.h3,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t('screens_admin_verification_requests_screen.033'),
                        style: AppTheme.bodyAction,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ..._requests.map(_buildRequestCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final user = Map<String, dynamic>.from(
      request['user'] as Map? ?? const <String, dynamic>{},
    );
    final displayName = user['fullName']?.toString().trim().isNotEmpty == true
        ? user['fullName'].toString().trim()
        : '@${user['username']?.toString() ?? '-'}';
    final phone = user['phone']?.toString().trim();
    final requestedRole =
        request['requestedRoleLabel']?.toString() ??
        _t('screens_admin_verification_requests_screen.034');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        onTap: () => _openDetails(request),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.assignment_ind_rounded,
                    color: AppTheme.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: AppTheme.bodyBold),
                      const SizedBox(height: 4),
                      Text(
                        '@${user['username']?.toString() ?? '-'}',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    requestedRole,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (phone != null && phone.isNotEmpty)
                  _infoChip(Icons.phone_rounded, phone),
                _infoChip(
                  Icons.badge_rounded,
                  request['nationalId']?.toString() ?? '-',
                ),
                _infoChip(
                  Icons.calendar_today_rounded,
                  request['birthDate']?.toString() ?? '-',
                ),
                _infoChip(
                  Icons.schedule_rounded,
                  request['createdAt']?.toString() ?? '-',
                ),
                _infoChip(Icons.touch_app_rounded, 'اضغط لعرض التفاصيل'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(label, style: AppTheme.caption),
        ],
      ),
    );
  }
}
