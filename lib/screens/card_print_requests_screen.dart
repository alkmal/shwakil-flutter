import 'package:flutter/material.dart';

import '../localization/index.dart';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
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
  bool _isSubmitting = false;

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
        _authService.currentUser(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = List<Map<String, dynamic>>.from(results[0] as List);
        _user = results[1] as Map<String, dynamic>?;
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

  Future<void> _showCreateRequestDialog() async {
    final l = context.loc;
    final valueController = TextEditingController();
    final quantityController = TextEditingController(text: '10');
    final notesController = TextEditingController();
    var cardType = 'standard';

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
            final unitAmount = cardType == 'single_use' ? 0.01 : value;
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
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: cardType,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_card_print_requests_screen.008'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'standard',
                          child: Text(
                            l.tr('screens_card_print_requests_screen.009'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'single_use',
                          child: Text(
                            l.tr('screens_card_print_requests_screen.010'),
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
                    TextField(
                      controller: valueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      enabled: cardType == 'standard',
                      decoration: InputDecoration(
                        labelText: cardType == 'single_use'
                            ? l.tr('screens_card_print_requests_screen.011')
                            : l.tr('screens_card_print_requests_screen.012'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_card_print_requests_screen.013'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_card_print_requests_screen.014'),
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
    final availableBalance =
        (_user?['availablePrintingBalance'] as num?)?.toDouble() ?? 0;
    final printFee = (_user?['customCardPrintRequestFeePercent'] as num?)
        ?.toDouble();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_card_print_requests_screen.018')),
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
                        l.tr('screens_card_print_requests_screen.018'),
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.tr('screens_card_print_requests_screen.019'),
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _heroBadge(
                            l.tr('screens_card_print_requests_screen.020'),
                            CurrencyFormatter.ils(availableBalance),
                          ),
                          _heroBadge(
                            l.tr('screens_card_print_requests_screen.021'),
                            '${printFee?.toStringAsFixed(2) ?? l.tr('screens_card_print_requests_screen.022')}%',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ShwakelButton(
                        label: l.tr('screens_card_print_requests_screen.023'),
                        icon: Icons.print_rounded,
                        onPressed: _showCreateRequestDialog,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
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

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final l = context.loc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ShwakelCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request['statusLabel']?.toString() ??
                        l.tr('screens_card_print_requests_screen.025'),
                    style: AppTheme.h3,
                  ),
                ),
                _statusChip(request['status']?.toString() ?? 'pending_review'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metaItem(
                  l.tr('screens_card_print_requests_screen.026'),
                  request['cardType'] == 'single_use'
                      ? l.tr('screens_card_print_requests_screen.027')
                      : l.tr('screens_card_print_requests_screen.028'),
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
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  l.tr(
                    'screens_card_print_requests_screen.033',
                    params: {'notes': '${request['customerNotes']}'},
                  ),
                  style: AppTheme.bodyAction,
                ),
              ),
            if ((request['adminNotes']?.toString().trim().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
          ],
        ),
      ),
    );
  }

  Widget _heroBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTheme.caption.copyWith(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold.copyWith(color: Colors.white)),
        ],
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

  Widget _statusChip(String status) {
    final l = context.loc;
    final color = switch (status) {
      'approved' => AppTheme.primary,
      'printing' => AppTheme.warning,
      'ready' => AppTheme.success,
      'completed' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.textSecondary,
    };
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
