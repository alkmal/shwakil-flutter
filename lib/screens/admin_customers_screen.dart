import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_customer_card.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
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
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _customers = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  bool _isLoadingCustomers = false;
  bool _isAuthorized = false;
  bool _canManageUsers = false;
  bool _canManageMarketingAccounts = false;
  String? _resendBusyId;
  String? _otpBusyId;
  int _customerPage = 1;
  int _customerLastPage = 1;
  int _loadRequestId = 0;
  String _lastSubmittedQuery = '';

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
    final requestId = ++_loadRequestId;
    if (reset) {
      _customerPage = 1;
      setState(() {
        if (_customers.isEmpty) {
          _isLoading = true;
        } else {
          _isLoadingCustomers = true;
        }
      });
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
      final lastPage = (pagination['lastPage'] as num?)?.toInt() ?? 1;
      final currentPage = (pagination['currentPage'] as num?)?.toInt() ?? 1;
      final normalizedPage = currentPage.clamp(1, lastPage);

      if (_customerPage > lastPage && lastPage > 0) {
        if (!mounted) {
          return;
        }
        setState(() => _customerPage = lastPage);
        await _loadCustomers();
        return;
      }

      if (!mounted || requestId != _loadRequestId) {
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
        _customerPage = normalizedPage;
        _customerLastPage = lastPage;
        _canManageUsers = permissions.canManageUsers;
        _canManageMarketingAccounts = permissions.canManageMarketingAccounts;
        _isLoading = false;
        _isLoadingCustomers = false;
      });
    } catch (error) {
      if (!mounted || requestId != _loadRequestId) {
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
          canManageMarketingAccounts: _canManageMarketingAccounts,
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
    var deliveryMethod = 'whatsapp';
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
                deliveryMethod: deliveryMethod,
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
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
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
                        final phoneField = TextField(
                          controller: whatsappController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: l.tr(
                              'screens_admin_customers_screen.009',
                            ),
                            prefixIcon: const Icon(Icons.phone_rounded),
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
                            Expanded(child: phoneField),
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
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l.tr('shared.password_delivery_method'),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment<String>(
                          value: 'whatsapp',
                          icon: Icon(Icons.chat_rounded),
                          label: Text(l.tr('shared.delivery_whatsapp')),
                        ),
                        ButtonSegment<String>(
                          value: 'sms',
                          icon: Icon(Icons.sms_rounded),
                          label: Text(l.tr('shared.delivery_sms')),
                        ),
                      ],
                      selected: {deliveryMethod},
                      onSelectionChanged: (selection) {
                        setDialogState(() => deliveryMethod = selection.first);
                      },
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
    String deliveryMethod = 'whatsapp';

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
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l.tr('screens_admin_customers_screen.013')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.tr('screens_admin_customers_screen.028')),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                    value: 'whatsapp',
                    icon: Icon(Icons.chat_rounded),
                    label: Text(l.tr('shared.delivery_whatsapp')),
                  ),
                  ButtonSegment<String>(
                    value: 'sms',
                    icon: Icon(Icons.sms_rounded),
                    label: Text(l.tr('shared.delivery_sms')),
                  ),
                ],
                selected: {deliveryMethod},
                onSelectionChanged: (selection) {
                  setDialogState(() => deliveryMethod = selection.first);
                },
              ),
            ],
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
        deliveryMethod: deliveryMethod,
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

  Future<void> _sendCustomerOtp(Map<String, dynamic> customer) async {
    final l = context.loc;
    final userId = customer['id']?.toString() ?? '';

    if (userId.isEmpty) {
      await AppAlertService.showError(
        context,
        message: l.tr('screens_admin_customers_screen.027'),
      );
      return;
    }

    if (_otpBusyId == userId) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إرسال OTP'),
        content: const Text(
          'سيتم إرسال رمز تحقق للمستخدم عبر واتساب، وسيتم التحويل إلى SMS فقط إذا فشلت جميع قنوات واتساب. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.tr('screens_admin_customers_screen.014')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.tr('screens_admin_customers_screen.015')),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _otpBusyId = userId);
    try {
      final response = await _apiService.sendAdminUserOtp(userId: userId);
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        message:
            response['message']?.toString() ?? 'تم إرسال رمز التحقق للمستخدم.',
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
        setState(() => _otpBusyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final totalCustomers =
        (_summary['customersCount'] as num?)?.toInt() ??
        (_summary['totalCustomers'] as num?)?.toInt() ??
        _customers.length;

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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_admin_customers_screen.017')),
        actions: [
          IconButton(
            tooltip: l.tr('screens_admin_customers_screen.049'),
            onPressed: () => _showSummarySheet(totalCustomers),
            icon: const Icon(Icons.analytics_rounded),
          ),
          IconButton(
            tooltip: l.tr('screens_admin_customers_screen.040'),
            onPressed: _showSearchSheet,
            icon: const Icon(Icons.manage_search_rounded),
          ),
          if (_canManageUsers)
            IconButton(
              tooltip: l.tr('screens_admin_customers_screen.022'),
              onPressed: _showCreateCustomerDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          IconButton(
            tooltip: l.tr('screens_admin_customers_screen.041'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: () => _loadCustomers(reset: true),
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_isLoadingCustomers)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              _buildHeader(totalCustomers),
              const SizedBox(height: 16),
              _buildOverviewCard(totalCustomers),
              const SizedBox(height: 16),
              ShwakelCard(
                padding: const EdgeInsets.all(18),
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
                shadowLevel: ShwakelShadowLevel.none,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.manage_search_rounded,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.tr('screens_admin_customers_screen.056'),
                        style: AppTheme.bodyAction.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_customers.isEmpty)
                ShwakelCard(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Text(
                      l.tr('screens_admin_customers_screen.038'),
                      style: AppTheme.bodyAction,
                    ),
                  ),
                )
              else ...[
                ..._customers.map(
                  (customer) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AdminCustomerCard(
                      customer: customer,
                      onTap: () => _openCustomerDetails(customer),
                      onResendCredentials: _canManageUsers
                          ? () => _resendCustomerCredentials(customer)
                          : null,
                      onSendOtp: _canManageUsers
                          ? () => _sendCustomerOtp(customer)
                          : null,
                    ),
                  ),
                ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int totalCustomers) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      gradient: AppTheme.heroGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      borderColor: Colors.white.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.tr('screens_admin_customers_screen.017'),
            style: AppTheme.h1.copyWith(color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_admin_customers_screen.050'),
            style: AppTheme.bodyAction.copyWith(
              color: Colors.white.withValues(alpha: 0.90),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroChip(
                icon: Icons.people_alt_rounded,
                label:
                    '$totalCustomers ${l.tr('screens_admin_customers_screen.051')}',
              ),
              _heroChip(
                icon: Icons.search_rounded,
                label: l.tr('screens_admin_customers_screen.040'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(int totalCustomers) {
    final totalBalances = (_summary['totalBalances'] as num?)?.toDouble() ?? 0;
    final totalPrintingDebt =
        (_summary['totalPrintingDebt'] as num?)?.toDouble() ?? 0;
    final printingDebtUsers =
        (_summary['printingDebtUsersCount'] as num?)?.toInt() ?? 0;

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.loc.tr('screens_admin_customers_screen.021'),
                  style: AppTheme.bodyBold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$totalCustomers',
                  style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.loc.tr('screens_admin_customers_screen.050'),
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _summaryCard(
                context.loc.tr('screens_admin_customers_screen.051'),
                '$totalCustomers',
                Icons.people_alt_rounded,
                AppTheme.primary,
              ),
              _summaryCard(
                context.loc.tr('screens_admin_customers_screen.052'),
                CurrencyFormatter.formatAmount(totalBalances),
                Icons.account_balance_wallet_rounded,
                AppTheme.success,
              ),
              _summaryCard(
                context.loc.tr('screens_admin_customers_screen.053'),
                CurrencyFormatter.formatAmount(totalPrintingDebt),
                Icons.print_rounded,
                AppTheme.warning,
              ),
              _summaryCard(
                context.loc.tr('screens_admin_customers_screen.054'),
                '$printingDebtUsers',
                Icons.warning_amber_rounded,
                AppTheme.error,
              ),
            ],
          ),
          const SizedBox(height: 14),
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
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: AppTheme.isPhone(context) ? double.infinity : 170,
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

  Widget _heroChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppTheme.caption.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSummarySheet(int totalCustomers) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(
              context.loc.tr('screens_admin_customers_screen.049'),
              style: AppTheme.h2,
            ),
            const SizedBox(height: 8),
            Text(
              context.loc.tr('screens_admin_customers_screen.050'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildOverviewCard(totalCustomers),
          ],
        ),
      ),
    );
  }

  Future<void> _showSearchSheet() async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            Text(
              context.loc.tr('screens_admin_customers_screen.040'),
              style: AppTheme.h2,
            ),
            const SizedBox(height: 8),
            Text(
              context.loc.tr('screens_admin_customers_screen.042'),
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ShwakelCard(
              padding: const EdgeInsets.all(18),
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
                    const Duration(milliseconds: 550),
                    () {
                      if (!mounted) {
                        return;
                      }
                      _submitSearch();
                    },
                  );
                },
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

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query == _lastSubmittedQuery) {
      return;
    }
    _lastSubmittedQuery = query;
    _loadCustomers(reset: true);
  }
}
