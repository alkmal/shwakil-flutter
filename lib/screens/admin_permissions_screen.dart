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
      'title': 'الصفحات العامة',
      'keys':
          'canViewBalance,canViewTransactions,canViewInventory,canViewQuickTransfer,canViewContact,canViewLocations,canViewUsagePolicy,canViewSecuritySettings,canViewAccountSettings,canRequestVerification',
    },
    {
      'title': 'البطاقات والعمليات',
      'keys':
          'canIssueCards,canIssueSubShekelCards,canIssueHighValueCards,canIssuePrivateCards,canDeleteCards,canResellCards,canRequestCardPrinting,canScanCards,canTransfer,canWithdraw',
    },
    {
      'title': 'الإدارة والمتابعة',
      'keys':
          'canViewCustomers,canLookupMembers,canManageUsers,canManageLocations,canManageSystemSettings,canReviewWithdrawals,canReviewTopups,canReviewDevices,canReviewCardPrintRequests,canPrepareCardPrintRequests,canFinalizeCardPrintRequests,canExportCustomerTransactions',
    },
  ];

  static const Map<String, String> _labels = {
    'canViewBalance': 'عرض صفحة الرصيد',
    'canViewTransactions': 'عرض الحركات',
    'canViewInventory': 'عرض البطاقات',
    'canViewQuickTransfer': 'عرض النقل السريع',
    'canViewContact': 'عرض الدعم',
    'canViewLocations': 'عرض الوكلاء والمواقع',
    'canViewUsagePolicy': 'عرض سياسة الاستخدام',
    'canViewSecuritySettings': 'عرض الأمان',
    'canViewAccountSettings': 'عرض الحساب',
    'canRequestVerification': 'السماح بطلب التوثيق',
    'canIssueCards': 'إصدار البطاقات',
    'canIssueSubShekelCards': 'بطاقات أقل من شيكل',
    'canIssueHighValueCards': 'بطاقات عالية القيمة',
    'canIssuePrivateCards': 'بطاقات خاصة',
    'canDeleteCards': 'حذف البطاقات',
    'canResellCards': 'إعادة بيع البطاقات',
    'canRequestCardPrinting': 'طلب طباعة البطاقات',
    'canScanCards': 'فحص البطاقات',
    'canTransfer': 'التحويل',
    'canWithdraw': 'السحب والاسترداد',
    'canViewCustomers': 'عرض العملاء',
    'canLookupMembers': 'البحث عن الأعضاء',
    'canManageUsers': 'إدارة المستخدمين',
    'canManageLocations': 'إدارة المواقع',
    'canManageSystemSettings': 'إدارة إعدادات النظام',
    'canReviewWithdrawals': 'مراجعة السحب',
    'canReviewTopups': 'مراجعة شحن الرصيد',
    'canReviewDevices': 'مراجعة الأجهزة',
    'canReviewCardPrintRequests': 'مراجعة طلبات الطباعة',
    'canPrepareCardPrintRequests': 'تجهيز طلبات الطباعة',
    'canFinalizeCardPrintRequests': 'إكمال طلبات الطباعة',
    'canExportCustomerTransactions': 'تصدير كشف العملاء',
  };

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
        title: 'تعذر تحميل الصلاحيات',
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
        title: 'تم الحفظ',
        message: 'تم تحديث قوالب الصلاحيات بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر الحفظ',
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: _roles.length,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('قوالب الصلاحيات'),
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
          label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ),
    );
  }

  Widget _buildRoleView(String roleKey) {
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
                'يمكنك من هنا تحديد ما يظهر وما يعمل لهذا المستوى من الأعضاء داخل التطبيق ولوحة الإدارة.',
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
                        title: group['title'] ?? '',
                        icon: Icons.tune_rounded,
                      ),
                      const SizedBox(height: 8),
                      ...keys.map((key) {
                        final current = template[key] == true;
                        return SwitchListTile(
                          value: current,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_labels[key] ?? key),
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
}
