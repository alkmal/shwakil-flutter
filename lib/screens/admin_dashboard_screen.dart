import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/user_display_name.dart';
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
  Map<String, dynamic> _adminCenterPayload = const {};
  Map<String, dynamic> _debtBookSnapshot = const {};
  String _selectedReportPeriod = 'daily';
  bool _isLoading = true;
  bool _isAuthorized = false;
  bool _isReportLoading = false;
  pw.Font? _pdfRegularFont;
  pw.Font? _pdfBoldFont;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user =
        AuthService.peekCurrentUser() ?? await _authService.currentUser();
    final permissions = AppPermissions.fromUser(user);
    final isAuthorized = permissions.hasAdminWorkspaceAccess;
    if (!mounted) {
      return;
    }
    setState(() {
      _user = user;
      _isAuthorized = isAuthorized;
      _isLoading = false;
    });
    if (!isAuthorized) {
      return;
    }
    _loadInitialAdminReport();
    if (user != null && user['id'] != null && permissions.canManageDebtBook) {
      _loadInitialDebtBook(user['id'].toString());
    }
  }

  Future<void> _loadInitialAdminReport() async {
    if (!ConnectivityService.instance.isOnline.value) {
      return;
    }
    setState(() => _isReportLoading = true);
    try {
      final payload = await _apiService.getAdminDashboard(
        period: _selectedReportPeriod,
      );
      if (!mounted) {
        return;
      }
      setState(() => _adminCenterPayload = payload);
    } catch (_) {
      // The center stays usable while the report is retried by pull-to-refresh.
    } finally {
      if (mounted) {
        setState(() => _isReportLoading = false);
      }
    }
  }

  Future<void> _loadInitialDebtBook(String userId) async {
    final cachedSnapshot = await _debtBookService.getSnapshot(userId);
    if (!mounted) {
      return;
    }
    setState(() => _debtBookSnapshot = cachedSnapshot);
    if (!ConnectivityService.instance.isOnline.value) {
      return;
    }
    try {
      final syncedSnapshot = await _debtBookService.syncPending(
        userId: userId,
        api: _apiService,
      );
      if (!mounted) {
        return;
      }
      setState(() => _debtBookSnapshot = syncedSnapshot);
    } catch (_) {}
  }

  Future<void> _loadAdminReport(String period) async {
    if (_isReportLoading) {
      return;
    }
    setState(() {
      _selectedReportPeriod = period;
      _isReportLoading = true;
    });
    try {
      final payload = await _apiService.getAdminDashboard(period: period);
      if (!mounted) {
        return;
      }
      setState(() => _adminCenterPayload = payload);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر تحميل تقرير الإدارة',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isReportLoading = false);
      }
    }
  }

  Future<void> _ensurePdfFonts() async {
    _pdfRegularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    _pdfBoldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );
  }

  void _openRoute(String routeName) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == routeName) {
      return;
    }
    Navigator.pushNamed(context, routeName);
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
        .where(
          (customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0,
        )
        .toList();

    final buffer = StringBuffer();
    buffer.writeln(l.tr('screens_admin_dashboard_screen.072'));
    buffer.writeln(
      l.tr(
        'screens_admin_dashboard_screen.073',
        params: {
          'count': '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
        },
      ),
    );
    buffer.writeln(
      l.tr(
        'screens_admin_dashboard_screen.074',
        params: {
          'count': '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
        },
      ),
    );
    buffer.writeln(
      l.tr(
        'screens_admin_dashboard_screen.075',
        params: {
          'amount': CurrencyFormatter.ils(
            (summary['totalDebt'] as num?)?.toDouble() ?? 0,
          ),
        },
      ),
    );
    buffer.writeln(
      l.tr(
        'screens_admin_dashboard_screen.076',
        params: {
          'amount': CurrencyFormatter.ils(
            (summary['totalPaid'] as num?)?.toDouble() ?? 0,
          ),
        },
      ),
    );
    buffer.writeln('');
    buffer.writeln(l.tr('screens_admin_dashboard_screen.077'));
    if (customers.isEmpty) {
      buffer.writeln(l.tr('screens_admin_dashboard_screen.078'));
    } else {
      for (final customer in customers) {
        final phone = customer['phone']?.toString().trim() ?? '';
        buffer.writeln(
          l.tr(
            'screens_admin_dashboard_screen.079',
            params: {
              'name': UserDisplayName.fromMap(customer, fallback: '-'),
              'phone': phone.isNotEmpty
                  ? phone
                  : l.tr('screens_admin_dashboard_screen.083'),
              'amount': CurrencyFormatter.ils(
                (customer['balance'] as num?)?.toDouble() ?? 0,
              ),
            },
          ),
        );
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
        .where(
          (customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0,
        )
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
                        l.tr(
                          'screens_admin_dashboard_screen.073',
                          params: {
                            'count':
                                '${(summary['customersCount'] as num?)?.toInt() ?? 0}',
                          },
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_admin_dashboard_screen.074',
                          params: {
                            'count':
                                '${(summary['openCustomersCount'] as num?)?.toInt() ?? 0}',
                          },
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_admin_dashboard_screen.075',
                          params: {
                            'amount': CurrencyFormatter.ils(
                              (summary['totalDebt'] as num?)?.toDouble() ?? 0,
                            ),
                          },
                        ),
                      ),
                      pw.Text(
                        l.tr(
                          'screens_admin_dashboard_screen.076',
                          params: {
                            'amount': CurrencyFormatter.ils(
                              (summary['totalPaid'] as num?)?.toDouble() ?? 0,
                            ),
                          },
                        ),
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
                        UserDisplayName.fromMap(customer, fallback: '-'),
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

    final usernameValue = _user?['username']?.toString().trim() ?? '';
    final fullName = UserDisplayName.fromMap(
      _user,
      fallback: usernameValue.isNotEmpty
          ? usernameValue
          : l.tr('screens_admin_dashboard_screen.003'),
    );
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
      if (permissions.canManageUsers || permissions.canManageMarketingAccounts)
        _AdminEntry(
          title: l.tr('screens_admin_dashboard_screen.087'),
          subtitle: l.tr('screens_admin_dashboard_screen.088'),
          icon: Icons.person_add_alt_1_rounded,
          color: AppTheme.secondary,
          routeName: '/admin-pending-registrations',
          badge: l.tr('screens_admin_dashboard_screen.089'),
        ),
      if (permissions.canManageUsers)
        const _AdminEntry(
          title: 'تقارير فحص البطاقات',
          subtitle: 'قراءات ونسب الاستخدام.',
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.accent,
          routeName: '/admin-card-scan-reports',
          badge: 'تقارير',
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
          title: l.tr('screens_admin_dashboard_screen.090'),
          subtitle: l.tr('screens_admin_dashboard_screen.091'),
          icon: Icons.approval_rounded,
          color: AppTheme.warning,
          routeName: '/admin-prepaid-multipay-approvals',
          badge: l.tr('screens_admin_dashboard_screen.092'),
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
        .where(
          (customer) => ((customer['balance'] as num?)?.toDouble() ?? 0) > 0,
        )
        .take(3)
        .toList();
    final adminWidgets = adminCards.map((item) => _navCard(item)).toList();
    final showDebtTab = permissions.canManageDebtBook;

    return DefaultTabController(
      length: showDebtTab ? 3 : 2,
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
          child: NestedScrollView(
            physics: const ClampingScrollPhysics(),
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(
                      fullName: fullName,
                      sectionCount: adminCards.length,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _AdminDashboardTabBarDelegate(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildDashboardTabBar(
                      showDebtTab: showDebtTab,
                      context: context,
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              children: [
                _buildAdminCenterTab(),
                _buildAdminUnitsTab(
                  adminCards: adminCards,
                  adminWidgets: adminWidgets,
                ),
                if (showDebtTab)
                  _buildDebtBookTab(
                    debtSummary: debtSummary,
                    topDebtors: topDebtors,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTabBar({
    required bool showDebtTab,
    required BuildContext context,
  }) {
    final l = context.loc;
    return Material(
      color: Colors.transparent,
      child: ShwakelCard(
        padding: const EdgeInsets.all(10),
        borderRadius: BorderRadius.circular(24),
        shadowLevel: ShwakelShadowLevel.soft,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(4),
          tabs: [
            const Tab(
              icon: Icon(Icons.query_stats_rounded),
              text: 'مركز الإدارة',
            ),
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
    );
  }

  Widget _buildHero({required String fullName, required int sectionCount}) {
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
                style: AppTheme.h2.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                fullName,
                style: AppTheme.bodyAction.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
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

  Widget _buildAdminCenterTab() {
    final overview = Map<String, dynamic>.from(
      _adminCenterPayload['overview'] as Map? ?? const {},
    );
    final stats = Map<String, dynamic>.from(
      overview['stats'] as Map? ?? const {},
    );
    final counts = Map<String, dynamic>.from(
      _adminCenterPayload['navigationCounts'] as Map? ?? const {},
    );
    final report = Map<String, dynamic>.from(
      _adminCenterPayload['report'] as Map? ?? const {},
    );
    final summary = Map<String, dynamic>.from(
      report['summary'] as Map? ?? const {},
    );
    final recentOperations = List<Map<String, dynamic>>.from(
      (report['recentOperations'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final typeBreakdown = List<Map<String, dynamic>>.from(
      (report['transactionTypeBreakdown'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final warnings = List<String>.from(
      (report['reportWarnings'] as List? ?? const []).map(
        (item) => item.toString(),
      ),
    );
    final reportError = report['reportError']?.toString().trim() ?? '';
    final period = Map<String, dynamic>.from(
      report['period'] as Map? ?? const {},
    );
    final hasReportPayload = report.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () => _loadAdminReport(_selectedReportPeriod),
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingXl),
        children: [
          _buildSectionHeader(
            title: 'مركز الإدارة',
            subtitle:
                'إحصائيات وتقارير يومية وأسبوعية وشهرية مع قراءة مباشرة للعمليات المهمة.',
            actionLabel: '${counts['pendingAll'] ?? 0} إجراء بانتظار المتابعة',
          ),
          const SizedBox(height: 16),
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          if (!hasReportPayload && _isReportLoading) ...[
            _adminReportLoadingCard(),
            const SizedBox(height: 16),
          ] else if (!hasReportPayload) ...[
            _adminReportEmptyState(),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 980
                  ? 4
                  : constraints.maxWidth > 680
                  ? 2
                  : 1;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 136,
                children: [
                  _metricCard(
                    icon: Icons.people_alt_rounded,
                    label: 'المستخدمون',
                    value: _formatInt(stats['totalUsers']),
                    detail: '${_formatInt(stats['activeUsers'])} نشط',
                    color: AppTheme.primary,
                  ),
                  _metricCard(
                    icon: Icons.pending_actions_rounded,
                    label: 'قيد المتابعة',
                    value: _formatInt(counts['pendingAll']),
                    detail: 'طلبات مالية وأجهزة وتوثيق',
                    color: AppTheme.warning,
                  ),
                  _metricCard(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'أرصدة الحسابات',
                    value: CurrencyFormatter.ils(_num(stats['totalBalance'])),
                    detail: 'الرصيد الإجمالي الحالي',
                    color: AppTheme.secondary,
                  ),
                  _metricCard(
                    icon: Icons.receipt_long_rounded,
                    label: 'عمليات اليوم',
                    value: _formatInt(stats['dailyCount']),
                    detail: CurrencyFormatter.ils(_num(stats['dailyVolume'])),
                    color: AppTheme.accent,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (reportError.isNotEmpty || warnings.isNotEmpty) ...[
            _reportNoticeCard(error: reportError, warnings: warnings),
            const SizedBox(height: 16),
          ],
          ShwakelCard(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(24),
            shadowLevel: ShwakelShadowLevel.soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.analytics_rounded,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        report['periodLabel']?.toString().trim().isNotEmpty ==
                                true
                            ? report['periodLabel'].toString()
                            : 'تقرير الفترة الحالية',
                        style: AppTheme.h3,
                      ),
                    ),
                    if (_isReportLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (period.isNotEmpty) ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _summaryPill(
                        'من',
                        period['from']?.toString() ?? '-',
                        AppTheme.info,
                      ),
                      _summaryPill(
                        'إلى',
                        period['to']?.toString() ?? '-',
                        AppTheme.info,
                      ),
                      _summaryPill(
                        'عدد الدخل',
                        '${_formatInt(summary['incomeCount'])} حركة',
                        AppTheme.success,
                      ),
                      _summaryPill(
                        'عدد الخارج',
                        '${_formatInt(summary['outgoingCount'])} حركة',
                        AppTheme.error,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryPill(
                      'الدخل',
                      CurrencyFormatter.ils(_num(summary['incomeAmount'])),
                      AppTheme.success,
                    ),
                    _summaryPill(
                      'الخارج',
                      CurrencyFormatter.ils(_num(summary['outgoingAmount'])),
                      AppTheme.error,
                    ),
                    _summaryPill(
                      'الصافي',
                      CurrencyFormatter.ils(_num(summary['netAmount'])),
                      _num(summary['netAmount']) >= 0
                          ? AppTheme.success
                          : AppTheme.error,
                    ),
                    _summaryPill(
                      'استخدام البطاقات',
                      '${_formatInt(summary['usageCount'])} عملية',
                      AppTheme.primary,
                    ),
                    _summaryPill(
                      'رسوم الفترة',
                      CurrencyFormatter.ils(_num(summary['usageFees'])),
                      AppTheme.secondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              final operations = _operationsList(
                recentOperations,
                periodLabel: report['periodLabel']?.toString() ?? '',
              );
              final breakdown = _breakdownList(typeBreakdown);
              if (!wide) {
                return Column(
                  children: [operations, const SizedBox(height: 16), breakdown],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: operations),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: breakdown),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    final periods = const [
      ('daily', 'اليومي', Icons.today_rounded),
      ('weekly', 'الأسبوعي', Icons.view_week_rounded),
      ('monthly', 'الشهري', Icons.calendar_month_rounded),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: periods.map((period) {
        final selected = _selectedReportPeriod == period.$1;
        return ChoiceChip(
          selected: selected,
          avatar: Icon(
            period.$3,
            size: 18,
            color: selected ? Colors.white : AppTheme.primary,
          ),
          label: Text(period.$2),
          onSelected: (_) => _loadAdminReport(period.$1),
          selectedColor: AppTheme.primary,
          labelStyle: AppTheme.bodyBold.copyWith(
            color: selected ? Colors.white : AppTheme.textPrimary,
          ),
        );
      }).toList(),
    );
  }

  Widget _adminReportLoadingCard() {
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(22),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'جاري تحميل بيانات مركز الإدارة وتقارير العمليات...',
              style: AppTheme.bodyAction,
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminReportEmptyState() {
    return ShwakelCard(
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(22),
      borderColor: AppTheme.warning.withValues(alpha: 0.20),
      color: AppTheme.warning.withValues(alpha: 0.05),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.refresh_rounded, color: AppTheme.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'لم تصل بيانات التقرير بعد. اسحب للتحديث أو اختر فترة أخرى لعرض العمليات.',
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _loadAdminReport(_selectedReportPeriod),
            icon: const Icon(Icons.sync_rounded),
            label: const Text('تحديث'),
          ),
        ],
      ),
    );
  }

  Widget _reportNoticeCard({
    required String error,
    required List<String> warnings,
  }) {
    final isError = error.isNotEmpty;
    final color = isError ? AppTheme.error : AppTheme.warning;
    final messages = [
      if (error.isNotEmpty) error,
      ...warnings,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: messages
                  .map(
                    (message) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String value,
    required String detail,
    required Color color,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(22),
      shadowLevel: ShwakelShadowLevel.soft,
      borderColor: color.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const Spacer(),
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.h3.copyWith(color: color),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _summaryPill(String label, String value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTheme.caption.copyWith(color: color)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyBold.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _operationsList(
    List<Map<String, dynamic>> operations, {
    required String periodLabel,
  }) {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppTheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text('تفاصيل آخر العمليات', style: AppTheme.h3)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${operations.length} عملية',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (periodLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              periodLabel,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          if (operations.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'لا توجد عمليات ضمن هذه الفترة. جرّب الأسبوعي أو الشهري إذا كنت تبحث عن حركات أقدم.',
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            )
          else
            ...operations.map(_operationRow),
        ],
      ),
    );
  }

  Widget _operationRow(Map<String, dynamic> item) {
    final amount = _num(item['amount']);
    final fee = _num(item['fee']);
    final user = item['userDisplayName']?.toString().trim();
    final description = item['description']?.toString().trim() ?? '';
    final type = item['type']?.toString().trim() ?? '';
    final color = _operationColor(type);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_operationIcon(type), color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['typeLabel']?.toString() ?? '-',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold.copyWith(color: color, height: 1.3),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  [
                    if (user != null && user.isNotEmpty) user,
                    _formatAdminDateTime(item['createdAt']),
                  ].where((part) => part.trim().isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.ils(amount),
                style: AppTheme.bodyBold.copyWith(color: color),
              ),
              if (fee > 0)
                Text(
                  'رسوم ${CurrencyFormatter.ils(fee)}',
                  style: AppTheme.caption.copyWith(color: AppTheme.secondary),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _operationIcon(String type) {
    if (type.contains('withdraw')) {
      return Icons.outbox_rounded;
    }
    if (type.contains('topup') || type.contains('credit')) {
      return Icons.add_card_rounded;
    }
    if (type.contains('transfer')) {
      return Icons.swap_horiz_rounded;
    }
    if (type.contains('prepaid')) {
      return Icons.credit_card_rounded;
    }
    if (type.contains('card')) {
      return Icons.confirmation_number_rounded;
    }
    return Icons.receipt_long_rounded;
  }

  Color _operationColor(String type) {
    if (type.contains('withdraw') ||
        type.contains('out') ||
        type.contains('deduction') ||
        type.contains('debit')) {
      return AppTheme.error;
    }
    if (type.contains('topup') ||
        type.contains('credit') ||
        type.contains('in') ||
        type.contains('refund')) {
      return AppTheme.success;
    }
    if (type.contains('prepaid')) {
      return AppTheme.primary;
    }
    if (type.contains('card')) {
      return AppTheme.secondary;
    }
    return AppTheme.info;
  }

  String _formatAdminDateTime(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      return value?.toString() ?? '';
    }
    final local = parsed.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _breakdownList(List<Map<String, dynamic>> breakdown) {
    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      shadowLevel: ShwakelShadowLevel.soft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('توزيع أنواع العمليات', style: AppTheme.h3),
          const SizedBox(height: 12),
          if (breakdown.isEmpty)
            Text(
              'لا توجد بيانات كافية لعرض التوزيع.',
              style: AppTheme.bodyAction.copyWith(
                color: AppTheme.textSecondary,
              ),
            )
          else
            ...breakdown.take(8).map((item) {
              final label = item['label']?.toString().trim().isNotEmpty == true
                  ? item['label'].toString()
                  : item['type']?.toString() ?? '-';
              final amount = _num(item['amount']);
              final fees = _num(item['fees']);
              final count = _formatInt(item['count']);
              final color = _operationColor(item['type']?.toString() ?? '');
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _operationIcon(item['type']?.toString() ?? ''),
                          size: 18,
                          color: color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodyBold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          CurrencyFormatter.ils(amount),
                          style: AppTheme.caption.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _miniReportChip('عدد الحركات', count, color),
                        if (fees > 0)
                          _miniReportChip(
                            'الرسوم',
                            CurrencyFormatter.ils(fees),
                            AppTheme.secondary,
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _miniReportChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

  String _formatInt(Object? value) =>
      '${(value as num?)?.toInt() ?? int.tryParse(value?.toString() ?? '') ?? 0}';

  Widget _buildAdminUnitsTab({
    required List<_AdminEntry> adminCards,
    required List<Widget> adminWidgets,
  }) {
    final priorityCards = adminCards.take(3).toList(growable: false);
    return ListView(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingXl),
      children: [
        Column(
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
            if (priorityCards.isNotEmpty) ...[
              const SizedBox(height: 16),
              ShwakelCard(
                padding: const EdgeInsets.all(20),
                color: AppTheme.tabSurface,
                borderColor: AppTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
                shadowLevel: ShwakelShadowLevel.soft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.dashboard_customize_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.loc.tr(
                              'screens_admin_dashboard_screen.093',
                            ),
                            style: AppTheme.bodyBold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.loc.tr('screens_admin_dashboard_screen.094'),
                      style: AppTheme.bodyAction.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: priorityCards
                          .map((item) => _priorityShortcutTile(item))
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(30),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 1120
                      ? 3
                      : constraints.maxWidth > 740
                      ? 2
                      : 1;
                  final tileExtent = constraints.maxWidth > 1120
                      ? 300.0
                      : constraints.maxWidth > 740
                      ? 320.0
                      : 340.0;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: tileExtent,
                    children: adminWidgets,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDebtBookTab({
    required Map<String, dynamic> debtSummary,
    required List<Map<String, dynamic>> topDebtors,
  }) {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingXl),
      children: [
        Column(
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
              onTap: () => _openRoute('/admin-debt-book'),
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
                              context.loc.tr(
                                'screens_admin_dashboard_screen.043',
                              ),
                              style: AppTheme.h3,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              topDebtors.isEmpty
                                  ? context.loc.tr(
                                      'screens_admin_dashboard_screen.044',
                                    )
                                  : context.loc.tr(
                                      'screens_admin_dashboard_screen.045',
                                    ),
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
                        label: context.loc.tr(
                          'screens_admin_dashboard_screen.046',
                        ),
                        onTap: _copyDebtBookAdminReport,
                      ),
                      _reportActionChip(
                        icon: Icons.print_rounded,
                        label: context.loc.tr(
                          'screens_admin_dashboard_screen.047',
                        ),
                        onTap: _printDebtBookAdminReport,
                      ),
                      _reportActionChip(
                        icon: Icons.picture_as_pdf_rounded,
                        label: context.loc.tr(
                          'screens_admin_dashboard_screen.048',
                        ),
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
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: topDebtors.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _debtCustomerRow(topDebtors[index]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _navCard(_AdminEntry item) {
    final isArabic = context.loc.isArabic;
    return ShwakelCard(
      onTap: () => _openRoute(item.routeName),
      padding: const EdgeInsets.all(22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      color: AppTheme.surfaceElevated,
      borderColor: item.color.withValues(alpha: 0.14),
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
                      item.color.withValues(alpha: 0.22),
                      item.color.withValues(alpha: 0.10),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: item.color.withValues(alpha: 0.10)),
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
                  color: item.color.withValues(alpha: 0.10),
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
          Container(
            width: double.infinity,
            height: 1,
            color: item.color.withValues(alpha: 0.10),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                context.loc.tr('screens_admin_dashboard_screen.084'),
                style: AppTheme.bodyBold.copyWith(color: item.color),
              ),
              const Spacer(),
              Icon(
                isArabic
                    ? Icons.arrow_back_rounded
                    : Icons.arrow_forward_rounded,
                color: item.color,
                size: 24,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priorityShortcutTile(_AdminEntry item) {
    final isArabic = context.loc.isArabic;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openRoute(item.routeName),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: item.color.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: item.color.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyBold.copyWith(height: 1.3),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isArabic ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
              color: item.color,
              size: 18,
            ),
          ],
        ),
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
              UserDisplayName.initialFromMap(
                customer,
                fallback: context.loc.tr('screens_admin_dashboard_screen.085'),
              ),
              style: AppTheme.bodyBold.copyWith(color: AppTheme.warning),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UserDisplayName.fromMap(customer, fallback: '-'),
                  style: AppTheme.bodyBold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  phone.isNotEmpty
                      ? phone
                      : context.loc.tr('screens_admin_dashboard_screen.086'),
                  style: AppTheme.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            CurrencyFormatter.ils(balance),
            style: AppTheme.bodyBold.copyWith(color: AppTheme.warning),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _AdminDashboardTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _AdminDashboardTabBarDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 86;

  @override
  double get maxExtent => 86;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppTheme.background,
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _AdminDashboardTabBarDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
