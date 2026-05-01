import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
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

  static const List<Map<String, String>> _groups = [
    {
      'titleKey': 'public_pages',
      'keys':
          'canViewBalance,canViewTransactions,canViewInventory,canViewQuickTransfer,canViewContact,canViewLocations,canViewUsagePolicy,canViewSecuritySettings,canViewAccountSettings,canRequestVerification,canViewAffiliateCenter',
    },
    {
      'titleKey': 'cards_and_ops',
      'keys':
          'canIssueCards,canIssueSubShekelCards,canIssueHighValueCards,canIssuePrivateCards,canIssueSingleUseTickets,canIssueAppointmentTickets,canIssueQueueTickets,canViewPrivateCards,canReadOwnPrivateCardsOnly,canDeleteCards,canResellCards,canUsePrepaidMultipayCards,canAcceptPrepaidMultipayPayments,canRequestCardPrinting,canScanCards,canOfflineCardScan,canTransfer,canWithdraw',
    },
    {
      'titleKey': 'admin_followup',
      'keys':
          'canViewCustomers,canLookupMembers,canManageUsers,canFinanceTopup,canManageMarketingAccounts,canViewSubUsers,canManageSubUsers,canManageLocations,canManageSystemSettings,canReviewWithdrawals,canReviewTopups,canReviewDevices,canManageCardPrintRequests,canExportCustomerTransactions',
    },
  ];

  static const List<Map<String, Object>> _cardOpsSections = [
    {
      'titleKey': 'issuance',
      'icon': Icons.credit_card_rounded,
      'keys': [
        'canIssueCards',
        'canIssueSubShekelCards',
        'canIssueHighValueCards',
        'canIssuePrivateCards',
        'canIssueSingleUseTickets',
        'canIssueAppointmentTickets',
        'canIssueQueueTickets',
      ],
    },
    {
      'titleKey': 'access_followup',
      'icon': Icons.qr_code_scanner_rounded,
      'keys': [
        'canViewPrivateCards',
        'canReadOwnPrivateCardsOnly',
        'canDeleteCards',
        'canResellCards',
        'canScanCards',
        'canOfflineCardScan',
      ],
    },
    {
      'titleKey': 'payments_printing',
      'icon': Icons.swap_horiz_rounded,
      'keys': [
        'canUsePrepaidMultipayCards',
        'canAcceptPrepaidMultipayPayments',
        'canRequestCardPrinting',
        'canManageCardPrintRequests',
        'canTransfer',
        'canWithdraw',
      ],
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
                      ...(group['titleKey'] == 'cards_and_ops'
                          ? _cardOpsSections.map(
                              (section) => Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _buildPermissionSection(
                                  roleKey: roleKey,
                                  title: _cardOpsSectionTitle(
                                    section['titleKey']! as String,
                                  ),
                                  icon: section['icon']! as IconData,
                                  keys: List<String>.from(
                                    section['keys']! as List,
                                  ),
                                ),
                              ),
                            )
                          : [
                              ...keys.map(
                                (key) => _buildPermissionToggle(
                                  roleKey: roleKey,
                                  permissionKey: key,
                                ),
                              ),
                            ]),
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

  String _cardOpsSectionTitle(String key) {
    final l = context.loc;
    return switch (key) {
      'issuance' => l.tr('screens_admin_permissions_screen.057'),
      'access_followup' => l.tr('screens_admin_permissions_screen.058'),
      _ => l.tr('screens_admin_permissions_screen.059'),
    };
  }

  Widget _buildPermissionSection({
    required String roleKey,
    required String title,
    required IconData icon,
    required List<String> keys,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: AppTheme.bodyBold)),
            ],
          ),
          const SizedBox(height: 10),
          ...keys.map(
            (key) =>
                _buildPermissionToggle(roleKey: roleKey, permissionKey: key),
          ),
        ],
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
      title: Text(_permissionLabel(permissionKey)),
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
      'canViewAffiliateCenter' => l.tr('screens_admin_permissions_screen.048'),
      'canIssueCards' => l.tr('screens_admin_permissions_screen.019'),
      'canIssueSubShekelCards' => l.tr('screens_admin_permissions_screen.020'),
      'canIssueHighValueCards' => l.tr('screens_admin_permissions_screen.021'),
      'canIssuePrivateCards' => l.tr('screens_admin_permissions_screen.022'),
      'canIssueSingleUseTickets' => l.tr(
        'screens_admin_permissions_screen.051',
      ),
      'canIssueAppointmentTickets' => l.tr(
        'screens_admin_permissions_screen.052',
      ),
      'canIssueQueueTickets' => l.tr('screens_admin_permissions_screen.053'),
      'canViewPrivateCards' => l.tr('screens_admin_permissions_screen.050'),
      'canReadOwnPrivateCardsOnly' => l.tr(
        'screens_admin_permissions_screen.060',
      ),
      'canDeleteCards' => l.tr('screens_admin_permissions_screen.023'),
      'canResellCards' => l.tr('screens_admin_permissions_screen.024'),
      'canUsePrepaidMultipayCards' => l.tr(
        'screens_admin_permissions_screen.054',
      ),
      'canAcceptPrepaidMultipayPayments' => l.tr(
        'screens_admin_permissions_screen.055',
      ),
      'canRequestCardPrinting' => l.tr('screens_admin_permissions_screen.025'),
      'canScanCards' => l.tr('screens_admin_permissions_screen.026'),
      'canOfflineCardScan' => l.tr('screens_admin_permissions_screen.042'),
      'canTransfer' => l.tr('screens_admin_permissions_screen.027'),
      'canWithdraw' => l.tr('screens_admin_permissions_screen.028'),
      'canViewCustomers' => l.tr('screens_admin_permissions_screen.029'),
      'canLookupMembers' => l.tr('screens_admin_permissions_screen.030'),
      'canManageUsers' => l.tr('screens_admin_permissions_screen.031'),
      'canFinanceTopup' => l.tr('screens_admin_permissions_screen.056'),
      'canManageMarketingAccounts' => l.tr(
        'screens_admin_permissions_screen.049',
      ),
      'canViewSubUsers' => l.tr('screens_admin_permissions_screen.047'),
      'canManageSubUsers' => l.tr('screens_admin_permissions_screen.043'),
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
