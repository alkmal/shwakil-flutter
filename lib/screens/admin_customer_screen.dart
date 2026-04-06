import 'dart:async';
import 'package:flutter/material.dart';
import '../services/index.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/admin/admin_enums.dart';
import '../widgets/admin/admin_transaction_audit_card.dart';
import '../widgets/admin/admin_pagination_footer.dart';
import '../widgets/admin/admin_section_header.dart';

class AdminCustomerScreen extends StatefulWidget {
  const AdminCustomerScreen({
    super.key,
    required this.customer,
    this.canExport = false,
    this.canManageUsers = false,
  });

  final Map<String, dynamic> customer;
  final bool canExport;
  final bool canManageUsers;

  @override
  State<AdminCustomerScreen> createState() => _AdminCustomerScreenState();
}

class _AdminCustomerScreenState extends State<AdminCustomerScreen> {
  final _api = ApiService();
  final _maxDevicesController = TextEditingController();
  final _printingDebtLimitController = TextEditingController();
  final _topupFeeController = TextEditingController();
  final _withdrawFeeController = TextEditingController();
  final _transferFeeController = TextEditingController();
  final _redeemFeeController = TextEditingController();
  final _resellFeeController = TextEditingController();
  final _cardPrintRequestFeeController = TextEditingController();

  late Map<String, dynamic> _customer;
  List<Map<String, dynamic>> _transactions = const [];
  List<Map<String, dynamic>> _devices = const [];
  bool _firstLoad = true;
  bool _busy = false; // Combined busy state for simplicity in UI
  String _role = 'basic';
  String _verification = 'unverified';
  int _txPage = 1;
  static const _perPage = 10;
  AdminTransactionAuditFilter _auditFilter = AdminTransactionAuditFilter.all;

  @override
  void initState() {
    super.initState();
    _customer = Map<String, dynamic>.from(widget.customer);
    _syncFields();
    _loadCustomer(full: true);
  }

  @override
  void dispose() {
    _maxDevicesController.dispose();
    _printingDebtLimitController.dispose();
    _topupFeeController.dispose();
    _withdrawFeeController.dispose();
    _transferFeeController.dispose();
    _redeemFeeController.dispose();
    _resellFeeController.dispose();
    _cardPrintRequestFeeController.dispose();
    super.dispose();
  }

  void _syncFields() {
    _role = _customer['role']?.toString() ?? 'basic';
    _verification =
        _customer['transferVerificationStatus']?.toString() ?? 'unverified';
    _maxDevicesController.text =
        ((_customer['maxDevices'] as num?)?.toInt() ?? 1).toString();
    _printingDebtLimitController.text =
        ((_customer['printingDebtLimit'] as num?)?.toDouble() ?? 20)
            .toStringAsFixed(2);
    _topupFeeController.text = _formatPct(_customer['customTopupFeePercent']);
    _withdrawFeeController.text = _formatPct(
      _customer['customWithdrawFeePercent'],
    );
    _transferFeeController.text = _formatPct(
      _customer['customTransferFeePercent'],
    );
    _redeemFeeController.text = _formatPct(
      _customer['customCardRedeemFeePercent'],
    );
    _resellFeeController.text = _formatPct(
      _customer['customCardResellFeePercent'],
    );
    _cardPrintRequestFeeController.text = _formatPct(
      _customer['customCardPrintRequestFeePercent'],
    );
  }

