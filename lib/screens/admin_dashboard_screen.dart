import 'dart:async';
import 'package:flutter/material.dart';
import '../services/index.dart';
import 'admin_customer_screen.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_page_header.dart';
import '../widgets/admin/admin_summary_widgets.dart';
import '../widgets/admin/admin_customer_card.dart';
import '../widgets/admin/admin_device_request_card.dart';
import '../widgets/admin/admin_withdrawal_request_card.dart';
import '../widgets/admin/admin_location_card.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/admin/admin_pagination_footer.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  final _searchController = TextEditingController();
  final _contactTitleController = TextEditingController();
  final _contactWhatsappController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactAddressController = TextEditingController();
  final _policyTitleController = TextEditingController();
  final _policyContentController = TextEditingController();
  final _unverifiedTransferLimitController = TextEditingController(text: '200');
  final _minSupportedVersionController = TextEditingController();
  final _latestVersionController = TextEditingController();
  final _androidStoreUrlController = TextEditingController();
  final _iosStoreUrlController = TextEditingController();
  final _webStoreUrlController = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _pendingDeviceRequests = const [];
  List<Map<String, dynamic>> _pendingWithdrawalRequests = const [];
  List<Map<String, dynamic>> _supportedLocations = const [];

  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _isLoadingCustomers = false;
  bool _isSavingSettings = false;
  bool _registrationEnabled = true;

  int _customerPage = 1;
  int _customerLastPage = 1;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _contactTitleController.dispose();
    _contactWhatsappController.dispose();
    _contactEmailController.dispose();
    _contactAddressController.dispose();
    _policyTitleController.dispose();
    _policyContentController.dispose();
    _unverifiedTransferLimitController.dispose();
    _minSupportedVersionController.dispose();
    _latestVersionController.dispose();
    _androidStoreUrlController.dispose();
    _iosStoreUrlController.dispose();
    _webStoreUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      await _authService.refreshCurrentUser();
      final user = await _authService.currentUser();
      final payload = await _apiService.getAdminCustomers(
        query: '',
        page: 1,
        perPage: 12,
      );
      final pendingDevices = await _apiService.getPendingDeviceAccessRequests();
      final pendingWithdrawals = await _apiService
          .getPendingWithdrawalRequests();
      final locations = await _apiService.getAdminSupportedLocations();
      final contactSettings = await _apiService.getContactInfo();
      final authSettings = await _apiService.getAuthSettings();
      final transferSettings = await _apiService.getTransferSettings();
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
      _policyTitleController.text = usagePolicy['title'] ?? '';
      _policyContentController.text = usagePolicy['content'] ?? '';

      setState(() {
        _user = user;
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _applyCustomers(payload);
        _pendingDeviceRequests = pendingDevices;
        _pendingWithdrawalRequests = pendingWithdrawals;
        _supportedLocations = locations;
        _isLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر التحميل',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  void _applyCustomers(Map<String, dynamic> payload) {
    final pag = Map<String, dynamic>.from(
      payload['pagination'] as Map? ?? const {},
    );
    _customerPage = (pag['currentPage'] as num?)?.toInt() ?? 1;
    _customerLastPage = (pag['lastPage'] as num?)?.toInt() ?? 1;
    _customers = List<Map<String, dynamic>>.from(
      payload['customers'] as List? ?? const [],
    );
  }

  Future<void> _loadCustomers({bool reset = false}) async {
    if (reset) {
      _customerPage = 1;
    }
    setState(() => _isLoadingCustomers = true);
    try {
      final payload = await _apiService.getAdminCustomers(
        query: _searchController.text.trim(),
        page: _customerPage,
        perPage: 12,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyCustomers(payload);
        _isLoadingCustomers = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _isLoadingCustomers = false);
      }
    }
  }

  Future<void> _saveGlobalSettings() async {
    setState(() => _isSavingSettings = true);
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
        title: 'تم الحفظ',
        message: 'تم حفظ كافة إعدادات النظام بنجاح.',
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
        setState(() => _isSavingSettings = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('لوحة تحكم الإدارة'),
        actions: [
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث البيانات',
          ),
          const SizedBox(width: 16),
        ],
      ),
      drawer: const AppSidebar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebarNav = constraints.maxWidth > 1180;
          return Row(
            children: [
              if (showSidebarNav) _buildSidebarNav(),
              Expanded(
                child: SingleChildScrollView(
                  child: ResponsiveScaffoldContainer(
                    padding: const EdgeInsets.all(AppTheme.spacingLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 28),
                        if (!showSidebarNav) _buildHorizontalTabs(),
                        if (!showSidebarNav) const SizedBox(height: 18),
                        _buildCurrentSectionContent(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebarNav() {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _navItem(0, 'نظرة عامة', Icons.dashboard_rounded),
          _navItem(1, 'إدارة العملاء', Icons.people_alt_rounded),
          _navItem(
            2,
            'طلبات الأجهزة',
            Icons.devices_other_rounded,
            badgeCount: _pendingDeviceRequests.length,
          ),
          _navItem(
            3,
            'السحوبات المصرفية',
            Icons.account_balance_rounded,
            badgeCount: _pendingWithdrawalRequests.length,
          ),
          _navItem(4, 'الفروع والمواقع', Icons.map_rounded),
          _navItem(5, 'إعدادات النظام', Icons.settings_applications_rounded),
        ],
      ),
    );
  }

  Widget _navItem(
    int index,
    String label,
    IconData icon, {
    int badgeCount = 0,
  }) {
    final isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : AppTheme.border,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          label,
          style: AppTheme.bodyBold.copyWith(
            color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
          ),
        ),
        trailing: badgeCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : null,
        onTap: () => setState(() => _selectedIndex = index),
      ),
    );
  }

  Widget _buildHorizontalTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _tabChip(0, 'نظرة عامة'),
          _tabChip(1, 'العملاء'),
          _tabChip(2, 'الأجهزة'),
          _tabChip(3, 'السحوبات'),
          _tabChip(4, 'الفروع'),
          _tabChip(5, 'الإعدادات'),
        ],
      ),
    );
  }

  Widget _tabChip(int index, String label) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: ChoiceChip(
        selected: isSelected,
        label: Text(label),
        onSelected: (_) => setState(() => _selectedIndex = index),
      ),
    );
  }

  Widget _buildHeader() {
    return ShwakelPageHeader(
      eyebrow: 'الداشبورد الإداري',
      title: 'إشراف كامل على النظام من شاشة واحدة',
      subtitle:
          'تابع العملاء والطلبات والإعدادات والفروع من واجهة إدارية واضحة ومنظمة.',
      badges: [
        ShwakelInfoBadge(
          icon: Icons.people_alt_rounded,
          label: '${_customers.length} عميل ظاهر',
        ),
        ShwakelInfoBadge(
          icon: Icons.notifications_active_rounded,
          label:
              '${_pendingDeviceRequests.length + _pendingWithdrawalRequests.length} طلب يحتاج متابعة',
          color: AppTheme.warning,
        ),
      ],
      trailing: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: AppTheme.radiusLg,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _user?['fullName'] ?? _user?['username'] ?? 'الإدارة',
                style: AppTheme.bodyBold.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSectionContent() {
    switch (_selectedIndex) {
      case 0:
        return _overviewSection();
      case 1:
        return _customersSection();
      case 2:
        return _deviceRequestsSection();
      case 3:
        return _withdrawalRequestsSection();
      case 4:
        return _locationsSection();
      case 5:
        return _settingsSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _overviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminDashboardSummary(summary: _summary),
        const SizedBox(height: 24),
        AdminSectionHeader(
          title: 'أولوية المتابعة اليوم',
          subtitle: 'نظرة سريعة على أهم العناصر التي تحتاج تدخلاً من الإدارة.',
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: 12),
        _overviewTile(
          Icons.devices_other_rounded,
          'طلبات الأجهزة المعلقة',
          '${_pendingDeviceRequests.length} طلب',
          AppTheme.warning,
        ),
        const SizedBox(height: 12),
        _overviewTile(
          Icons.account_balance_rounded,
          'طلبات السحب المعلقة',
          '${_pendingWithdrawalRequests.length} طلب',
          AppTheme.secondary,
        ),
        const SizedBox(height: 12),
        _overviewTile(
          Icons.location_on_rounded,
          'الفروع والمواقع المدعومة',
          '${_supportedLocations.length} موقع',
          AppTheme.accent,
        ),
      ],
    );
  }

  Widget _overviewTile(IconData icon, String title, String value, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppTheme.radiusMd,
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: AppTheme.bodyBold)),
          Text(value, style: AppTheme.bodyBold.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _customersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'إدارة العملاء',
          subtitle:
              'ابحث في العملاء وافتح بطاقة كل عميل للوصول إلى السجل والصلاحيات والتحكم الكامل.',
          icon: Icons.people_alt_rounded,
          trailing: SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'ابحث عن عميل...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 500),
                  () => _loadCustomers(reset: true),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_isLoadingCustomers)
          const Center(child: CircularProgressIndicator())
        else ...[
          _customersGrid(),
          const SizedBox(height: 20),
          AdminPaginationFooter(
            currentPage: _customerPage,
            lastPage: _customerLastPage,
            onPageChanged: (page) {
              setState(() => _customerPage = page);
              _loadCustomers();
            },
          ),
        ],
      ],
    );
  }

  Widget _customersGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 1100
            ? 3
            : constraints.maxWidth > 720
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: 180,
          ),
          itemCount: _customers.length,
          itemBuilder: (context, index) => AdminCustomerCard(
            customer: _customers[index],
            onTap: () => _openCustomerDetails(_customers[index]),
          ),
        );
      },
    );
  }

  Widget _deviceRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'طلبات الأجهزة',
          subtitle: 'اعتمد أو ارفض طلبات الأجهزة الجديدة من نفس الواجهة.',
          icon: Icons.devices_other_rounded,
          iconColor: AppTheme.warning,
        ),
        const SizedBox(height: 16),
        if (_pendingDeviceRequests.isEmpty)
          _buildEmptyPanel('لا توجد طلبات أجهزة معلقة حاليًا.')
        else
          ..._pendingDeviceRequests.map(
            (request) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdminDeviceRequestCard(
                request: request,
                onAction: (approve) => _handleDeviceRequest(request, approve),
                onTap: () {},
              ),
            ),
          ),
      ],
    );
  }

  Widget _withdrawalRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'السحوبات المصرفية',
          subtitle: 'راجع الطلبات المالية المعلقة واعتمدها أو ارفضها بسرعة.',
          icon: Icons.account_balance_rounded,
          iconColor: AppTheme.secondary,
        ),
        const SizedBox(height: 16),
        if (_pendingWithdrawalRequests.isEmpty)
          _buildEmptyPanel('لا توجد طلبات سحب معلقة حاليًا.')
        else
          ..._pendingWithdrawalRequests.map(
            (request) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdminWithdrawalRequestCard(
                request: request,
                onAction: (approve) => _handleWithdrawal(request, approve),
                onTap: () {},
              ),
            ),
          ),
      ],
    );
  }

  Widget _locationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'الفروع والمواقع',
          subtitle: 'عرض المواقع المدعومة في النظام بصيغة أقرب للداشبورد.',
          icon: Icons.map_rounded,
          iconColor: AppTheme.accent,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 1100
                ? 3
                : constraints.maxWidth > 720
                ? 2
                : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 150,
              ),
              itemCount: _supportedLocations.length,
              itemBuilder: (context, index) => AdminLocationCard(
                location: _supportedLocations[index],
                onEdit: () {},
                onDelete: () {},
                onMap: () {},
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _settingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'إعدادات النظام',
          subtitle:
              'حدّث بيانات التواصل وإعدادات التسجيل والسياسات من بطاقة إعدادات واحدة.',
          icon: Icons.settings_applications_rounded,
        ),
        const SizedBox(height: 16),
        _settingsCard(
          title: 'بيانات التواصل والدعم',
          child: Column(
            children: [
              TextField(
                controller: _contactTitleController,
                decoration: const InputDecoration(
                  labelText: 'اسم الجهة المعروض للعملاء',
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 720;
                  if (isCompact) {
                    return Column(
                      children: [
                        TextField(
                          controller: _contactWhatsappController,
                          decoration: const InputDecoration(
                            labelText: 'رقم واتساب الدعم',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _contactEmailController,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني للدعم',
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _contactWhatsappController,
                          decoration: const InputDecoration(
                            labelText: 'رقم واتساب الدعم',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _contactEmailController,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني للدعم',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactAddressController,
                decoration: const InputDecoration(labelText: 'العنوان الفعلي'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _settingsCard(
          title: 'خيارات التسجيل والسياسات',
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _registrationEnabled,
                title: const Text('السماح بتسجيل الحسابات الجديدة'),
                subtitle: const Text(
                  'فتح أو إغلاق إمكانية إنشاء حسابات جديدة داخل التطبيق.',
                ),
                onChanged: (value) =>
                    setState(() => _registrationEnabled = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _unverifiedTransferLimitController,
                decoration: const InputDecoration(
                  labelText: 'سقف التحويل للحسابات غير الموثقة (₪)',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _minSupportedVersionController,
                decoration: const InputDecoration(
                  labelText: 'أقل نسخة مسموحة',
                  hintText: 'مثال: 1.0.3',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _latestVersionController,
                decoration: const InputDecoration(
                  labelText: 'أحدث نسخة متاحة',
                  hintText: 'مثال: 1.0.5',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _androidStoreUrlController,
                decoration: const InputDecoration(
                  labelText: 'رابط متجر Android',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _iosStoreUrlController,
                decoration: const InputDecoration(labelText: 'رابط متجر iOS'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _webStoreUrlController,
                decoration: const InputDecoration(
                  labelText: 'رابط التحديث للويب أو سطح المكتب',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _policyTitleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان سياسة الاستخدام',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _policyContentController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'محتوى سياسة الاستخدام',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ShwakelButton(
          label: 'حفظ كافة الإعدادات',
          icon: Icons.save_rounded,
          onPressed: _saveGlobalSettings,
          isLoading: _isSavingSettings,
        ),
      ],
    );
  }

  Widget _settingsCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.radiusLg,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.h3),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildEmptyPanel(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.radiusLg,
        border: Border.all(color: AppTheme.border),
      ),
      child: Center(
        child: Text(
          message,
          style: AppTheme.bodyAction.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  void _openCustomerDetails(Map<String, dynamic> customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminCustomerScreen(customer: customer),
      ),
    );
  }

  Future<void> _handleDeviceRequest(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    try {
      await _apiService.reviewDeviceAccessRequest(
        request['id'].toString(),
        approve: approve,
      );
      _loadAll();
    } catch (_) {}
  }

  Future<void> _handleWithdrawal(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    try {
      await _apiService.reviewWithdrawalRequest(
        request['id'].toString(),
        approve: approve,
      );
      _loadAll();
    } catch (_) {}
  }
}
