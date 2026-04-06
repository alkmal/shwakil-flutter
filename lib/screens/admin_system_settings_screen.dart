import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AdminSystemSettingsScreen extends StatefulWidget {
  const AdminSystemSettingsScreen({super.key});

  @override
  State<AdminSystemSettingsScreen> createState() =>
      _AdminSystemSettingsScreenState();
}

class _AdminSystemSettingsScreenState extends State<AdminSystemSettingsScreen> {
  final ApiService _apiService = ApiService();

  final _contactTitleController = TextEditingController();
  final _contactWhatsappController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactAddressController = TextEditingController();
  final _policyTitleController = TextEditingController();
  final _policyContentController = TextEditingController();
  final _unverifiedTransferLimitController = TextEditingController(text: '200');
  final _topupRequestInstructionsController = TextEditingController();
  final _minSupportedVersionController = TextEditingController();
  final _latestVersionController = TextEditingController();
  final _androidStoreUrlController = TextEditingController();
  final _iosStoreUrlController = TextEditingController();
  final _webStoreUrlController = TextEditingController();
  final _walletTopupFeeController = TextEditingController();
  final _walletTransferFeeController = TextEditingController();
  final _cardRedeemFeeController = TextEditingController();
  final _cardResellFeeController = TextEditingController();
  final _cardPrintRequestFeeController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _registrationEnabled = true;
  bool _topupRequestEnabled = true;
  List<Map<String, dynamic>> _topupPaymentMethods = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contactTitleController.dispose();
    _contactWhatsappController.dispose();
    _contactEmailController.dispose();
    _contactAddressController.dispose();
    _policyTitleController.dispose();
    _policyContentController.dispose();
    _unverifiedTransferLimitController.dispose();
    _topupRequestInstructionsController.dispose();
    _minSupportedVersionController.dispose();
    _latestVersionController.dispose();
    _androidStoreUrlController.dispose();
    _iosStoreUrlController.dispose();
    _webStoreUrlController.dispose();
    _walletTopupFeeController.dispose();
    _walletTransferFeeController.dispose();
    _cardRedeemFeeController.dispose();
    _cardResellFeeController.dispose();
    _cardPrintRequestFeeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final contactSettings = await _apiService.getContactInfo();
      final authSettings = await _apiService.getAuthSettings();
      final transferSettings = await _apiService.getTransferSettings();
      final feeSettings = await _apiService.getFeeSettings();
      final topupRequestSettings = await _apiService
          .getAdminTopupRequestSettings();
      final topupPaymentMethods = await _apiService
          .getAdminTopupPaymentMethods();
      final usagePolicy = await _apiService.getUsagePolicy();

      if (!mounted) {
        return;
      }

      _contactTitleController.text = contactSettings['title'] ?? '';
      _contactWhatsappController.text =
          contactSettings['supportWhatsapp'] ?? '';
      _contactEmailController.text = contactSettings['supportEmail'] ?? '';
      _contactAddressController.text = contactSettings['address'] ?? '';
      _registrationEnabled = authSettings['registrationEnabled'] == true;
      _minSupportedVersionController.text =
          authSettings['minSupportedVersion']?.toString() ?? '';
      _latestVersionController.text =
          authSettings['latestVersion']?.toString() ?? '';
      _androidStoreUrlController.text =
          authSettings['androidStoreUrl']?.toString() ?? '';
      _iosStoreUrlController.text =
          authSettings['iosStoreUrl']?.toString() ?? '';
      _webStoreUrlController.text =
          authSettings['webStoreUrl']?.toString() ?? '';
      _unverifiedTransferLimitController.text =
          (transferSettings['unverifiedTransferLimit'] as num?)
              ?.toStringAsFixed(2) ??
          '200';
      _walletTopupFeeController.text =
          (feeSettings['walletTopupPercent'] as num?)?.toString() ?? '1';
      _walletTransferFeeController.text =
          (feeSettings['walletTransferPercent'] as num?)?.toString() ?? '1';
      _cardRedeemFeeController.text =
          (feeSettings['cardRedeemPercent'] as num?)?.toString() ?? '1';
      _cardResellFeeController.text =
          (feeSettings['cardResellPercent'] as num?)?.toString() ?? '1';
      _cardPrintRequestFeeController.text =
          (feeSettings['cardPrintRequestPercent'] as num?)?.toString() ?? '1';
      _topupRequestEnabled = topupRequestSettings['enabled'] == true;
      _topupRequestInstructionsController.text =
          topupRequestSettings['instructions']?.toString() ?? '';
      _policyTitleController.text = usagePolicy['title'] ?? '';
      _policyContentController.text = usagePolicy['content'] ?? '';

