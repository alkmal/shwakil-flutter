import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_customer_card.dart';
import '../widgets/admin/admin_load_error_card.dart';
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
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _customers = const [];
  Map<String, dynamic> _summary = const {};
  bool _isLoading = true;
  bool _isLoadingCustomers = false;
  bool _isAuthorized = false;
  bool _canManageUsers = false;
  bool _canManageMarketingAccounts = false;
  bool _showSummaryInline = false;
  String? _loadError;
  String? _resendBusyId;
  String? _otpBusyId;
  int _customerPage = 1;
  int _customerLastPage = 1;
  int _loadRequestId = 0;
  String _lastSubmittedQuery = '';
  String _sortMode = 'newest';

  @override
  void initState() {
    super.initState();
    _loadCustomers(reset: true);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers({bool reset = false}) async {
    final requestId = ++_loadRequestId;
    if (reset) {
      _customerPage = 1;
      setState(() {
        _loadError = null;
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
          _loadError = null;
          _isLoading = false;
          _isLoadingCustomers = false;
        });
        return;
      }
      final payload = await _apiService.getAdminCustomers(
        query: _searchController.text.trim(),
        page: _customerPage,
        perPage: 12,
        sort: _sortMode,
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
        _loadError = null;
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
        _loadError = ErrorMessageService.sanitize(error);
        _isLoading = false;
        _isLoadingCustomers = false;
      });
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

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
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

            return Scaffold(
              appBar: AppBar(
                title: Text(l.tr('screens_admin_customers_screen.005')),
              ),
              body: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        TextField(
                          controller: usernameController,
                          decoration: InputDecoration(
                            labelText: l.tr(
                              'screens_admin_customers_screen.006',
                            ),
                            prefixIcon: const Icon(
                              Icons.person_outline_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: fullNameController,
                          decoration: InputDecoration(
                            labelText: l.tr(
                              'screens_admin_customers_screen.007',
                            ),
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
                              icon: const Icon(Icons.chat_rounded),
                              label: Text(l.tr('shared.delivery_whatsapp')),
                            ),
                            ButtonSegment<String>(
                              value: 'sms',
                              icon: const Icon(Icons.sms_rounded),
                              label: Text(l.tr('shared.delivery_sms')),
                            ),
                          ],
                          selected: {deliveryMethod},
                          onSelectionChanged: (selection) {
                            setDialogState(
                              () => deliveryMethod = selection.first,
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSaving
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                                child: Text(
                                  l.tr('screens_admin_customers_screen.010'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: isSaving ? null : submit,
                                child: Text(
                                  isSaving
                                      ? l.tr(
                                          'screens_admin_customers_screen.011',
                                        )
                                      : l.tr(
                                          'screens_admin_customers_screen.012',
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
              resizeToAvoidBottomInset: true,
            );
          },
        ),
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
                    icon: const Icon(Icons.chat_rounded),
                    label: Text(l.tr('shared.delivery_whatsapp')),
                  ),
                  ButtonSegment<String>(
                    value: 'sms',
                    icon: const Icon(Icons.sms_rounded),
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
        title: Text(l.text('إرسال OTP', 'Send OTP')),
        content: const Text(
          'سيتم إرسال رمز تحقق عبر قناة واحدة فقط. كل إعادة إرسال تستخدم القناة التالية حتى تصل إلى SMS. هل تريد المتابعة؟',
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

    if (_loadError != null && !_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: Text(l.tr('screens_admin_customers_screen.017'))),
        drawer: const AppSidebar(),
        body: ResponsiveScaffoldContainer(
          maxWidth: 620,
          child: Center(
            child: AdminLoadErrorCard(
              message: _loadError!,
              onRetry: () => _loadCustomers(reset: true),
            ),
          ),
        ),
      );
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
            onPressed: () {
              setState(() => _showSummaryInline = !_showSummaryInline);
            },
            icon: Icon(
              _showSummaryInline
                  ? Icons.analytics_outlined
                  : Icons.analytics_rounded,
            ),
          ),
          IconButton(
            tooltip: l.tr('screens_admin_customers_screen.040'),
            onPressed: () => _searchFocusNode.requestFocus(),
            icon: const Icon(Icons.search_rounded),
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
              if (_loadError != null) ...[
                AdminLoadErrorCard(
                  message: _loadError!,
                  onRetry: () => _loadCustomers(reset: true),
                ),
                const SizedBox(height: 16),
              ],
              if (_isLoadingCustomers)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              _buildPageHeader(totalCustomers),
              const SizedBox(height: 16),
              _buildSearchPanel(totalCustomers),
              if (_showSummaryInline) ...[
                const SizedBox(height: 16),
                _buildOverviewCard(totalCustomers),
              ],
              const SizedBox(height: 16),
              if (_customers.isEmpty)
                ShwakelCard(
                  padding: const EdgeInsets.all(28),
                  child: Center(
                    child: Text(
                      _searchController.text.trim().isEmpty
                          ? l.tr('screens_admin_customers_screen.038')
                          : l.tr('screens_admin_customers_screen.001'),
                      style: AppTheme.bodyAction,
                    ),
                  ),
                )
              else ...[
                _buildCustomersGrid(),
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

  Widget _buildPageHeader(int totalCustomers) {
    final l = context.loc;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
          ),
          child: const Icon(Icons.groups_rounded, color: AppTheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.tr('screens_admin_customers_screen.017'),
                style: AppTheme.h1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _countPill(icon: Icons.people_alt_rounded, label: '$totalCustomers'),
      ],
    );
  }

  Widget _buildSearchPanel(int totalCustomers) {
    final l = context.loc;
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: l.tr('screens_admin_customers_screen.040'),
              hintText: l.tr('screens_admin_customers_screen.023'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasQuery)
                    IconButton(
                      tooltip: l.tr('screens_admin_customers_screen.039'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _clearSearch,
                    ),
                  IconButton(
                    tooltip: l.tr('screens_admin_customers_screen.057'),
                    icon: _isLoadingCustomers
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.manage_search_rounded),
                    onPressed: _isLoadingCustomers
                        ? null
                        : () => _submitSearch(force: true),
                  ),
                ],
              ),
            ),
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _submitSearch(force: true),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(l.text('الأحدث', 'Newest')),
                selected: _sortMode == 'newest',
                onSelected: (_) => _changeSortMode('newest'),
              ),
              ChoiceChip(
                label: Text(l.text('الأكثر ربحًا', 'Most profitable')),
                selected: _sortMode == 'profit_desc',
                onSelected: (_) => _changeSortMode('profit_desc'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.tr(
                    'screens_admin_customers_screen.043',
                    params: {
                      'shown': '${_customers.length}',
                      'total': '$totalCustomers',
                    },
                  ),
                  style: AppTheme.caption,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _showSummaryInline = !_showSummaryInline);
                },
                icon: Icon(
                  _showSummaryInline
                      ? Icons.expand_less_rounded
                      : Icons.query_stats_rounded,
                  size: 18,
                ),
                label: Text(l.tr('screens_admin_customers_screen.049')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomersGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = constraints.maxWidth >= 760;
        if (!useGrid) {
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _customers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _customerCard(_customers[index]),
          );
        }

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: _customers
              .map(
                (customer) => SizedBox(
                  width: (constraints.maxWidth - 14) / 2,
                  child: _customerCard(customer),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _customerCard(Map<String, dynamic> customer) {
    return AdminCustomerCard(
      customer: customer,
      onTap: () => _openCustomerDetails(customer),
      onResendCredentials: _canManageUsers
          ? () => _resendCustomerCredentials(customer)
          : null,
      onSendOtp: _canManageUsers ? () => _sendCustomerOtp(customer) : null,
    );
  }

  void _changeSortMode(String mode) {
    if (_sortMode == mode) {
      return;
    }
    setState(() => _sortMode = mode);
    _loadCustomers(reset: true);
  }

  Widget _buildOverviewCard(int totalCustomers) {
    final totalBalances = (_summary['totalBalances'] as num?)?.toDouble() ?? 0;
    final totalPrintingDebt =
        (_summary['totalPrintingDebt'] as num?)?.toDouble() ?? 0;
    final printingDebtUsers =
        (_summary['printingDebtUsersCount'] as num?)?.toInt() ?? 0;
    final totalAdminProfits =
        (_summary['totalAdminProfits'] as num?)?.toDouble() ?? 0;

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
                'أرباح التطبيق',
                CurrencyFormatter.formatAmount(totalAdminProfits),
                Icons.analytics_rounded,
                AppTheme.accent,
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

  void _onSearchChanged(String value) {
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    _submitSearch(force: true);
    setState(() {});
  }

  void _submitSearch({bool force = false}) {
    final query = _searchController.text.trim();
    if (!force && query == _lastSubmittedQuery) {
      return;
    }
    _lastSubmittedQuery = query;
    _loadCustomers(reset: true);
  }
}
