import 'package:flutter/material.dart';

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
  State<CardPrintRequestsScreen> createState() => _CardPrintRequestsScreenState();
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
        title: 'تعذر تحميل الطلبات',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _showCreateRequestDialog() async {
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
                title: 'بيانات غير مكتملة',
                message: 'أدخل قيمة البطاقة وعدد البطاقات بشكل صحيح.',
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
                title: 'تم إرسال الطلب',
                message:
                    response['message']?.toString() ??
                    'تم إرسال طلب طباعة البطاقات بنجاح.',
              );
              await _load();
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => _isSubmitting = false);
              await AppAlertService.showError(
                dialogContext,
                title: 'تعذر إرسال الطلب',
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: const Text('طلب طباعة بطاقات'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: cardType,
                      decoration: const InputDecoration(
                        labelText: 'نوع البطاقة',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'standard',
                          child: Text('بطاقات رصيد عادية'),
                        ),
                        DropdownMenuItem(
                          value: 'single_use',
                          child: Text('بطاقات استخدام مرة واحدة'),
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
                            ? 'القيمة ثابتة لبطاقات المرة الواحدة'
                            : 'قيمة البطاقة الواحدة',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد البطاقات',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات إضافية',
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
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : submit,
                child: Text(_isSubmitting ? 'جارٍ الإرسال...' : 'إرسال الطلب'),
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

  @override
  Widget build(BuildContext context) {
    final availableBalance =
        (_user?['availablePrintingBalance'] as num?)?.toDouble() ?? 0;
    final printFee =
        (_user?['customCardPrintRequestFeePercent'] as num?)?.toDouble();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('طلبات طباعة البطاقات')),
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
                        'طلبات طباعة البطاقات',
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'أرسل طلبك من هنا وسيتم خصم القيمة مباشرة من رصيدك، ثم تتابع الإدارة مراحل المراجعة والطباعة والتجهيز حتى الإكمال.',
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
                            'الرصيد المتاح للطباعة',
                            CurrencyFormatter.ils(availableBalance),
                          ),
                          _heroBadge(
                            'رسوم طلب الطباعة',
                            '${printFee?.toStringAsFixed(2) ?? 'الافتراضية'}%',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ShwakelButton(
                        label: 'طلب طباعة جديد',
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
                        'لا توجد طلبات طباعة سابقة حتى الآن.',
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
                    request['statusLabel']?.toString() ?? 'بانتظار المراجعة',
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
                  'النوع',
                  request['cardType'] == 'single_use'
                      ? 'مرة واحدة'
                      : 'بطاقات عادية',
                ),
                _metaItem('العدد', '${request['quantity'] ?? 0} بطاقة'),
                _metaItem(
                  'القيمة',
                  CurrencyFormatter.ils(
                    (request['cardValue'] as num?)?.toDouble() ?? 0,
                  ),
                ),
                _metaItem(
                  'الإجمالي',
                  CurrencyFormatter.ils(
                    (request['totalAmount'] as num?)?.toDouble() ?? 0,
                  ),
                ),
              ],
            ),
            if ((request['customerNotes']?.toString().trim().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  'ملاحظاتك: ${request['customerNotes']}',
                  style: AppTheme.bodyAction,
                ),
              ),
            if ((request['adminNotes']?.toString().trim().isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'ملاحظات الإدارة: ${request['adminNotes']}',
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
          Text(
            value,
            style: AppTheme.bodyBold.copyWith(color: Colors.white),
          ),
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
    final color = switch (status) {
      'approved' => AppTheme.primary,
      'printing' => AppTheme.warning,
      'ready' => AppTheme.success,
      'completed' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status == 'pending_review' ? 'مراجعة' : status,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