  String _formatPct(Object? v) {
    if (v == null) return '';
    final d = (v as num).toDouble();
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  Future<void> _loadCustomer({bool full = false}) async {
    setState(() => full ? _firstLoad = true : _busy = true);
    try {
      final id = _customer['id']?.toString() ?? '';
      final filter = _auditFilter == AdminTransactionAuditFilter.nearBranch
          ? 'near_branch'
          : (_auditFilter == AdminTransactionAuditFilter.outsideBranches
                ? 'outside_branches'
                : 'all');

      final results = await Future.wait([
        _api.getAdminCustomerTransactions(id, locationFilter: filter),
        _api.getAdminUserDevices(id),
      ]);

      if (!mounted) return;
      final txData = results[0];
      final dvData = results[1];

      setState(() {
        _customer = Map<String, dynamic>.from(
          txData['customer'] as Map? ?? _customer,
        );
        _transactions = List<Map<String, dynamic>>.from(
          txData['transactions'] as List? ?? [],
        );
        _devices = List<Map<String, dynamic>>.from(
          dvData['devices'] as List? ?? [],
        );
        _txPage = 1;
        _syncFields();
        _firstLoad = false;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _firstLoad = false;
          _busy = false;
        });
      }
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(e),
      );
    }
  }

  Future<void> _updateAccount() async {
    setState(() => _busy = true);
    try {
      final debt = double.tryParse(_printingDebtLimitController.text) ?? 20;
      final payload = await _api.updateAdminUserAccountControls(
        userId: _customer['id'].toString(),
        isDisabled: _customer['isDisabled'] == true,
        transferVerificationStatus: _verification,
        role: _role,
        printingDebtLimit: debt,
        customTopupFeePercent: double.tryParse(_topupFeeController.text),
        customWithdrawFeePercent: double.tryParse(_withdrawFeeController.text),
        customTransferFeePercent: double.tryParse(_transferFeeController.text),
        customCardRedeemFeePercent: double.tryParse(_redeemFeeController.text),
        customCardResellFeePercent: double.tryParse(_resellFeeController.text),
        customCardPrintRequestFeePercent: double.tryParse(
          _cardPrintRequestFeeController.text,
        ),
      );
      if (mounted) {
        setState(() {
          _customer = Map<String, dynamic>.from(payload['user']);
          _syncFields();
          _busy = false;
        });
        AppAlertService.showSuccess(
          context,
          message: 'تم تحديث بيانات العميل بنجاح.',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      AppAlertService.showError(
        context,
        message: ErrorMessageService.sanitize(e),
      );
    }
  }

  Future<void> _resendAccountDetails() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إعادة إرسال بيانات المستخدم'),
        content: const Text(
          'سيتم إنشاء كلمة مرور جديدة لهذا المستخدم ثم إرسال بيانات الدخول إلى واتساب الحساب. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد الإرسال'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _busy = true);
    try {
      final response = await _api.resendAdminUserAccountDetails(
        userId: _customer['id'].toString(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      await AppAlertService.showSuccess(
        context,
        title: 'تم الإرسال',
        message: response['message']?.toString() ??
            'تم إنشاء كلمة مرور جديدة وإرسال بيانات المستخدم عبر واتساب.',
      );
      await _loadCustomer(full: true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      await AppAlertService.showError(
        context,
        title: 'تعذر الإرسال',
        message: ErrorMessageService.sanitize(e),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_firstLoad) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name = _customer['fullName'] ?? _customer['username'] ?? 'عميل شواكل';

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(name),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(74),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const TabBar(
                  isScrollable: true,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: EdgeInsets.all(6),
                  labelPadding: EdgeInsets.symmetric(horizontal: 14),
                  tabs: [
                    Tab(
                      text: 'نظرة عامة',
                      icon: Icon(Icons.info_outline_rounded, size: 20),
                    ),
                    Tab(
                      text: 'سجل الحركات',
                      icon: Icon(Icons.receipt_long_rounded, size: 20),
                    ),
                    Tab(
                      text: 'الإدارة والرسوم',
                      icon: Icon(Icons.manage_accounts_rounded, size: 20),
                    ),
                    Tab(
                      text: 'الصلاحيات',
                      icon: Icon(Icons.security_rounded, size: 20),
                    ),
                    Tab(
                      text: 'الأجهزة',
                      icon: Icon(Icons.devices_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildOverviewTab(),
            _buildTransactionsTab(),
            _buildManagementTab(),
            _buildPermissionsTab(),
            _buildDevicesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            _buildProfileHero(),
            if (widget.canManageUsers) ...[
              const SizedBox(height: 16),
              ShwakelCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إجراءات سريعة', style: AppTheme.h3),
                    const SizedBox(height: 10),
                    Text(
                      'إعادة إرسال بيانات المستخدم عبر واتساب ستنشئ كلمة مرور جديدة تلقائيًا قبل الإرسال.',
                      style: AppTheme.bodyAction,
                    ),
                    const SizedBox(height: 16),
                    ShwakelButton(
                      label: 'إعادة إرسال بيانات المستخدم',
                      icon: Icons.mark_chat_unread_rounded,
                      onPressed: _busy ? null : _resendAccountDetails,
                      isLoading: _busy,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildMetricCard(
                    'الرصيد الحالي',
                    CurrencyFormatter.ils(
                      ((_customer['balance'] as num?) ?? 0).toDouble(),
                    ),
                    Icons.account_balance_wallet_rounded,
                    AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    'حالة الحساب',
                    _customer['isDisabled'] == true ? 'معطل' : 'نشط',
                    Icons.verified_user_rounded,
                    _customer['isDisabled'] == true
                        ? AppTheme.error
                        : AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('بيانات التواصل', style: AppTheme.h3),
                  const SizedBox(height: 16),
                  _infoRow('اسم المستخدم', _customer['username'] ?? '-'),
                  _infoRow('الاسم الرباعي', _customer['fullName'] ?? '-'),
                  _infoRow('الواتساب', _customer['whatsapp'] ?? '-'),
                  _infoRow('تاريخ الانضمام', _customer['createdAt'] ?? '-'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHero() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              (_customer['username']
                      ?.toString()
                      .substring(0, 1)
                      .toUpperCase() ??
                  'U'),
              style: AppTheme.h1.copyWith(color: Colors.white, fontSize: 32),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _customer['fullName'] ?? _customer['username'],
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                Text(
                  _customer['roleLabel'] ?? 'عميل أساسي',
                  style: AppTheme.caption.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_customer['isVerified'] == true)
            const Icon(Icons.verified_rounded, color: Colors.white, size: 30),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    final paged = _transactions
        .skip((_txPage - 1) * _perPage)
        .take(_perPage)
        .toList();
    final lastPage = (_transactions.length / _perPage)
        .ceil()
        .clamp(1, 999)
        .toInt();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            AdminSectionHeader(
              title: 'سجل حركات العميل',
              subtitle:
                  'استعرض الحركات المالية والعمليات المرتبطة بهذا العميل.',
              icon: Icons.history_rounded,
              trailing: DropdownButton<AdminTransactionAuditFilter>(
                value: _auditFilter,
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _auditFilter = v);
                    _loadCustomer();
                  }
                },
                items: const [
                  DropdownMenuItem(
                    value: AdminTransactionAuditFilter.all,
                    child: Text('الكل'),
                  ),
                  DropdownMenuItem(
                    value: AdminTransactionAuditFilter.nearBranch,
                    child: Text('قرب الفروع'),
                  ),
                  DropdownMenuItem(
                    value: AdminTransactionAuditFilter.outsideBranches,
                    child: Text('خارج الفروع'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (_transactions.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text('لا توجد حركات حديثة.', style: AppTheme.caption),
                ),
              )
            else ...[
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: paged.length,
                itemBuilder: (c, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AdminTransactionAuditCard(transaction: paged[i]),
                ),
              ),
              const SizedBox(height: 24),
              AdminPaginationFooter(
                currentPage: _txPage,
                lastPage: lastPage,
                onPageChanged: (p) => setState(() => _txPage = p),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManagementTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إدارة الحساب والرسوم', style: AppTheme.h3),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: _verification,
                    decoration: const InputDecoration(
                      labelText: 'حالة التوثيق (تفعيل التحقق)',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'restricted',
                        child: Text('عضوية مقيدة'),
                      ),
                      DropdownMenuItem(
                        value: 'verified_member',
                        child: Text('عضوية موثقة'),
                      ),
                      DropdownMenuItem(
                        value: 'advanced_member',
                        child: Text('عضوية مطورة'),
                      ),
                      DropdownMenuItem(
                        value: 'unverified',
                        child: Text('غير موثق'),
                      ),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('قيد المراجعة'),
                      ),
                      DropdownMenuItem(
                        value: 'approved',
                        child: Text('موثق / مفعل'),
                      ),
                      DropdownMenuItem(value: 'rejected', child: Text('مرفوض')),
                    ],
                    onChanged: (v) => setState(() => _verification = v!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'دور الحساب'),
                    items: const [
                      DropdownMenuItem(
                        value: 'basic',
                        child: Text('مستخدم عادي'),
                      ),
                      DropdownMenuItem(
                        value: 'support',
                        child: Text('فريق الدعم'),
                      ),
                      DropdownMenuItem(value: 'admin', child: Text('مدير فني')),
                    ],
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _printingDebtLimitController,
                    decoration: const InputDecoration(
                      labelText: 'سقف دين الطباعة (₪)',
                      suffixText: '₪',
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('رسوم مخصصة لهذا العميل (%)', style: AppTheme.bodyBold),
                  const SizedBox(height: 16),
                  _feeGrid(),
                  const SizedBox(height: 40),
                  ShwakelButton(
                    label: 'حفظ التغييرات',
                    icon: Icons.save_rounded,
                    onPressed: _updateAccount,
                    isLoading: _busy,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feeGrid() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _feeField('الإيداع', _topupFeeController),
        _feeField('السحب', _withdrawFeeController),
        _feeField('التحويل', _transferFeeController),
        _feeField('الاسترداد', _redeemFeeController),
        _feeField('إعادة البيع', _resellFeeController),
        _feeField('طلب الطباعة', _cardPrintRequestFeeController),
      ],
    );
  }

  Widget _buildPermissionsTab() {
    final perms = Map<String, dynamic>.from(
      _customer['permissions'] as Map? ?? {},
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: ShwakelCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('صلاحيات البطاقات والإدارة', style: AppTheme.h3),
              const SizedBox(height: 16),
              _permItem('إصدار بطاقات رصيد', 'canIssueCards', perms),
              _permItem('طلب طباعة البطاقات', 'canRequestCardPrinting', perms),
              _permItem('إصدار أجزاء الشيكل', 'canIssueSubShekelCards', perms),
              _permItem(
                'إصدار بطاقات عالية القيمة',
                'canIssueHighValueCards',
                perms,
              ),
              _permItem(
                'إعادة تفعيل البطاقات المستخدمة',
                'canResellCards',
                perms,
              ),
              _permItem(
                'مراجعة طلبات طباعة البطاقات',
                'canReviewCardPrintRequests',
                perms,
              ),
              _permItem(
                'تجهيز وطباعة الطلبات',
                'canPrepareCardPrintRequests',
                perms,
              ),
              _permItem(
                'إكمال وتسليم الطلبات',
                'canFinalizeCardPrintRequests',
                perms,
              ),
              if (widget.canManageUsers)
                _permItem('إدارة المستخدمين الآخرين', 'canManageUsers', perms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سياسة الأجهزة ونقاط الوصول', style: AppTheme.h3),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _maxDevicesController,
                    decoration: const InputDecoration(
                      labelText: 'الحد الأقصى للأجهزة المسموح بها',
                    ),
                  ),
                  const SizedBox(height: 24),
                  ShwakelButton(
                    label: 'تحديث سياسة الأجهزة',
                    icon: Icons.phonelink_lock_rounded,
                    isSecondary: true,
                    onPressed: _saveDevicePolicy,
                    isLoading: _busy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AdminSectionHeader(
              title: 'الأجهزة النشطة',
              icon: Icons.smartphone_rounded,
            ),
            if (_devices.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('لا توجد أجهزة مرتبطة بهذا الحساب.'),
                ),
              )
            else
              ..._devices.map(_buildDeviceTile),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(Map<String, dynamic> d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.smartphone_rounded,
              color: d['isActiveDevice'] == true
                  ? AppTheme.success
                  : AppTheme.textTertiary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d['deviceName'] ?? 'جهاز غير معروف',
                    style: AppTheme.bodyBold,
                  ),
                  Text(
                    'معرف الجهاز: ${d['deviceId']}',
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: AppTheme.error),
              onPressed: () => _releaseDevice(d),
            ),
          ],
        ),
      ),
    );
  }

  // UI Helpers
  Widget _buildMetricCard(
    String title,
    String val,
    IconData icon,
    Color color,
  ) {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title, style: AppTheme.caption),
          Text(val, style: AppTheme.h3),
        ],
      ),
    );
  }

  Widget _infoRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: AppTheme.bodyAction),
        Text(v, style: AppTheme.bodyBold),
      ],
    ),
  );
  Widget _feeField(String l, TextEditingController c) => SizedBox(
    width: 140,
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: l, suffixText: '%'),
    ),
  );
  Widget _permItem(String l, String k, Map<String, dynamic> p) =>
      SwitchListTile(
        title: Text(l, style: AppTheme.bodyText),
        value: p[k] == true,
        onChanged: (v) async {
          p[k] = v;
          await _savePermissions(p);
        },
        activeThumbColor: AppTheme.primary,
        contentPadding: EdgeInsets.zero,
      );

  // Partial handlers
  Future<void> _savePermissions(Map<String, dynamic> p) async {
    setState(() => _busy = true);
    try {
      final res = await _api.updateAdminUserCardPermissions(
        userId: _customer['id'].toString(),
        canIssueCards: p['canIssueCards'] == true,
        canIssueSubShekelCards: p['canIssueSubShekelCards'] == true,
        canIssueHighValueCards: p['canIssueHighValueCards'] == true,
        canIssuePrivateCards: p['canIssuePrivateCards'] == true,
        canResellCards: p['canResellCards'] == true,
        canRequestCardPrinting: p['canRequestCardPrinting'] == true,
        canReviewCardPrintRequests: p['canReviewCardPrintRequests'] == true,
        canPrepareCardPrintRequests: p['canPrepareCardPrintRequests'] == true,
        canFinalizeCardPrintRequests: p['canFinalizeCardPrintRequests'] == true,
        canManageUsers: p['canManageUsers'] == true,
      );
      setState(() {
        _customer = Map<String, dynamic>.from(res['user']);
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDevicePolicy() async {
    setState(() => _busy = true);
    try {
      final max = int.tryParse(_maxDevicesController.text) ?? 1;
      final res = await _api.updateAdminUserDevicePolicy(
        userId: _customer['id'].toString(),
        allowMultiDevice: max > 1,
        maxDevices: max,
      );
      setState(() {
        _customer = Map<String, dynamic>.from(res['user']);
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _releaseDevice(Map<String, dynamic> d) async {
    try {
      await _api.releaseAdminUserDevice(
        userId: _customer['id'].toString(),
        deviceRecordId: d['id'].toString(),
      );
      _loadCustomer();
    } catch (_) {}
  }
}
