import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/permission_catalog.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminPermissionsScreen extends StatefulWidget {
  const AdminPermissionsScreen({super.key});

  @override
  State<AdminPermissionsScreen> createState() => _AdminPermissionsScreenState();
}

class _AdminPermissionsScreenState extends State<AdminPermissionsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAuthorized = false;
  List<Map<String, dynamic>> _roles = const [];
  Map<String, dynamic> _templates = const {};

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
      final payload = await _apiService.getPermissionTemplates();
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthorized = true;
        _roles = List<Map<String, dynamic>>.from(
          payload['roles'] as List? ?? const [],
        );
        _templates = Map<String, dynamic>.from(
          payload['templates'] as Map? ?? const {},
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_permissions_screen.044'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await _apiService.updatePermissionTemplates(templates: _templates);
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: context.loc.tr('screens_admin_permissions_screen.001'),
        message: context.loc.tr('screens_admin_permissions_screen.045'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_permissions_screen.002'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
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
          title: Text(l.tr('screens_admin_permissions_screen.003')),
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
                  context.loc.tr('screens_admin_permissions_screen.046'),
                  style: AppTheme.h3,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: _roles.length,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_admin_permissions_screen.003')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _roles
                .map((role) => Tab(text: role['label']?.toString() ?? '-'))
                .toList(),
          ),
        ),
        drawer: const AppSidebar(),
        body: TabBarView(
          children: _roles
              .map(
                (role) => _buildRoleView(role['value']?.toString() ?? 'basic'),
              )
              .toList(),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _save,
          icon: const Icon(Icons.save_rounded),
          label: Text(
            _isSaving
                ? l.tr('screens_admin_permissions_screen.004')
                : l.tr('screens_admin_permissions_screen.005'),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleView(String roleKey) {
    final l = context.loc;

    return SingleChildScrollView(
      child: ResponsiveScaffoldContainer(
        padding: const EdgeInsets.all(AppTheme.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              gradient: AppTheme.primaryGradient,
              child: Text(
                l.tr('screens_admin_permissions_screen.041'),
                style: AppTheme.bodyAction.copyWith(
                  color: Colors.white,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ...PermissionCatalog.groups.map((group) {
              final keys = List<String>.from(group['keys']! as List);
              final title = PermissionCatalog.groupTitle(context, group);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdminSectionHeader(
                        title: title,
                        icon: group['icon']! as IconData,
                      ),
                      const SizedBox(height: 8),
                      ...keys.map(
                        (key) => _buildPermissionToggle(
                          roleKey: roleKey,
                          permissionKey: key,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionToggle({
    required String roleKey,
    required String permissionKey,
  }) {
    final current =
        (Map<String, dynamic>.from(
          _templates[roleKey] as Map? ?? const {},
        ))[permissionKey] ==
        true;
    return SwitchListTile(
      value: current,
      contentPadding: EdgeInsets.zero,
      title: Text(PermissionCatalog.label(context, permissionKey)),
      subtitle: Text(
        PermissionCatalog.description(context, permissionKey),
        style: AppTheme.caption,
      ),
      onChanged: (value) {
        setState(() {
          final next = Map<String, dynamic>.from(
            _templates[roleKey] as Map? ?? const {},
          );
          next[permissionKey] = value;
          _templates = Map<String, dynamic>.from(_templates)..[roleKey] = next;
        });
      },
    );
  }
}
