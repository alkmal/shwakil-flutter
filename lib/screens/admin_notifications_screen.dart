import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _actionRouteController = TextEditingController();
  final TextEditingController _actionLabelController = TextEditingController();
  final TextEditingController _userSearchController = TextEditingController();

  bool _isLoading = true;
  bool _isAuthorized = false;
  bool _isSending = false;
  bool _isSearchingUsers = false;
  String _targetType = 'all';
  String _targetValue = '';
  String _category = 'general';
  String _notificationType = 'admin_custom_notification';
  String _priority = 'normal';
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _verificationStatuses = const [];
  List<Map<String, dynamic>> _permissions = const [];
  List<Map<String, dynamic>> _recentBatches = const [];
  List<Map<String, dynamic>> _userResults = const [];
  Map<String, dynamic>? _selectedUser;

  String _t(String key, {Map<String, String>? params}) =>
      context.loc.tr(key, params: params);

  List<_AdminNotificationOption> get _targetTypes => [
    _AdminNotificationOption(
      value: 'all',
      label: _t('screens_admin_notifications_screen.010'),
    ),
    _AdminNotificationOption(
      value: 'user',
      label: _t('screens_admin_notifications_screen.011'),
    ),
    _AdminNotificationOption(
      value: 'role',
      label: _t('screens_admin_notifications_screen.012'),
    ),
    _AdminNotificationOption(
      value: 'verification_status',
      label: _t('screens_admin_notifications_screen.013'),
    ),
    _AdminNotificationOption(
      value: 'permission',
      label: _t('screens_admin_notifications_screen.014'),
    ),
  ];

  List<_AdminNotificationOption> get _categories => [
    _AdminNotificationOption(
      value: 'general',
      label: _t('screens_admin_notifications_screen.015'),
    ),
    _AdminNotificationOption(
      value: 'account',
      label: _t('screens_admin_notifications_screen.016'),
    ),
    _AdminNotificationOption(
      value: 'financial',
      label: _t('screens_admin_notifications_screen.017'),
    ),
    _AdminNotificationOption(
      value: 'cards',
      label: _t('screens_admin_notifications_screen.018'),
    ),
    _AdminNotificationOption(
      value: 'security',
      label: _t('screens_admin_notifications_screen.019'),
    ),
  ];

  List<_AdminNotificationOption> get _types => [
    _AdminNotificationOption(
      value: 'admin_custom_notification',
      label: _t('screens_admin_notifications_screen.020'),
    ),
    _AdminNotificationOption(
      value: 'admin_account_notice',
      label: _t('screens_admin_notifications_screen.021'),
    ),
    _AdminNotificationOption(
      value: 'admin_card_notice',
      label: _t('screens_admin_notifications_screen.022'),
    ),
    _AdminNotificationOption(
      value: 'admin_financial_notice',
      label: _t('screens_admin_notifications_screen.023'),
    ),
    _AdminNotificationOption(
      value: 'admin_security_notice',
      label: _t('screens_admin_notifications_screen.024'),
    ),
    _AdminNotificationOption(
      value: 'admin_maintenance_notice',
      label: _t('screens_admin_notifications_screen.025'),
    ),
  ];

  List<_AdminNotificationOption> get _priorities => [
    _AdminNotificationOption(
      value: 'normal',
      label: _t('screens_admin_notifications_screen.026'),
    ),
    _AdminNotificationOption(
      value: 'important',
      label: _t('screens_admin_notifications_screen.027'),
    ),
    _AdminNotificationOption(
      value: 'urgent',
      label: _t('screens_admin_notifications_screen.028'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _detailsController.dispose();
    _actionRouteController.dispose();
    _actionLabelController.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canManageSystemSettings) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }

      final payload = await _apiService.getAdminNotificationComposer();
      if (!mounted) {
        return;
      }
      final audiences = Map<String, dynamic>.from(
        payload['audiences'] as Map? ?? const {},
      );
      setState(() {
        _isAuthorized = true;
        _roles = _listFrom(audiences['roles']);
        _verificationStatuses = _listFrom(audiences['verificationStatuses']);
        _permissions = _listFrom(audiences['permissions']);
        _recentBatches = _listFrom(payload['recentBatches']);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_notifications_screen.001'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  List<Map<String, dynamic>> _listFrom(Object? raw) {
    return List<Map<String, dynamic>>.from(
      (raw as List? ?? const []).map((item) => Map<String, dynamic>.from(item)),
    );
  }

  Future<void> _searchUsers() async {
    final query = _userSearchController.text.trim();
    if (query.isEmpty) {
      setState(() => _userResults = const []);
      return;
    }

    setState(() => _isSearchingUsers = true);
    try {
      final payload = await _apiService.getAdminCustomers(
        query: query,
        page: 1,
        perPage: 8,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _userResults = _listFrom(payload['customers']);
        _isSearchingUsers = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSearchingUsers = false);
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_notifications_screen.029'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_targetType != 'all' && _targetValue.trim().isEmpty) {
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_notifications_screen.030'),
        message: _t('screens_admin_notifications_screen.031'),
      );
      return;
    }

    setState(() => _isSending = true);
    try {
      final payload = await _apiService.sendAdminNotification(
        targetType: _targetType,
        targetValue: _targetValue,
        category: _category,
        notificationType: _notificationType,
        priority: _priority,
        title: _titleController.text,
        body: _bodyController.text,
        details: _detailsController.text,
        actionRoute: _actionRouteController.text,
        actionLabel: _actionLabelController.text,
      );
      if (!mounted) {
        return;
      }
      final summary = Map<String, dynamic>.from(
        payload['summary'] as Map? ?? const {},
      );
      setState(() {
        _recentBatches = _listFrom(payload['recentBatches']);
        _isSending = false;
      });
      RealtimeNotificationService.notifyNotificationsUpdated();
      await AppAlertService.showSuccess(
        context,
        title: _t('screens_admin_notifications_screen.032'),
        message: _t(
          'screens_admin_notifications_screen.033',
          params: {'count': '${summary['recipientCount'] ?? 0}'},
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSending = false);
      await AppAlertService.showError(
        context,
        title: _t('screens_admin_notifications_screen.034'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  void _selectTargetType(String? value) {
    if (value == null) {
      return;
    }
    setState(() {
      _targetType = value;
      _targetValue = '';
      _selectedUser = null;
      _userResults = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(_t('screens_admin_notifications_screen.002')),
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
                  _t('screens_admin_notifications_screen.035'),
                  style: AppTheme.h3,
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
        title: Text(_t('screens_admin_notifications_screen.002')),
        actions: [
          IconButton(
            tooltip: _t('screens_transactions_screen.011'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildComposer(),
              const SizedBox(height: 16),
              _buildPreview(),
              const SizedBox(height: 16),
              _buildRecentBatches(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Form(
      key: _formKey,
      child: ShwakelCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('screens_admin_notifications_screen.003'),
              style: AppTheme.h2,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 760;
                final fields = [
                  _buildDropdown(
                    label: _t('screens_admin_notifications_screen.004'),
                    value: _targetType,
                    options: _targetTypes,
                    onChanged: _selectTargetType,
                  ),
                  _buildDropdown(
                    label: _t('screens_admin_notifications_screen.005'),
                    value: _category,
                    options: _categories,
                    onChanged: (value) => setState(() {
                      _category = value ?? 'general';
                    }),
                  ),
                  _buildDropdown(
                    label: _t('screens_admin_notifications_screen.006'),
                    value: _notificationType,
                    options: _types,
                    onChanged: (value) => setState(() {
                      _notificationType = value ?? 'admin_custom_notification';
                    }),
                  ),
                  _buildDropdown(
                    label: _t('screens_admin_notifications_screen.007'),
                    value: _priority,
                    options: _priorities,
                    onChanged: (value) => setState(() {
                      _priority = value ?? 'normal';
                    }),
                  ),
                ];

                if (!twoColumns) {
                  return Column(
                    children: fields
                        .map(
                          (field) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: field,
                          ),
                        )
                        .toList(),
                  );
                }

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: fields
                      .map(
                        (field) => SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: field,
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildTargetValueField(),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _t('screens_admin_notifications_screen.036'),
                prefixIcon: const Icon(Icons.title_rounded),
              ),
              maxLength: 191,
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? _t('screens_admin_notifications_screen.037')
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyController,
              minLines: 4,
              maxLines: 7,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: _t('screens_admin_notifications_screen.038'),
                alignLabelWithHint: true,
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? _t('screens_admin_notifications_screen.039')
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detailsController,
              minLines: 2,
              maxLines: 4,
              maxLength: 1200,
              decoration: InputDecoration(
                labelText: _t('screens_admin_notifications_screen.040'),
                alignLabelWithHint: true,
                prefixIcon: const Icon(Icons.subject_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 760;
                final fields = [
                  TextField(
                    controller: _actionRouteController,
                    decoration: InputDecoration(
                      labelText: _t('screens_admin_notifications_screen.041'),
                      prefixIcon: const Icon(Icons.route_rounded),
                    ),
                  ),
                  TextField(
                    controller: _actionLabelController,
                    decoration: InputDecoration(
                      labelText: _t('screens_admin_notifications_screen.042'),
                      prefixIcon: const Icon(Icons.touch_app_rounded),
                    ),
                  ),
                ];
                if (!twoColumns) {
                  return Column(
                    children: [
                      fields.first,
                      const SizedBox(height: 12),
                      fields.last,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: fields.first),
                    const SizedBox(width: 12),
                    Expanded(child: fields.last),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            ShwakelButton(
              label: _isSending
                  ? _t('screens_admin_notifications_screen.043')
                  : _t('screens_admin_notifications_screen.044'),
              icon: Icons.send_rounded,
              isLoading: _isSending,
              onPressed: _isSending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetValueField() {
    if (_targetType == 'all') {
      return _buildTargetSummary(_t('screens_admin_notifications_screen.010'));
    }

    if (_targetType == 'user') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _userSearchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchUsers(),
            decoration: InputDecoration(
              labelText: _t('screens_admin_notifications_screen.045'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: _t('screens_admin_notifications_screen.029'),
                onPressed: _isSearchingUsers ? null : _searchUsers,
                icon: _isSearchingUsers
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search_rounded),
              ),
            ),
          ),
          if (_selectedUser != null) ...[
            const SizedBox(height: 10),
            _buildTargetSummary(_userDisplayName(_selectedUser!)),
          ],
          if (_userResults.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _userResults.map(_buildUserChoice).toList(),
            ),
          ],
        ],
      );
    }

    final rawOptions = switch (_targetType) {
      'role' => _roles,
      'verification_status' => _verificationStatuses,
      'permission' => _permissions,
      _ => const <Map<String, dynamic>>[],
    };
    final options = rawOptions
        .map(
          (item) => _AdminNotificationOption(
            value: item['value']?.toString() ?? '',
            label: item['label']?.toString() ?? '',
          ),
        )
        .where((item) => item.value.isNotEmpty && item.label.isNotEmpty)
        .toList();

    return _buildDropdown(
      label: _t('screens_admin_notifications_screen.046'),
      value: _targetValue.isEmpty ? null : _targetValue,
      options: options,
      onChanged: (value) => setState(() => _targetValue = value ?? ''),
      validator: (value) => value == null || value.isEmpty
          ? _t('screens_admin_notifications_screen.031')
          : null,
    );
  }

  Widget _buildUserChoice(Map<String, dynamic> user) {
    final selected = user['id']?.toString() == _targetValue;
    return ChoiceChip(
      selected: selected,
      label: Text(_userDisplayName(user)),
      avatar: const Icon(Icons.person_rounded, size: 18),
      onSelected: (_) {
        setState(() {
          _selectedUser = user;
          _targetValue = user['id']?.toString() ?? '';
        });
      },
    );
  }

  Widget _buildTargetSummary(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.group_rounded, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTheme.bodyAction,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final title = _titleController.text.trim().isEmpty
        ? _t('screens_admin_notifications_screen.047')
        : _titleController.text.trim();
    final body = _bodyController.text.trim().isEmpty
        ? _t('screens_admin_notifications_screen.048')
        : _bodyController.text.trim();
    final details = _detailsController.text.trim();

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('screens_admin_notifications_screen.049'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.bodyBold),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: AppTheme.bodyAction.copyWith(height: 1.5),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        details,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentBatches() {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('screens_admin_notifications_screen.050'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 14),
          if (_recentBatches.isEmpty)
            Text(
              _t('screens_admin_notifications_screen.051'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            )
          else
            ..._recentBatches.map(
              (batch) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecentAdminNotificationBatch(batch: batch),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<_AdminNotificationOption> options,
    required ValueChanged<String?> onChanged,
    FormFieldValidator<String>? validator,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options
          .map(
            (item) => DropdownMenuItem<String>(
              value: item.value,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: validator,
    );
  }

  String _userDisplayName(Map<String, dynamic> user) {
    final fullName = user['fullName']?.toString().trim();
    final username = user['username']?.toString().trim() ?? '';
    if (fullName != null && fullName.isNotEmpty) {
      return '$fullName @$username';
    }
    return username.isEmpty ? user['id']?.toString() ?? '-' : '@$username';
  }
}

class _RecentAdminNotificationBatch extends StatelessWidget {
  const _RecentAdminNotificationBatch({required this.batch});

  final Map<String, dynamic> batch;

  @override
  Widget build(BuildContext context) {
    final count = (batch['recipientCount'] as num?)?.toInt() ?? 0;
    final sender =
        batch['sentByDisplayName']?.toString().trim().isNotEmpty == true
        ? batch['sentByDisplayName'].toString()
        : batch['sentByUsername']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.campaign_rounded, color: AppTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  batch['title']?.toString() ?? '',
                  style: AppTheme.bodyBold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: AppTheme.caption.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            batch['body']?.toString() ?? '',
            style: AppTheme.caption.copyWith(height: 1.4),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniPill(
                icon: Icons.group_rounded,
                label: batch['targetLabel']?.toString() ?? '-',
              ),
              if (sender.isNotEmpty)
                _MiniPill(icon: Icons.person_rounded, label: sender),
              _MiniPill(
                icon: Icons.schedule_rounded,
                label: batch['createdAt']?.toString() ?? '',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.58,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminNotificationOption {
  const _AdminNotificationOption({required this.value, required this.label});

  final String value;
  final String label;
}