      setState(() {
        _topupPaymentMethods = topupPaymentMethods;
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
          'تعذر تحميل الإعدادات',
          'Could not load settings',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _save() async {
    final l = context.loc;
    setState(() => _isSaving = true);
    try {
      await Future.wait([
        _apiService.updateContactInfo(
          title: _contactTitleController.text,
          supportWhatsapp: _contactWhatsappController.text,
          supportEmail: _contactEmailController.text,
          address: _contactAddressController.text,
        ),
        _apiService.updateAuthSettings(
          registrationEnabled: _registrationEnabled,
          minSupportedVersion: _minSupportedVersionController.text,
          latestVersion: _latestVersionController.text,
          androidStoreUrl: _androidStoreUrlController.text,
          iosStoreUrl: _iosStoreUrlController.text,
          webStoreUrl: _webStoreUrlController.text,
        ),
        _apiService.updateTransferSettings(
          unverifiedTransferLimit:
              double.tryParse(_unverifiedTransferLimitController.text) ?? 200,
        ),
        _apiService.updateFeeSettings(
          walletTopupPercent:
              double.tryParse(_walletTopupFeeController.text) ?? 1,
          walletTransferPercent:
              double.tryParse(_walletTransferFeeController.text) ?? 1,
          cardRedeemPercent:
              double.tryParse(_cardRedeemFeeController.text) ?? 1,
          cardResellPercent:
              double.tryParse(_cardResellFeeController.text) ?? 1,
          cardPrintRequestPercent:
              double.tryParse(_cardPrintRequestFeeController.text) ?? 1,
        ),
        _apiService.updateAdminTopupRequestSettings(
          enabled: _topupRequestEnabled,
          instructions: _topupRequestInstructionsController.text,
        ),
        _apiService.updateUsagePolicy(
          title: _policyTitleController.text,
          content: _policyContentController.text,
        ),
      ]);
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_admin_system_settings_screen.001'),
        message: l.text(
          'تم حفظ الإعدادات بنجاح.',
          'Settings have been saved successfully.',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_system_settings_screen.002'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showTopupMethodDialog({Map<String, dynamic>? method}) async {
    final l = context.loc;
    final titleController = TextEditingController(
      text: method?['title']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: method?['description']?.toString() ?? '',
    );
    final imageUrlController = TextEditingController(
      text: method?['imageUrl']?.toString() ?? '',
    );
    final accountNumberController = TextEditingController(
      text: method?['accountNumber']?.toString() ?? '',
    );
    final sortOrderController = TextEditingController(
      text: (method?['sortOrder'] ?? 0).toString(),
    );
    var isActive = method?['isActive'] != false;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (titleController.text.trim().isEmpty ||
                accountNumberController.text.trim().isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_system_settings_screen.003'),
                message: l.text(
                  'العنوان ورقم التحويل مطلوبان.',
                  'Title and transfer number are required.',
                ),
              );
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              final methods = await _apiService.saveAdminTopupPaymentMethod(
                methodId: method?['id']?.toString(),
                title: titleController.text,
                description: descriptionController.text,
                imageUrl: imageUrlController.text,
                accountNumber: accountNumberController.text,
                isActive: isActive,
                sortOrder: int.tryParse(sortOrderController.text) ?? 0,
              );
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!mounted) {
                return;
              }
              setState(() => _topupPaymentMethods = methods);
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_system_settings_screen.004'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(
              method == null
                  ? l.tr('screens_admin_system_settings_screen.005')
                  : l.tr('screens_admin_system_settings_screen.006'),
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.007',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountNumberController,
                      decoration: InputDecoration(
                        labelText: l.text(
                          'رقم الحساب أو المحفظة',
                          'Account or wallet number',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.008',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sortOrderController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.009',
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.010',
                        ),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      title: Text(
                        l.tr('screens_admin_system_settings_screen.011'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_admin_system_settings_screen.012')),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(
                  isSaving
                      ? l.tr('screens_admin_system_settings_screen.013')
                      : l.tr('screens_admin_system_settings_screen.014'),
                ),
              ),
            ],
          );
        },
      ),
    );

