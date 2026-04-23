import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class CardPrintRequestsScreen extends StatefulWidget {
  const CardPrintRequestsScreen({super.key});

  @override
  State<CardPrintRequestsScreen> createState() =>
      _CardPrintRequestsScreenState();
}

class _CardPrintRequestsScreenState extends State<CardPrintRequestsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _requests = const [];
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _isAuthorized = false;
  bool _isSubmitting = false;

  Map<String, dynamic> get _subUserOperationalLimits =>
      Map<String, dynamic>.from(
        _user?['subUserOperationalLimits'] as Map? ?? const {},
      );

  bool get _isSubUser => _user?['isSubUser'] == true;

  double? _limitAsDouble(String key) =>
      (_subUserOperationalLimits[key] as num?)?.toDouble();

  bool get _isDriverAccount => _user?['role']?.toString() == 'driver';

  String _cardTypeLabel(BuildContext context, String cardType) {
    final l = context.loc;
    return switch (cardType) {
      'single_use' => l.tr('screens_card_print_requests_screen.027'),
      'delivery' => l.tr('shared.delivery_card_label'),
      _ => l.tr('screens_card_print_requests_screen.028'),
    };
  }

  String _cardTypeUsageNote(String cardType) {
    return cardType == 'delivery'
        ? context.loc.tr('shared.delivery_card_payments_note')
        : '';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = context.loc;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getMyCardPrintRequests(),
        _refreshAndReadCurrentUser(),
      ]);
      if (!mounted) {
        return;
      }
      final user = results[1] as Map<String, dynamic>?;
      final permissions = AppPermissions.fromUser(user);
      setState(() {
        _requests = List<Map<String, dynamic>>.from(results[0] as List);
        _user = user;
        _isAuthorized = permissions.canRequestCardPrinting;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: l.tr('screens_card_print_requests_screen.001'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<Map<String, dynamic>?> _refreshAndReadCurrentUser() async {
    await _authService.refreshCurrentUser();
    return _authService.currentUser();
  }

  Future<void> _showCreateRequestDialog() async {
    if (!_isAuthorized) {
      return;
    }
    final l = context.loc;
    final valueController = TextEditingController();
    final quantityController = TextEditingController(text: '10');
    final notesController = TextEditingController();
    var cardType = _isDriverAccount ? 'delivery' : 'standard';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            final value = double.tryParse(valueController.text.trim()) ?? 0;
            final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
            if (quantity <= 0 || (cardType == 'standard' && value <= 0)) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.002'),
                message: l.tr('screens_card_print_requests_screen.003'),
              );
              return;
            }

            final availableBalance =
                (_user?['availablePrintingBalance'] as num?)?.toDouble() ?? 0;
            final feePercent =
                (_user?['customCardPrintRequestFeePercent'] as num?)
                    ?.toDouble() ??
                0;
            final unitAmount =
                (cardType == 'single_use' || cardType == 'delivery')
                ? 0.01
                : value;
            final baseAmount = unitAmount * quantity;
            final feeAmount = baseAmount * (feePercent / 100);
            final totalAmount = baseAmount + feeAmount;
            if (totalAmount > availableBalance) {
              final contact = await ContactInfoService.getContactInfo();
              if (!dialogContext.mounted) {
                return;
              }
              await _showOverLimitDialog(
                dialogContext,
                availableBalance: availableBalance,
                totalAmount: totalAmount,
                feePercent: feePercent,
                supportWhatsapp: ContactInfoService.supportWhatsapp(contact),
              );
              return;
            }

            setDialogState(() => _isSubmitting = true);
            try {
              final response = await _apiService.requestCardPrint(
                value: value,
                quantity: quantity,
                cardType: cardType,
                notes: notesController.text,
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
                title: l.tr('screens_card_print_requests_screen.004'),
                message:
                    response['message']?.toString() ??
                    l.tr('screens_card_print_requests_screen.005'),
              );
              await _load();
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => _isSubmitting = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_card_print_requests_screen.006'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(l.tr('screens_card_print_requests_screen.007')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSubUser) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          l.tr(
                            'screens_card_print_requests_screen.049',
                            params: {
                              'limit': CurrencyFormatter.ils(
                                _limitAsDouble('printRequestMaxAmount') ?? 0,
                              ),
                              'debtLimit': CurrencyFormatter.ils(
                                _limitAsDouble('printingDebtLimit') ?? 0,
                              ),
                            },
                          ),
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: cardType,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_card_print_requests_screen.008',
                        ),
                      ),
                      items: _isDriverAccount
                          ? [
                              DropdownMenuItem(
                                value: 'delivery',
                                child: Text(l.tr('shared.delivery_card_label')),
                              ),
                            ]
                          : [
                              DropdownMenuItem(
                                value: 'standard',
                                child: Text(
                                  l.tr(
                                    'screens_card_print_requests_screen.009',
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'single_use',
                                child: Text(
                                  l.tr(
                                    'screens_card_print_requests_screen.010',
                                  ),
                                ),
                              ),
                            ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => cardType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (cardType == 'delivery')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySoft.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          l.tr('shared.delivery_card_print_note'),
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (cardType == 'delivery') const SizedBox(height: 12),
                    TextField(
                      controller: valueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: cardType == 'standard',
                      decoration: InputDecoration(
                        labelText:
                            cardType == 'single_use' || cardType == 'delivery'
                            ? l.tr('screens_card_print_requests_screen.011')
                            : l.tr('screens_card_print_requests_screen.012'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_card_print_requests_screen.013',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_card_print_requests_screen.014',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isSubmitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_card_print_requests_screen.015')),
              ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : submit,
                child: Text(
                  _isSubmitting
                      ? l.tr('screens_card_print_requests_screen.016')
                      : l.tr('screens_card_print_requests_screen.017'),
                ),
              ),
            ],
          );
        },
      ),
    );

    valueController.dispose();
    quantityController.dispose();
    notesController.dispose();
    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showOverLimitDialog(
    BuildContext dialogContext, {
    required double availableBalance,
    required double totalAmount,
    required double feePercent,
    required String supportWhatsapp,
  }) async {
    final l = context.loc;
    await showDialog<void>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(l.tr('screens_card_print_requests_screen.041')),
        content: Text(
          l.tr(
            'screens_card_print_requests_screen.042',
            params: {
              'available': CurrencyFormatter.ils(availableBalance),
              'total': CurrencyFormatter.ils(totalAmount),
              'fee': feePercent.toStringAsFixed(2),
              'phone': supportWhatsapp,
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.tr('screens_card_print_requests_screen.043')),
          ),
        ],
      ),
    );
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
          title: Text(l.tr('screens_card_print_requests_screen.018')),
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
                  l.tr('screens_card_print_requests_screen.037'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final availableBalance =
        (_user?['availablePrintingBalance'] as num?)?.toDouble() ?? 0;
    final printFee = (_user?['customCardPrintRequestFeePercent'] as num?)
        ?.toDouble();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_card_print_requests_screen.018')),
        actions: [
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
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            useSafeArea: false,
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingLg,
              8,
              AppTheme.spacingLg,
              AppTheme.spacingLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPrintInfoCard(
                  availableBalance: availableBalance,
                  printFee: printFee,
                ),
                if (_isSubUser) ...[
                  const SizedBox(height: 12),
                  ShwakelCard(
                    padding: const EdgeInsets.all(16),
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    child: Text(
                      l.tr(
                        'screens_card_print_requests_screen.047',
                        params: {
                          'limit': CurrencyFormatter.ils(
                            _limitAsDouble('printRequestMaxAmount') ?? 0,
                          ),
                          'debtLimit': CurrencyFormatter.ils(
                            _limitAsDouble('printingDebtLimit') ?? 0,
                          ),
                        },
                      ),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_requests.isEmpty)
                  ShwakelCard(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Text(
                        l.tr('screens_card_print_requests_screen.024'),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  )
                else
                  ..._requests.map(_buildRequestCard),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrintInfoCard({
    required double availableBalance,
    required double? printFee,
  }) {
    final l = context.loc;
    final feeLabel =
        '${printFee?.toStringAsFixed(2) ?? l.tr('screens_card_print_requests_screen.022')}%';
    final debtLimit = (_user?['printingDebtLimit'] as num?)?.toDouble() ?? 0;
    final currentDebt = (_user?['outstandingDebt'] as num?)?.toDouble() ?? 0;

    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.premium,
      gradient: const LinearGradient(
        colors: [Color(0xFF0F172A), Color(0xFF0F766E)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final actionButton = SizedBox(
            width: compact ? double.infinity : 190,
            child: ShwakelButton(
              label: l.tr('screens_card_print_requests_screen.023'),
              icon: Icons.print_rounded,
              onPressed: _showCreateRequestDialog,
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flex(
                direction: compact ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: [
                  if (compact)
                    _buildPrintInfoHeader()
                  else
                    Expanded(child: _buildPrintInfoHeader()),
                  SizedBox(width: compact ? 0 : 18, height: compact ? 18 : 0),
                  actionButton,
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildPrintMetricTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: l.tr('screens_card_print_requests_screen.020'),
                    value: CurrencyFormatter.ils(availableBalance),
                  ),
                  _buildPrintMetricTile(
                    icon: Icons.percent_rounded,
                    label: l.tr('screens_card_print_requests_screen.021'),
                    value: feeLabel,
                  ),
                  _buildPrintMetricTile(
                    icon: Icons.credit_score_rounded,
                    label: l.tr('screens_card_print_requests_screen.051'),
                    value: CurrencyFormatter.ils(debtLimit),
                  ),
                  _buildPrintMetricTile(
                    icon: Icons.trending_down_rounded,
                    label: l.tr('screens_card_print_requests_screen.052'),
                    value: CurrencyFormatter.ils(currentDebt),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrintInfoHeader() {
    final l = context.loc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.print_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.tr('screens_card_print_requests_screen.050'),
                style: AppTheme.h3.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l.tr('screens_card_print_requests_screen.019'),
          style: AppTheme.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.76),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPrintMetricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: AppTheme.isPhone(context) ? double.infinity : 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.tr('screens_admin_dashboard_screen.057'),
      message: l.tr('screens_card_print_requests_screen.053'),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final l = context.loc;
    final status = request['status']?.toString() ?? 'pending_review';
    final cardType = _cardTypeLabel(
      context,
      request['cardType']?.toString() ?? 'standard',
    );
    final quantityLabel = l.tr(
      'screens_card_print_requests_screen.030',
      params: {'count': '${request['quantity'] ?? 0}'},
    );
    final totalAmount = CurrencyFormatter.ils(
      (request['totalAmount'] as num?)?.toDouble() ?? 0,
    );
    final createdAt = _formatDateTime(
      request['createdAt']?.toString(),
      request['created_at']?.toString() ?? '-',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        onTap: () => _showRequestDetails(request),
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(22),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final iconCard = Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.print_rounded,
                color: _statusColor(status),
                size: 22,
              ),
            );
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        request['statusLabel']?.toString() ??
                            l.tr('screens_card_print_requests_screen.025'),
                        style: AppTheme.bodyBold.copyWith(fontSize: 16),
                      ),
                      _statusChip(status),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          request['statusLabel']?.toString() ??
                              l.tr('screens_card_print_requests_screen.025'),
                          style: AppTheme.bodyBold.copyWith(fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusChip(status),
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _miniMetaChip(
                      label: l.tr('screens_card_print_requests_screen.026'),
                      value: cardType,
                    ),
                    _miniMetaChip(
                      label: l.tr('screens_card_print_requests_screen.029'),
                      value: quantityLabel,
                    ),
                    _miniMetaChip(
                      label: l.tr('screens_card_print_requests_screen.032'),
                      value: totalAmount,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  createdAt,
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconCard,
                      const SizedBox(width: 12),
                      Expanded(child: content),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: AppTheme.textTertiary,
                      size: 22,
                    ),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconCard,
                const SizedBox(width: 12),
                Expanded(child: content),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_left_rounded,
                  color: AppTheme.textTertiary,
                  size: 22,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showRequestDetails(Map<String, dynamic> request) async {
    final l = context.loc;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text('تفاصيل طلب الطباعة', style: AppTheme.h3),
                    ),
                    _statusChip(
                      request['status']?.toString() ?? 'pending_review',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.026'),
                      _cardTypeLabel(
                        context,
                        request['cardType']?.toString() ?? 'standard',
                      ),
                    ),
                    if ((request['cardType']?.toString() ?? '') == 'delivery')
                      _metaItem(
                        l.tr('shared.usage_label'),
                        _cardTypeUsageNote(
                          request['cardType']?.toString() ?? 'standard',
                        ),
                      ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.029'),
                      l.tr(
                        'screens_card_print_requests_screen.030',
                        params: {'count': '${request['quantity'] ?? 0}'},
                      ),
                    ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.031'),
                      CurrencyFormatter.ils(
                        (request['cardValue'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.032'),
                      CurrencyFormatter.ils(
                        (request['totalAmount'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.044'),
                      request['sourceType'] == 'local'
                          ? l.tr('screens_card_print_requests_screen.045')
                          : l.tr('screens_card_print_requests_screen.046'),
                    ),
                    _metaItem(
                      l.tr('screens_card_print_requests_screen.047'),
                      _formatDateTime(
                        request['lastPrintedAt']?.toString(),
                        l.tr('screens_card_print_requests_screen.048'),
                      ),
                    ),
                  ],
                ),
                if ((request['customerNotes']?.toString().trim().isNotEmpty ??
                    false))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ShwakelCard(
                      padding: const EdgeInsets.all(14),
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(18),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Text(
                        l.tr(
                          'screens_card_print_requests_screen.033',
                          params: {'notes': '${request['customerNotes']}'},
                        ),
                        style: AppTheme.bodyAction,
                      ),
                    ),
                  ),
                if ((request['adminNotes']?.toString().trim().isNotEmpty ??
                    false))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ShwakelCard(
                      padding: const EdgeInsets.all(14),
                      color: AppTheme.surfaceMuted,
                      borderRadius: BorderRadius.circular(18),
                      shadowLevel: ShwakelShadowLevel.none,
                      child: Text(
                        l.tr(
                          'screens_card_print_requests_screen.034',
                          params: {'notes': '${request['adminNotes']}'},
                        ),
                        style: AppTheme.bodyAction.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold),
        ],
      ),
    );
  }

  Widget _miniMetaChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: AppTheme.caption.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'approved' => AppTheme.primary,
      'printing' => AppTheme.warning,
      'ready' => AppTheme.success,
      'completed' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.textSecondary,
    };
  }

  Widget _statusChip(String status) {
    final l = context.loc;
    final color = _statusColor(status);
    final label = switch (status) {
      'pending_review' => l.tr('screens_card_print_requests_screen.035'),
      'approved' => l.tr('screens_card_print_requests_screen.036'),
      'printing' => l.tr('screens_card_print_requests_screen.037'),
      'ready' => l.tr('screens_card_print_requests_screen.038'),
      'completed' => l.tr('screens_card_print_requests_screen.039'),
      'rejected' => l.tr('screens_card_print_requests_screen.040'),
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _formatDateTime(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}
