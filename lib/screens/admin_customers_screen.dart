import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_customer_card.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/tool_toggle_hint.dart';
import 'admin_customer_screen.dart';

class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _customers = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  bool _isLoadingCustomers = false;
  bool _isAuthorized = false;
  bool _canManageUsers = false;
  String? _resendBusyId;
  int _customerPage = 1;
  int _customerLastPage = 1;
  bool _showSearch = false;

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
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canViewCustomers) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
          _isLoadingCustomers = false;
        });
        return;
      }
      final payload = await _apiService.getAdminCustomers(
        query: _searchController.text.trim(),
        page: _customerPage,
        perPage: 12,
      );
      final pagination = Map<String, dynamic>.from(
        payload['pagination'] as Map? ?? const {},
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isAuthorized = true;
        _summary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _customers = List<Map<String, dynamic>>.from(
          payload['customers'] as List? ?? const [],
        );
        _customerLastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
        _canManageUsers = permissions.canManageUsers;
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
        builder: (_) => AdminCustomerScreen(
          customer: customer,
          canManageUsers: _canManageUsers,
        ),
      ),
    );
  }

  Future<void> _showCreateCustomerDialog() async {
    if (!_canManageUsers) {
      return;
    }
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
            final username = usernameController.text.trim().toLowerCase();
            final whatsapp = PhoneNumberService.normalize(
              input: whatsappController.text.trim(),
              defaultDialCode: countryCode,
            );

            if (username.isEmpty || whatsapp.isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_customers_screen.002'),
                message: l.tr('screens_admin_customers_screen.024'),
              );
              return;
            }

            if (!RegExp(r'^[a-z0-9._@+-]{3,32}$').hasMatch(username)) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_customers_screen.002'),
                message: l.tr('screens_admin_customers_screen.047'),
              );
              return;
            }

            setDialogState(() => isSaving = true);
            try {
              final response = await _apiService.createAdminUser(
                username: username,
                fullName: fullNameController.text,
                whatsapp: whatsapp,
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
                    l.tr('screens_admin_customers_screen.025'),
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
                      l.tr('screens_admin_customers_screen.026'),
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
        message: l.tr('screens_admin_customers_screen.027'),
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
        content: Text(l.tr('screens_admin_customers_screen.028')),
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
    final totalCustomers =
        (_summary['totalCustomers'] as num?)?.toInt() ?? _customers.length;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_admin_customers_screen.017')),
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
                  l.tr('screens_admin_customers_screen.038'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_admin_customers_screen.017')),
          actions: [
            if (_canManageUsers)
              IconButton(
                tooltip: l.tr('screens_admin_customers_screen.022'),
                onPressed: _showCreateCustomerDialog,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            IconButton(
              tooltip: _showSearch
                  ? context.loc.tr('screens_admin_customers_screen.039')
                  : context.loc.tr('screens_admin_customers_screen.040'),
              onPressed: () => setState(() => _showSearch = !_showSearch),
              icon: Icon(
                _showSearch
                    ? Icons.search_off_rounded
                    : Icons.manage_search_rounded,
              ),
            ),
            IconButton(
              tooltip: context.loc.tr('screens_admin_customers_screen.041'),
              onPressed: _showHelpDialog,
              icon: const Icon(Icons.info_outline_rounded),
            ),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(76),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(6),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  tabs: [
                    Tab(
                      text: l.tr('screens_admin_customers_screen.048'),
                      icon: const Icon(Icons.people_alt_rounded),
                    ),
                    Tab(
                      text: l.tr('screens_admin_customers_screen.049'),
                      icon: const Icon(Icons.analytics_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        drawer: const AppSidebar(),
        body: RefreshIndicator(
          onRefresh: () => _loadCustomers(reset: true),
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: TabBarView(
              children: [
                _buildCustomersTab(totalCustomers),
                _buildSummaryTab(totalCustomers),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomersTab(int totalCustomers) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: context.loc.tr('screens_admin_customers_screen.021'),
            icon: Icons.people_alt_rounded,
          ),
          const SizedBox(height: 16),
          if (_showSearch)
            ShwakelCard(
              padding: const EdgeInsets.all(18),
              withBorder: true,
              borderColor: AppTheme.borderLight,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: context.loc.tr(
                    'screens_admin_customers_screen.023',
                  ),
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
            )
          else
            ToolToggleHint(
              message: context.loc.tr('screens_admin_customers_screen.042'),
              icon: Icons.manage_search_rounded,
            ),
          const SizedBox(height: 12),
          Text(
            context.loc.tr(
              'screens_admin_customers_screen.043',
              params: {
                'shown': '${_customers.length}',
                'total': '$totalCustomers',
              },
            ),
            style: AppTheme.caption,
          ),
          const SizedBox(height: 16),
          if (_isLoadingCustomers) const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1080
                  ? 3
                  : constraints.maxWidth > 720
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
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
    );
  }

  Widget _buildSummaryTab(int totalCustomers) {
    final totalBalances = (_summary['totalBalances'] as num?)?.toDouble() ?? 0;
    final totalPrintingDebt =
        (_summary['totalPrintingDebt'] as num?)?.toDouble() ?? 0;
    final printingDebtUsers =
        (_summary['printingDebtUsersCount'] as num?)?.toInt() ?? 0;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            withBorder: true,
            borderColor: AppTheme.borderLight,
            child: Text(
              'ملخص سريع وواضح للعملاء بدون إزاحة القائمة الرئيسية. استخدم تبويب القائمة للوصول إلى الحسابات، وافتح البحث من الأيقونة عند الحاجة.',
              style: AppTheme.bodyAction,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final cards = [
                _summaryCard(
                  'إجمالي العملاء',
                  '$totalCustomers',
                  Icons.people_alt_rounded,
                  AppTheme.primary,
                ),
                _summaryCard(
                  'إجمالي الأرصدة',
                  totalBalances.toStringAsFixed(2),
                  Icons.account_balance_wallet_rounded,
                  AppTheme.success,
                ),
                _summaryCard(
                  'مديونية الطباعة',
                  totalPrintingDebt.toStringAsFixed(2),
                  Icons.print_rounded,
                  AppTheme.warning,
                ),
                _summaryCard(
                  'حسابات عليها دين',
                  '$printingDebtUsers',
                  Icons.warning_amber_rounded,
                  AppTheme.error,
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      cards[i],
                      if (i != cards.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return Wrap(spacing: 12, runSpacing: 12, children: cards);
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 240,
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
        withBorder: true,
        borderColor: AppTheme.borderLight,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.caption),
                  const SizedBox(height: 4),
                  Text(value, style: AppTheme.bodyBold),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.loc.tr('screens_admin_customers_screen.044')),
        content: Text(context.loc.tr('screens_admin_customers_screen.045')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.loc.tr('screens_admin_customers_screen.046')),
          ),
        ],
      ),
    );
  }
}
