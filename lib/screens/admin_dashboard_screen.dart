import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final DebtBookService _debtBookService = DebtBookService();
  Map<String, dynamic>? _user;
  Map<String, dynamic> _debtBookSnapshot = const {};
  bool _isLoading = true;
  bool _isAuthorized = false;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _authService.currentUser();
    final permissions = AppPermissions.fromUser(user);
    final isAuthorized = permissions.hasAdminWorkspaceAccess;
    if (!mounted) {
      return;
    }
    Map<String, dynamic> debtBookSnapshot = const {};
    if (user != null &&
        user['id'] != null &&
        permissions.canManageDebtBook) {
      final userId = user['id'].toString();
      debtBookSnapshot = await _debtBookService.getSnapshot(userId);
      if (ConnectivityService.instance.isOnline.value) {
        try {
          debtBookSnapshot = await _debtBookService.syncPending(
            userId: userId,
            api: _apiService,
          );
        } catch (_) {}
      }
    }

    setState(() {
      _user = user;
      _debtBookSnapshot = debtBookSnapshot;
      _isAuthorized = isAuthorized;
      _isLoading = false;
    });
  }

  Future<void> _ensurePdfFonts() async {
    _pdfRegularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    _pdfBoldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
  }

  List<Map<String, dynamic>> _sortedDebtCustomers() {
    final customers = List<Map<String, dynamic>>.from(
      (_debtBookSnapshot['customers'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    customers.sort((a, b) {
      final aBalance = (a['balance'] as num?)?.toDouble() ?? 0;
      final bBalance = (b['balance'] as num?)?.toDouble() ?? 0;
      return bBalance.compareTo(aBalance);
    });
    return customers;
  }

  String _buildDebtBookAdminReportText() {
    final l = context.loc;
    final summary = Map<String, dynamic>.from(
      _debtBookSnapshot['summary'] as Map? ?? const {},
    );
    final customers = _sortedDebtCustomers()
        .where((customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0)
        .toList();

    final buffer = StringBuffer();
    buffer.writeln(l.tr('screens_admin_dashboard_screen.072'));
    buffer.writeln(l.tr('screens_admin_dashboard_screen.073', params: {
      'count': '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
    }));
    buffer.writeln(l.tr('screens_admin_dashboard_screen.074', params: {
      'count': '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
    }));
    buffer.writeln(l.tr('screens_admin_dashboard_screen.075', params: {
      'amount': CurrencyFormatter.ils(
        (summary['totalDebt'] as num?)?.toDouble() ?? 0,
      ),
    }));
    buffer.writeln(l.tr('screens_admin_dashboard_screen.076', params: {
      'amount': CurrencyFormatter.ils(
        (summary['totalPaid'] as num?)?.toDouble() ?? 0,
      ),
    }));
    buffer.writeln('');
    buffer.writeln(l.tr('screens_admin_dashboard_screen.077'));
    if (customers.isEmpty) {
      buffer.writeln(l.tr('screens_admin_dashboard_screen.078'));
    } else {
      for (final customer in customers) {
        final phone = customer['phone']?.toString().trim() ?? '';
        buffer.writeln(l.tr('screens_admin_dashboard_screen.079', params: {
          'name': customer['fullName']?.toString() ?? '-',
          'phone': phone.isNotEmpty
              ? phone
              : l.tr('screens_admin_dashboard_screen.083'),
          'amount': CurrencyFormatter.ils(
            (customer['balance'] as num?)?.toDouble() ?? 0,
          ),
        }));
      }
    }
    return buffer.toString();
  }

  Future<pw.Document> _buildDebtBookAdminReportPdf() async {
    await _ensurePdfFonts();
    if (!mounted) {
      return pw.Document();
    }
    final l = context.loc;
    final summary = Map<String, dynamic>.from(
      _debtBookSnapshot['summary'] as Map? ?? const {},
    );
    final customers = _sortedDebtCustomers()
        .where((customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0)
        .toList();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(
            base: _pdfRegularFont!,
            bold: _pdfBoldFont!,
          ),
        ),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  l.tr('screens_admin_dashboard_screen.072'),
                  style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        l.tr('screens_admin_dashboard_screen.073', params: {
                          'count': '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
                        }),
                      ),
                      pw.Text(
                        l.tr('screens_admin_dashboard_screen.074', params: {
                          'count': '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
                        }),
                      ),
                      pw.Text(
                        l.tr('screens_admin_dashboard_screen.075', params: {
                          'amount': CurrencyFormatter.ils((summary['totalDebt'] as num?)?.toDouble() ?? 0),
                        }),
                      ),
                      pw.Text(
                        l.tr('screens_admin_dashboard_screen.076', params: {
                          'amount': CurrencyFormatter.ils((summary['totalPaid'] as num?)?.toDouble() ?? 0),
                        }),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  l.tr('screens_admin_dashboard_screen.077'),
                  style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
                ),
                pw.SizedBox(height: 8),
                if (customers.isEmpty)
                  pw.Text(l.tr('screens_admin_dashboard_screen.044'))
                else
                  pw.TableHelper.fromTextArray(
                    headerStyle: pw.TextStyle(font: _pdfBoldFont),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    cellAlignment: pw.Alignment.centerRight,
                    headers: [
                      l.tr('screens_admin_dashboard_screen.080'),
                      l.tr('screens_admin_dashboard_screen.081'),
                      l.tr('screens_admin_dashboard_screen.082'),
                    ],
                    data: customers.map((customer) {
                      final phone = customer['phone']?.toString().trim() ?? '';
                      return [
                        customer['fullName']?.toString() ?? '-',
                        phone.isNotEmpty
                            ? phone
                            : l.tr('screens_admin_dashboard_screen.083'),
                        CurrencyFormatter.ils(
                          (customer['balance'] as num?)?.toDouble() ?? 0,
                        ),
                      ];
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf;
  }

  Future<void> _copyDebtBookAdminReport() async {
    await Clipboard.setData(
      ClipboardData(text: _buildDebtBookAdminReportText()),
    );
    if (!mounted) {
      return;
    }
    await AppAlertService.showSuccess(
      context,
      title: context.loc.tr('screens_admin_dashboard_screen.068'),
      message: context.loc.tr('screens_admin_dashboard_screen.069'),
    );
  }

  Future<void> _printDebtBookAdminReport() async {
    try {
      final pdf = await _buildDebtBookAdminReportPdf();
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'admin_debt_book_report',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_dashboard_screen.070'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _shareDebtBookAdminReportPdf() async {
    try {
      final pdf = await _buildDebtBookAdminReportPdf();
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'admin_debt_book_report.pdf',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_dashboard_screen.071'),
        message: ErrorMessageService.sanitize(error),
      );
    }
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
          title: const SizedBox.shrink(),
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
                  l.tr('screens_admin_dashboard_screen.020'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final fullNameValue = _user?['fullName']?.toString().trim() ?? '';
    final usernameValue = _user?['username']?.toString().trim() ?? '';
    final fullName = fullNameValue.isNotEmpty
        ? fullNameValue
        : (usernameValue.isNotEmpty
              ? usernameValue
              : l.tr('screens_admin_dashboard_screen.003'));
    final permissions = AppPermissions.fromUser(_user);
    final adminCards = <_AdminEntry>[
      if (permissions.canManageCardPrintRequests ||
          permissions.canReviewCardPrintRequests ||
          permissions.canPrepareCardPrintRequests ||
          permissions.canFinalizeCardPrintRequests)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.004'),
          subtitle: l.tr('screens_admin_dashboard_screen.005'),
          icon: Icons.print_rounded,
          color: AppTheme.primary,
          routeName: '/admin-card-print-requests',
          badge: l.tr('screens_admin_dashboard_screen.021'),
        ),
      if (permissions.canViewCustomers)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.006'),
          subtitle: l.tr('screens_admin_dashboard_screen.007'),
          icon: Icons.people_alt_rounded,
          color: AppTheme.primary,
          routeName: '/admin-customers',
          badge: l.tr('screens_admin_dashboard_screen.022'),
        ),
      if (permissions.canReviewDevices)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.008'),
          subtitle: l.tr('screens_admin_dashboard_screen.009'),
          icon: Icons.devices_other_rounded,
          color: AppTheme.warning,
          routeName: '/admin-device-requests',
          badge: l.tr('screens_admin_dashboard_screen.023'),
        ),
      if (permissions.canReviewWithdrawals)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.010'),
          subtitle: l.tr('screens_admin_dashboard_screen.011'),
          icon: Icons.outbox_rounded,
          color: AppTheme.secondary,
          routeName: '/withdrawal-requests',
          badge: l.tr('screens_admin_dashboard_screen.024'),
        ),
      if (permissions.canReviewTopups)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.012'),
          subtitle: l.tr('screens_admin_dashboard_screen.013'),
          icon: Icons.add_card_rounded,
          color: AppTheme.accent,
          routeName: '/topup-requests',
          badge: l.tr('screens_admin_dashboard_screen.025'),
        ),
      if (permissions.canManageLocations)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.014'),
          subtitle: l.tr('screens_admin_dashboard_screen.015'),
          icon: Icons.map_rounded,
          color: AppTheme.secondary,
          routeName: '/admin-locations',
          badge: l.tr('screens_admin_dashboard_screen.026'),
        ),
      if (permissions.canManageSystemSettings)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.016'),
          subtitle: l.tr('screens_admin_dashboard_screen.017'),
          icon: Icons.settings_applications_rounded,
          color: AppTheme.textPrimary,
          routeName: '/admin-system-settings',
          badge: l.tr('screens_admin_dashboard_screen.027'),
        ),
      if (permissions.canManageSystemSettings)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.018'),
          subtitle: l.tr('screens_admin_dashboard_screen.019'),
          icon: Icons.rule_folder_rounded,
          color: AppTheme.secondary,
          routeName: '/admin-permissions',
          badge: l.tr('screens_admin_dashboard_screen.028'),
        ),
      if (permissions.canManageDebtBook)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.029'),
          subtitle: l.tr('screens_admin_dashboard_screen.030'),
          icon: Icons.menu_book_rounded,
          color: AppTheme.warning,
          routeName: '/admin-debt-book',
          badge: l.tr('screens_admin_dashboard_screen.031'),
        ),
    ];
    final debtSummary = Map<String, dynamic>.from(
      _debtBookSnapshot['summary'] as Map? ?? const {},
    );
    final debtCustomers = _sortedDebtCustomers();
    final topDebtors = debtCustomers
        .where((customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0)
        .take(3)
        .toList();
    final adminWidgets = adminCards.map((item) => _navCard(item)).toList();
    final showDebtTab = permissions.canManageDebtBook;

    return DefaultTabController(
      length: showDebtTab ? 2 : 1,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              tooltip: l.tr('screens_admin_dashboard_screen.056'),
              onPressed: _showHelpDialog,
              icon: const Icon(Icons.info_outline_rounded),
            ),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
        ),
        drawer: const AppSidebar(),
        body: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(fullName: fullName, sectionCount: adminCards.length),
              const SizedBox(height: 24),
              ShwakelCard(
                padding: const EdgeInsets.all(10),
                borderRadius: BorderRadius.circular(24),
                shadowLevel: ShwakelShadowLevel.soft,
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(4),
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.dashboard_customize_rounded),
                      text: l.tr('screens_admin_dashboard_screen.050'),
                    ),
                    if (showDebtTab)
                      Tab(
                        icon: const Icon(Icons.menu_book_rounded),
                        text: l.tr('screens_admin_dashboard_screen.034'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildAdminUnitsTab(adminCards: adminCards, adminWidgets: adminWidgets),
                    if (showDebtTab)
                      _buildDebtBookTab(
                        debtSummary: debtSummary,
                        topDebtors: topDebtors,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero({
    required String fullName,
    required int sectionCount,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: AppTheme.heroGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      borderColor: Colors.white.withValues(alpha: 0.18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identityBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.loc.tr('screens_admin_dashboard_screen.002'),
                style: AppTheme.h1.copyWith(color: Colors.white, height: 1.2),
              ),
              const SizedBox(height: 10),
              Text(
                context.loc.tr(
                  'screens_admin_dashboard_screen.description',
                  params: {'name': fullName},
                ),
                style: AppTheme.bodyAction.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _heroChip(
                    icon: Icons.manage_accounts_rounded,
                    label: fullName,
                  ),
                  _heroChip(
                    icon: Icons.grid_view_rounded,
                    label: context.loc.tr(
                      'screens_admin_dashboard_screen.053',
                      params: {'count': '$sectionCount'},
                    ),
                  ),
                ],
              ),
            ],
          );
          return identityBlock;
        },
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.tr('screens_admin_dashboard_screen.057'),
      message: l.tr('screens_admin_dashboard_screen.058'),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    String? actionLabel,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.dashboard_customize_rounded,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.h2.copyWith(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              actionLabel,
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
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

  Widget _buildAdminUnitsTab({
    required List<_AdminEntry> adminCards,
    required List<Widget> adminWidgets,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: context.loc.tr('screens_admin_dashboard_screen.050'),
            subtitle: context.loc.tr('screens_admin_dashboard_screen.051'),
            actionLabel: context.loc.tr(
              'screens_admin_dashboard_screen.052',
              params: {'count': '${adminCards.length}'},
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 1120
                  ? 3
                  : constraints.maxWidth > 740
                  ? 2
                  : 1;
              final childAspectRatio = constraints.maxWidth > 1120
                  ? 1.45
                  : constraints.maxWidth > 740
                  ? 1.18
                  : 1.32;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: childAspectRatio,
                children: adminWidgets,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDebtBookTab({
    required Map<String, dynamic> debtSummary,
    required List<Map<String, dynamic>> topDebtors,
  }) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: context.loc.tr('screens_admin_dashboard_screen.034'),
            subtitle: context.loc.tr('screens_admin_dashboard_screen.035'),
            actionLabel: context.loc.tr(
              'screens_admin_dashboard_screen.036',
              params: {
                'count':
                    '${(debtSummary['openCustomersCount'] as num?)?.toInt() ?? 0}',
              },
            ),
          ),
          const SizedBox(height: 16),
          ShwakelCard(
            onTap: () => Navigator.pushNamed(context, '/admin-debt-book'),
            padding: const EdgeInsets.all(22),
            borderRadius: BorderRadius.circular(26),
            shadowLevel: ShwakelShadowLevel.medium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.trending_up_rounded,
                        color: AppTheme.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.loc.tr('screens_admin_dashboard_screen.043'),
                            style: AppTheme.h3,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            topDebtors.isEmpty
                                ? context.loc.tr('screens_admin_dashboard_screen.044')
                                : context.loc.tr('screens_admin_dashboard_screen.045'),
                            style: AppTheme.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _reportActionChip(
                      icon: Icons.copy_all_rounded,
                      label: context.loc.tr('screens_admin_dashboard_screen.046'),
                      onTap: _copyDebtBookAdminReport,
                    ),
                    _reportActionChip(
                      icon: Icons.print_rounded,
                      label: context.loc.tr('screens_admin_dashboard_screen.047'),
                      onTap: _printDebtBookAdminReport,
                    ),
                    _reportActionChip(
                      icon: Icons.picture_as_pdf_rounded,
                      label: context.loc.tr('screens_admin_dashboard_screen.048'),
                      onTap: _shareDebtBookAdminReportPdf,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (topDebtors.isEmpty)
                  Text(
                    context.loc.tr('screens_admin_dashboard_screen.049'),
                    style: AppTheme.bodyAction.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  )
                else
                  ...topDebtors.map(
                    (customer) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _debtCustomerRow(customer),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navCard(_AdminEntry item) {
    return ShwakelCard(
      onTap: () => Navigator.pushNamed(context, item.routeName),
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      borderColor: item.color.withValues(alpha: 0.10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      item.color.withValues(alpha: 0.16),
                      item.color.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(item.icon, color: item.color, size: 30),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.badge,
                  style: AppTheme.caption.copyWith(
                    color: item.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.h3.copyWith(color: item.color, height: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                context.loc.tr('screens_admin_dashboard_screen.084'),
                style: AppTheme.bodyBold.copyWith(color: item.color),
              ),
              const Spacer(),
              Icon(Icons.arrow_back_rounded, color: item.color, size: 24),
            ],
          ),
        ],
      ),
    );
  }

  Widget _debtCustomerRow(Map<String, dynamic> customer) {
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
    final phone = customer['phone']?.toString().trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.warning.withValues(alpha: 0.14),
            child: Text(
              (customer['fullName']?.toString().trim().isNotEmpty ?? false)
                  ? customer['fullName'].toString().trim().characters.first
                  : context.loc.tr('screens_admin_dashboard_screen.085'),
              style: AppTheme.bodyBold.copyWith(color: AppTheme.warning),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer['fullName']?.toString() ?? '-',
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 4),
                Text(
                  phone.isNotEmpty
                      ? phone
                      : context.loc.tr('screens_admin_dashboard_screen.086'),
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            CurrencyFormatter.ils(balance),
            style: AppTheme.bodyBold.copyWith(color: AppTheme.warning),
          ),
        ],
      ),
    );
  }

  Widget _reportActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTheme.caption.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminEntry {
  const _AdminEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.routeName,
    required this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String routeName;
  final String badge;
}
