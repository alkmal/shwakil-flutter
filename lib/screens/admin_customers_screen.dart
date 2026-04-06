import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_customer_card.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import 'admin_customer_screen.dart';

class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  final ApiService _apiService = ApiService();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _customers = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  bool _isLoadingCustomers = false;
  int _customerPage = 1;
  int _customerLastPage = 1;

  @override
  void initState() {
    super.initState();
    _loadCustomers(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({bool reset = false}) async {
    if (reset) {
      _customerPage = 1;
      setState(() => _isLoading = true);
    } else {
      setState(() => _isLoadingCustomers = true);
    }

    try {
      final payload = await _apiService.getAdminCustomers(
        query: _searchController.text.trim(),
        page: _customerPage,
        perPage: 12,
      );
      final pag = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _customers = List<Map<String, dynamic>>.from(
          payload['customers'] as List? ?? const [],
        );
        _customerLastPage = (pag['lastPage'] as num?)?.toInt() ?? 1;
        _isLoading = false;
        _isLoadingCustomers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingCustomers = false;
      });
      await AppAlertService.showError(
        context,
        title: 'تعذر تحميل العملاء',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  void _openCustomerDetails(Map<String, dynamic> customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AdminCustomerScreen(customer: customer, canManageUsers: true),
      ),
    );
  }

  Future<void> _showCreateCustomerDialog() async {
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final whatsappController = TextEditingController();
    final passwordController = TextEditingController();
    var countryCode = PhoneNumberService.countries.first.dialCode;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (usernameController.text.trim().isEmpty ||
                whatsappController.text.trim().isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: 'بيانات ناقصة',
                message: 'اسم المستخدم ورقم الواتساب مطلوبان.',
              );
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              final response = await _apiService.createAdminUser(
                username: usernameController.text,
                fullName: fullNameController.text,
                whatsapp: whatsappController.text,
                password: passwordController.text,
                countryCode: countryCode,
              );
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              await AppAlertService.showSuccess(
                context,
                title: 'تم إنشاء المستخدم',
                message:
                    response['message']?.toString() ??
                    'تم إنشاء المستخدم بنجاح.',
              );
              await _loadCustomers(reset: true);
            } catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: 'تعذر الإنشاء',
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: const Text('إضافة مستخدم جديد'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المستخدم',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل',
                        prefixIcon: Icon(Icons.badge_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 130,
                          child: DropdownButtonFormField<String>(
                            initialValue: countryCode,
                            decoration: const InputDecoration(
                              labelText: 'رمز الدولة',
                            ),
                            items: PhoneNumberService.countries
                                .map(
                                  (country) => DropdownMenuItem(
                                    value: country.dialCode,
                                    child: Text('+${country.dialCode}'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() => countryCode = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: whatsappController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'رقم الواتساب',
                              prefixIcon: Icon(Icons.phone_rounded),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور الابتدائية',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(isSaving ? 'جارٍ الحفظ...' : 'إنشاء'),
              ),
            ],
          );
        },
      ),
    );

    usernameController.dispose();
    fullNameController.dispose();
    whatsappController.dispose();
    passwordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('إدارة العملاء')),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: () => _loadCustomers(reset: true),
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
                        'إدارة العملاء',
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ابحث عن العملاء، أضف مستخدمين جدد، وافتح بطاقة كل عميل بشكل مستقل.',
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _heroBadge('إجمالي الظاهر', '${_customers.length} عميل'),
                          _heroBadge(
                            'إجمالي النظام',
                            '${(_summary['totalCustomers'] as num?)?.toInt() ?? _customers.length} حساب',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AdminSectionHeader(
                  title: 'العملاء',
                  subtitle: 'كل البيانات هنا تخص العملاء فقط، وتُجلب عند فتح هذه الشاشة.',
                  icon: Icons.people_alt_rounded,
                  trailing: ShwakelButton(
                    label: 'إضافة مستخدم',
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: _showCreateCustomerDialog,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'ابحث عن عميل...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                      if (!mounted) return;
                      _loadCustomers(reset: true);
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (_isLoadingCustomers)
                  const LinearProgressIndicator(minHeight: 3),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 1080
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
                        mainAxisExtent: 210,
                      ),
                      itemCount: _customers.length,
                      itemBuilder: (context, index) => AdminCustomerCard(
                        customer: _customers[index],
                        onTap: () => _openCustomerDetails(_customers[index]),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                AdminPaginationFooter(
                  currentPage: _customerPage,
                  lastPage: _customerLastPage,
                  onPageChanged: (page) {
                    setState(() => _customerPage = page);
                    _loadCustomers();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $value',
        style: AppTheme.bodyBold.copyWith(color: Colors.white),
      ),
    );
  }
}
