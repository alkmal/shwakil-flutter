import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminPermissionsScreen extends StatefulWidget {
  const AdminPermissionsScreen({super.key});

  @override
  State<AdminPermissionsScreen> createState() => _AdminPermissionsScreenState();
}

class _AdminPermissionsScreenState extends State<AdminPermissionsScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _isSaving = false;
  List<Map<String, dynamic>> _roles = const [];
  Map<String, dynamic> _templates = const {};

  static const List<Map<String, String>> _groups = [
    {
      'titleKey': 'public_pages',
      'keys':
          'canViewBalance,canViewTransactions,canViewInventory,canViewQuickTransfer,canViewContact,canViewLocations,canViewUsagePolicy,canViewSecuritySettings,canViewAccountSettings,canRequestVerification',
    },
    {
      'titleKey': 'cards_and_ops',
      'keys':
          'canIssueCards,canIssueSubShekelCards,canIssueHighValueCards,canIssuePrivateCards,canDeleteCards,canResellCards,canRequestCardPrinting,canScanCards,canOfflineCardScan,canTransfer,canWithdraw',
    },
    {
      'titleKey': 'admin_followup',
      'keys':
          'canViewCustomers,canLookupMembers,canManageUsers,canManageLocations,canManageSystemSettings,canReviewWithdrawals,canReviewTopups,canReviewDevices,canManageCardPrintRequests,canExportCustomerTransactions',
    },
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final payload = await _apiService.getPermissionTemplates();
      if (!mounted) {
        return;
      }
      setState(() {
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
        title: context.loc.text(
          'تعذر تحميل الصلاحيات',
          'Could not load permissions',
        ),
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
        message: context.loc.text(
          'تم تحديث قوالب الصلاحيات بنجاح.',
          'Permission templates have been updated successfully.',
        ),
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

    return DefaultTabController(
      length: _roles.length,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_admin_permissions_screen.003')),
          bottom: TabBar(
            isScrollable: true,
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
    final template = Map<String, dynamic>.from(
      _templates[roleKey] as Map? ?? const {},
    );

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
            ..._groups.map((group) {
              final keys = (group['keys'] ?? '').split(',');
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ShwakelCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdminSectionHeader(
                        title: _groupTitle(group['titleKey'] ?? ''),
                        icon: Icons.tune_rounded,
                      ),
                      const SizedBox(height: 8),
                      ...keys.map((key) {
                        final current = template[key] == true;
                        return SwitchListTile(
                          value: current,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_permissionLabel(key)),
                          onChanged: (value) {
                            setState(() {
                              final next = Map<String, dynamic>.from(
                                _templates[roleKey] as Map? ?? const {},
                              );
                              next[key] = value;
                              _templates = Map<String, dynamic>.from(_templates)
                                ..[roleKey] = next;
                            });
                          },
                        );
                      }),
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

  String _groupTitle(String key) {
    final l = context.loc;
    return switch (key) {
      'public_pages' => l.tr('screens_admin_permissions_screen.006'),
      'cards_and_ops' => l.tr('screens_admin_permissions_screen.007'),
      _ => l.tr('screens_admin_permissions_screen.008'),
    };
  }

  String _permissionLabel(String key) {
    final l = context.loc;
    return switch (key) {
      'canViewBalance' => l.tr('screens_admin_permissions_screen.009'),
      'canViewTransactions' => l.tr('screens_admin_permissions_screen.010'),
      'canViewInventory' => l.tr('screens_admin_permissions_screen.011'),
      'canViewQuickTransfer' => l.tr('screens_admin_permissions_screen.012'),
      'canViewContact' => l.tr('screens_admin_permissions_screen.013'),
      'canViewLocations' => l.tr('screens_admin_permissions_screen.014'),
      'canViewUsagePolicy' => l.tr('screens_admin_permissions_screen.015'),
      'canViewSecuritySettings' => l.tr('screens_admin_permissions_screen.016'),
      'canViewAccountSettings' => l.tr('screens_admin_permissions_screen.017'),
      'canRequestVerification' => l.tr('screens_admin_permissions_screen.018'),
      'canIssueCards' => l.tr('screens_admin_permissions_screen.019'),
      'canIssueSubShekelCards' => l.tr('screens_admin_permissions_screen.020'),
      'canIssueHighValueCards' => l.tr('screens_admin_permissions_screen.021'),
      'canIssuePrivateCards' => l.tr('screens_admin_permissions_screen.022'),
      'canDeleteCards' => l.tr('screens_admin_permissions_screen.023'),
      'canResellCards' => l.tr('screens_admin_permissions_screen.024'),
      'canRequestCardPrinting' => l.tr('screens_admin_permissions_screen.025'),
      'canScanCards' => l.tr('screens_admin_permissions_screen.026'),
      'canOfflineCardScan' => l.tr('screens_admin_permissions_screen.042'),
      'canTransfer' => l.tr('screens_admin_permissions_screen.027'),
      'canWithdraw' => l.tr('screens_admin_permissions_screen.028'),
      'canViewCustomers' => l.tr('screens_admin_permissions_screen.029'),
      'canLookupMembers' => l.tr('screens_admin_permissions_screen.030'),
      'canManageUsers' => l.tr('screens_admin_permissions_screen.031'),
      'canManageLocations' => l.tr('screens_admin_permissions_screen.032'),
      'canManageSystemSettings' => l.tr('screens_admin_permissions_screen.033'),
      'canReviewWithdrawals' => l.tr('screens_admin_permissions_screen.034'),
      'canReviewTopups' => l.tr('screens_admin_permissions_screen.035'),
      'canReviewDevices' => l.tr('screens_admin_permissions_screen.036'),
      'canManageCardPrintRequests' => l.tr(
        'screens_admin_permissions_screen.037',
      ),
      'canExportCustomerTransactions' => l.tr(
        'screens_admin_permissions_screen.040',
      ),
      _ => key,
    };
  }
}