    titleController.dispose();
    descriptionController.dispose();
    imageUrlController.dispose();
    accountNumberController.dispose();
    sortOrderController.dispose();
  }

  Future<void> _deleteTopupMethod(Map<String, dynamic> method) async {
    final l = context.loc;
    try {
      final methods = await _apiService.deleteAdminTopupPaymentMethod(
        method['id'].toString(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _topupPaymentMethods = methods);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_system_settings_screen.015'),
        message: ErrorMessageService.sanitize(error),
      );
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
      appBar: AppBar(
        title: Text(l.tr('screens_admin_system_settings_screen.016')),
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
                ShwakelCard(
                  padding: const EdgeInsets.all(28),
                  gradient: AppTheme.primaryGradient,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.tr('screens_admin_system_settings_screen.017'),
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.text(
                          'كل إعدادات الإدارة نُقلت إلى شاشة مستقلة وتُحمّل فقط عند الحاجة.',
                          'All administration settings were moved to a dedicated screen and load only when needed.',
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
                  title: l.tr('screens_admin_system_settings_screen.018'),
                  subtitle: l.text(
                    'إعدادات الدعم ووسائل الاتصال.',
                    'Support and contact settings.',
                  ),
                  icon: Icons.support_agent_rounded,
                ),
                const SizedBox(height: 16),
                _card(
                  Column(
                    children: [
                      TextField(
                        controller: _contactTitleController,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_system_settings_screen.019',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contactWhatsappController,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_system_settings_screen.020',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contactEmailController,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_system_settings_screen.021',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _contactAddressController,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_system_settings_screen.022',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AdminSectionHeader(
                  title: l.text(
                    'إعدادات التسجيل والتحويل',
                    'Registration & Transfer Settings',
                  ),
                  subtitle: l.text(
                    'السياسات العامة وحدود النظام.',
                    'General policies and system limits.',
                  ),
                  icon: Icons.tune_rounded,
                ),
                const SizedBox(height: 16),
                _card(
                  Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _registrationEnabled,
                        onChanged: (value) =>
                            setState(() => _registrationEnabled = value),
                        title: Text(
                          l.text(
                            'السماح بالتسجيل الجديد',
                            'Allow new registration',
                          ),
                        ),
                      ),
                      TextField(
                        controller: _unverifiedTransferLimitController,
                        decoration: InputDecoration(
                          labelText: l.text(
                            'سقف التحويل للحسابات غير الموثقة',
                            'Transfer limit for unverified accounts',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _minSupportedVersionController,
                        decoration: InputDecoration(
                          labelText: l.text(
                            'أقل نسخة مدعومة',
                            'Minimum supported version',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _latestVersionController,
                        decoration: InputDecoration(
                          labelText: l.text(
                            'أحدث نسخة متاحة',
                            'Latest available version',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _androidStoreUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Android URL',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _iosStoreUrlController,
                        decoration: const InputDecoration(labelText: 'iOS URL'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _webStoreUrlController,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_system_settings_screen.023',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AdminSectionHeader(
                  title: l.tr('screens_admin_system_settings_screen.024'),
                  subtitle: l.text(
                    'تفعيل الخدمة وإدارة طرق الدفع.',
                    'Enable the service and manage payment methods.',
                  ),
                  icon: Icons.add_card_rounded,
                  trailing: ShwakelButton(
                    label: l.tr('screens_admin_system_settings_screen.025'),
                    icon: Icons.playlist_add_rounded,
                    onPressed: _showTopupMethodDialog,
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _topupRequestEnabled,
                        onChanged: (value) =>
                            setState(() => _topupRequestEnabled = value),
                        title: Text(
                          l.text(
                            'تفعيل طلبات شحن الرصيد',
                            'Enable top-up requests',
                          ),
                        ),
                      ),
                      TextField(
                        controller: _topupRequestInstructionsController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: l.text(
                            'تعليمات الشحن للعميل',
                            'Top-up instructions for customer',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_topupPaymentMethods.isEmpty)
                        Text(
                          l.text(
                            'لا توجد طرق شحن مضافة حاليًا.',
                            'No top-up methods have been added yet.',
                          ),
                          style: AppTheme.bodyAction,
                        )
                      else
                        ..._topupPaymentMethods.map(
                          (method) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          method['title']?.toString() ?? '-',
                                          style: AppTheme.bodyBold,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          method['accountNumber']?.toString() ??
                                              '-',
                                          style: AppTheme.bodyAction,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        _showTopupMethodDialog(method: method),
                                    icon: const Icon(Icons.edit_rounded),
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteTopupMethod(method),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AdminSectionHeader(
                  title: l.tr('screens_admin_system_settings_screen.026'),
                  subtitle: l.text(
                    'تحديث النصوص المعروضة داخل التطبيق.',
                    'Update the policy text displayed inside the app.',
                  ),
                  icon: Icons.policy_rounded,
                ),
                const SizedBox(height: 16),
                _card(
                  Column(
                    children: [
                      TextField(
                        controller: _policyTitleController,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_system_settings_screen.027',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _policyContentController,
                        minLines: 4,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: l.tr(
                            'screens_admin_system_settings_screen.028',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _card(
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _buildFeeField(
                        l.tr('screens_admin_system_settings_screen.029'),
                        _walletTopupFeeController,
                      ),
                      _buildFeeField(
                        l.tr('screens_admin_system_settings_screen.030'),
                        _walletTransferFeeController,
                      ),
                      _buildFeeField(
                        l.tr('screens_admin_system_settings_screen.031'),
                        _cardRedeemFeeController,
                      ),
                      _buildFeeField(
                        l.tr('screens_admin_system_settings_screen.032'),
                        _cardResellFeeController,
                      ),
                      _buildFeeField(
                        l.tr('screens_admin_system_settings_screen.033'),
                        _cardPrintRequestFeeController,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ShwakelButton(
                  label: l.tr('screens_admin_system_settings_screen.034'),
                  icon: Icons.save_rounded,
                  onPressed: _save,
                  isLoading: _isSaving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return ShwakelCard(padding: const EdgeInsets.all(20), child: child);
  }

  Widget _buildFeeField(String label, TextEditingController controller) {
    return SizedBox(
      width: 190,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: '%'),
      ),
    );
  }
}
