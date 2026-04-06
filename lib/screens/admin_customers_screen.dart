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
  String? _resendBusyId;
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
      if (!mounted) {
        return;
      }
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
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _isLoadingCustomers = false;
      });
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_customers_screen.001'),
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
    final l = context.loc;
    final usernameController = TextEditingController();
    final fullNameController = TextEditingController();
    final whatsappController = TextEditingController();
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
                title: l.tr('screens_admin_customers_screen.002'),
                message: l.text(
                  'اسم المستخدم ورقم الواتساب مطلوبان.',
                  'Username and WhatsApp number are required.',
                ),
              );
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              final response = await _apiService.createAdminUser(
                username: usernameController.text,
                fullName: fullNameController.text,
                whatsapp: whatsappController.text,
                password: '',
                countryCode: countryCode,
              );
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!mounted) {
                return;
              }
              await AppAlertService.showSuccess(
                context,
                title: l.tr('screens_admin_customers_screen.003'),
                message:
                    response['message']?.toString() ??
                    l.text(
                      'تم إنشاء المستخدم بنجاح.',
                      'The user has been created successfully.',
                    ),
              );
              await _loadCustomers(reset: true);
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_customers_screen.004'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(l.tr('screens_admin_customers_screen.005')),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_admin_customers_screen.006'),
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fullNameController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_admin_customers_screen.007'),
                        prefixIcon: const Icon(Icons.badge_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 380;
                        final countryField = SizedBox(
                          width: stacked ? double.infinity : 130,
                          child: DropdownButtonFormField<String>(
                            initialValue: countryCode,
                            decoration: InputDecoration(
                              labelText: l.tr(
                                'screens_admin_customers_screen.008',
                              ),
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
                              if (value == null) {
                                return;
                              }
                              setDialogState(() => countryCode = value);
                            },
                          ),
                        );
                        final phoneField = Expanded(
                          child: TextField(
                            controller: whatsappController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: l.tr(
                                'screens_admin_customers_screen.009',
                              ),
                              prefixIcon: const Icon(Icons.phone_rounded),
                            ),
                          ),
                        );

                        if (stacked) {
                          return Column(
                            children: [
                              countryField,
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: phoneField,
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            countryField,
                            const SizedBox(width: 12),
                            phoneField,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.text(
                        'سيتم إنشاء كلمة مرور افتراضية وإرسالها تلقائيًا إلى رقم الواتساب المدخل.',
                        'A temporary password will be generated and sent automatically to the provided WhatsApp number.',
                      ),
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_admin_customers_screen.010')),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(
                  isSaving
                      ? l.tr('screens_admin_customers_screen.011')
                      : l.tr('screens_admin_customers_screen.012'),
                ),
              ),
            ],
          );
        },
      ),
    );

    usernameController.dispose();
    fullNameController.dispose();
    whatsappController.dispose();
  }

  Future<void> _resendCustomerCredentials(Map<String, dynamic> customer) async {
    final l = context.loc;
    final userId = customer['id']?.toString() ?? '';
    if (userId.isEmpty) {
      await AppAlertService.showError(
        context,
        message: l.text(
          'Ù„Ø§ ÙŠÙ…ÙƒÙ† ØªØ­Ø¯ÙŠØ¯ Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ø­Ø³Ø§Ø¨.',
          'Unable to determine the user account.',
        ),
      );
      return;
    }

    if (_resendBusyId == userId) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_admin_customers_screen.013')),
        content: Text(
          l.text(
            'Ø³ÙŠØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø¨ÙŠØ§Ù†Ø§Øª Ø§Ù„Ø­Ø³Ø§Ø¨ ÙˆÙƒÙ„Ù…Ø© Ø§Ù„Ù…Ø±ÙˆØ± Ø¬Ø¯ÙŠØ¯Ø© ÙˆØ±Ù‚Ù… Ø§Ù„ÙˆØ§ØªØ³Ø§Ø¨ Ø§Ù„Ù…Ø¹ØØÙˆØ¯ Ù…Ù† Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù….',
            'A new password and account details will be sent over WhatsApp to the linked number.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.tr('screens_admin_customers_screen.014')),
          ),
          ShwakelButton(
            label: l.tr('screens_admin_customers_screen.015'),
            onPressed: () => Navigator.pop(dialogContext, true),
            width: 120,
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _resendBusyId = userId);
    try {
      final response = await _apiService.resendAdminUserAccountDetails(
        userId: userId,
        regeneratePassword: true,
      );
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        message:
            response['message']?.toString() ??
            l.tr('screens_admin_customers_screen.016'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _resendBusyId = null);
      }
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
      appBar: AppBar(title: Text(l.tr('screens_admin_customers_screen.017'))),
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
                        l.tr('screens_admin_customers_screen.018'),
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.text(
                          'ابحث عن العملاء، أضف مستخدمين جدد، وافتح بطاقة كل عميل بشكل مستقل.',
                          'Search customers, add new users, and open each customer profile independently.',
                        ),
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _heroBadge(
                            l.tr('screens_admin_customers_screen.019'),
                            l.text(
                              '${_customers.length} عميل',
                              '${_customers.length} customers',
                            ),
                          ),
                          _heroBadge(
                            l.tr('screens_admin_customers_screen.020'),
                            l.text(
                              '${(_summary['totalCustomers'] as num?)?.toInt() ?? _customers.length} حساب',
                              '${(_summary['totalCustomers'] as num?)?.toInt() ?? _customers.length} accounts',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AdminSectionHeader(
                  title: l.tr('screens_admin_customers_screen.021'),
                  subtitle: l.text(
                    'كل البيانات هنا تخص العملاء فقط، وتُجلب عند فتح هذه الشاشة.',
                    'All data here belongs only to customers and is loaded when this screen opens.',
                  ),
                  icon: Icons.people_alt_rounded,
                  trailing: ShwakelButton(
                    label: l.tr('screens_admin_customers_screen.022'),
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: _showCreateCustomerDialog,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_customers_screen.023'),
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 350),
                      () {
                        if (!mounted) {
                          return;
                        }
                        _loadCustomers(reset: true);
                      },
                    );
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
                      itemBuilder: (context, index) {
                        final customer = _customers[index];
                        return AdminCustomerCard(
                          customer: customer,
                          onTap: () => _openCustomerDetails(customer),
                          onResendCredentials: () =>
                              _resendCustomerCredentials(customer),
                        );
                      },
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
