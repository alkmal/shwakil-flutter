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
          'canIssueCards,canIssueSubShekelCards,canIssueHighValueCards,canIssuePrivateCards,canDeleteCards,canResellCards,canRequestCardPrinting,canScanCards,canTransfer,canWithdraw',
    },
    {
      'titleKey': 'admin_followup',
      'keys':
          'canViewCustomers,canLookupMembers,canManageUsers,canManageLocations,canManageSystemSettings,canReviewWithdrawals,canReviewTopups,canReviewDevices,canReviewCardPrintRequests,canPrepareCardPrintRequests,canFinalizeCardPrintRequests,canExportCustomerTransactions',
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
        title: context.loc.text('تم الحفظ', 'Saved'),
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
        title: context.loc.text('تعذر الحفظ', 'Could not save'),
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
          title: Text(l.text('قوالب الصلاحيات', 'Permission Templates')),
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
              .map((role) => _buildRoleView(role['value']?.toString() ?? 'basic'))
              .toList(),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _save,
          icon: const Icon(Icons.save_rounded),
          label: Text(
            _isSaving
                ? l.text('جارٍ الحفظ...', 'Saving...')
                : l.text('حفظ', 'Save'),
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
                l.text(
                  'يمكنك من هنا تحديد ما يظهر وما يعمل لهذا المستوى من الأعضاء داخل التطبيق ولوحة الإدارة.',
                  'From here you can define what this membership level can see and use across the app and admin panel.',
                ),
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
      'public_pages' => l.text('الصفحات العامة', 'Public Pages'),
      'cards_and_ops' => l.text('البطاقات والعمليات', 'Cards & Operations'),
      _ => l.text('الإدارة والمتابعة', 'Administration & Follow-up'),
    };
  }

  String _permissionLabel(String key) {
    final l = context.loc;
    return switch (key) {
      'canViewBalance' => l.text('عرض صفحة الرصيد', 'View balance screen'),
      'canViewTransactions' => l.text('عرض الحركات', 'View transactions'),
      'canViewInventory' => l.text('عرض البطاقات', 'View cards'),
      'canViewQuickTransfer' => l.text('عرض النقل السريع', 'View quick transfer'),
      'canViewContact' => l.text('عرض الدعم', 'View support'),
      'canViewLocations' => l.text('عرض الوكلاء والمواقع', 'View agents and locations'),
      'canViewUsagePolicy' => l.text('عرض سياسة الاستخدام', 'View usage policy'),
      'canViewSecuritySettings' => l.text('عرض الأمان', 'View security settings'),
      'canViewAccountSettings' => l.text('عرض الحساب', 'View account settings'),
      'canRequestVerification' => l.text('السماح بطلب التوثيق', 'Allow verification requests'),
      'canIssueCards' => l.text('إصدار البطاقات', 'Issue cards'),
      'canIssueSubShekelCards' => l.text('بطاقات أقل من شيكل', 'Issue sub-shekel cards'),
      'canIssueHighValueCards' => l.text('بطاقات عالية القيمة', 'Issue high-value cards'),
      'canIssuePrivateCards' => l.text('بطاقات خاصة', 'Issue private cards'),
      'canDeleteCards' => l.text('حذف البطاقات', 'Delete cards'),
      'canResellCards' => l.text('إعادة بيع البطاقات', 'Resell cards'),
      'canRequestCardPrinting' => l.text('طلب طباعة البطاقات', 'Request card printing'),
      'canScanCards' => l.text('فحص البطاقات', 'Scan cards'),
      'canTransfer' => l.text('التحويل', 'Transfer funds'),
      'canWithdraw' => l.text('السحب والاسترداد', 'Withdraw and redeem'),
      'canViewCustomers' => l.text('عرض العملاء', 'View customers'),
      'canLookupMembers' => l.text('البحث عن الأعضاء', 'Lookup members'),
      'canManageUsers' => l.text('إدارة المستخدمين', 'Manage users'),
      'canManageLocations' => l.text('إدارة المواقع', 'Manage locations'),
      'canManageSystemSettings' => l.text('إدارة إعدادات النظام', 'Manage system settings'),
      'canReviewWithdrawals' => l.text('مراجعة السحب', 'Review withdrawals'),
      'canReviewTopups' => l.text('مراجعة شحن الرصيد', 'Review top-ups'),
      'canReviewDevices' => l.text('مراجعة الأجهزة', 'Review devices'),
      'canReviewCardPrintRequests' => l.text('مراجعة طلبات الطباعة', 'Review print requests'),
      'canPrepareCardPrintRequests' => l.text('تجهيز طلبات الطباعة', 'Prepare print requests'),
      'canFinalizeCardPrintRequests' => l.text('إكمال طلبات الطباعة', 'Finalize print requests'),
      'canExportCustomerTransactions' => l.text('تصدير كشف العملاء', 'Export customer transactions'),
      _ => key,
    };
  }
}
