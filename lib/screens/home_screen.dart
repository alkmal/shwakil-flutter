import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';
import 'scan_card_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _user;
  bool _isLoading = true;
  StreamSubscription<Map<String, dynamic>>? _balanceSubscription;
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _balanceSubscription = RealtimeNotificationService.balanceUpdatesStream
        .listen((_) {
          if (mounted) _loadUser();
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!_routeSubscribed && route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  @override
  void dispose() {
    _balanceSubscription?.cancel();
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didPopNext() => _loadUser();

  bool get _canIssueCards {
    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    return permissions['canIssueCards'] == true;
  }

  bool get _canTransfer {
    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    return permissions['canTransfer'] == true;
  }

  bool get _canReviewCards {
    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    return permissions['canReviewCards'] == true;
  }

  bool get _isVerifiedAccount =>
      _user?['transferVerificationStatus']?.toString() == 'approved';

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      await _authService.refreshCurrentUser();
      final user = await _authService.currentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await RealtimeNotificationService.stop();
    if (!mounted) return;

    final canUseTrustedUnlock =
        await LocalSecurityService.canUseTrustedUnlock();
    if (!mounted) return;

    if (!canUseTrustedUnlock) {
      await _authService.logout();
      await LocalSecurityService.clearTrustedState();
      if (!mounted) return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      canUseTrustedUnlock ? '/unlock' : '/login',
      (route) => false,
    );
  }

  Future<void> _startHomeBarcodeScan() async {
    if (!_canIssueCards) return;
    final l = context.loc;

    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );

    var didScan = false;
    final scannedValue = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: const Text(
            'فحص الباركود',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.text(
                  'وجّه الكاميرا إلى الباركود.',
                  'Point the camera at the barcode.',
                ),
                textAlign: TextAlign.center,
                style: AppTheme.bodyAction,
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 320,
                  width: double.infinity,
                  child: MobileScanner(
                    controller: controller,
                    onDetect: (capture) {
                      if (didScan) return;
                      final value = capture.barcodes
                          .map((barcode) => barcode.rawValue?.trim() ?? '')
                          .firstWhere(
                            (candidate) => candidate.isNotEmpty,
                            orElse: () => '',
                          );
                      if (value.isEmpty) return;
                      didScan = true;
                      Navigator.of(context).pop(value);
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            ShwakelButton(
              label: l.tr('screens_home_screen.001'),
              isSecondary: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );

    await controller.dispose();
    if (!mounted || scannedValue == null || scannedValue.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanCardScreen(initialBarcode: scannedValue),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final services = _serviceItems(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_home_screen.002')),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            tooltip: l.tr('screens_home_screen.003'),
          ),
        ],
      ),
      drawer: const AppSidebar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUser,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ResponsiveScaffoldContainer(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 28),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final isMobile = width < 700;
                        final isTablet = width < 1100;
                        final columns = isMobile ? 1 : (isTablet ? 2 : 3);
                        final spacing = 18.0;
                        final itemWidth =
                            (width - (spacing * (columns - 1))) / columns;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeroCard(isMobile: isMobile),
                            const SizedBox(height: 20),
                            if (_canIssueCards || _canReviewCards) ...[
                              _buildHomeBarcodeCard(isMobile: isMobile),
                              const SizedBox(height: 22),
                            ],
                            Text(
                              l.tr('screens_home_screen.004'),
                              style: AppTheme.h1,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l.tr('screens_home_screen.005'),
                              style: AppTheme.bodyAction,
                            ),
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: services
                                  .map(
                                    (service) => SizedBox(
                                      width: itemWidth,
                                      child: _buildServiceCard(
                                        title: service.title,
                                        subtitle: service.subtitle,
                                        icon: service.icon,
                                        color: service.color,
                                        onTap: service.onTap,
                                        compact: isMobile,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<_HomeServiceItem> _serviceItems(BuildContext context) {
    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    final canIssueCards = permissions['canIssueCards'] == true;
    final canScanCards = permissions['canScanCards'] != false;
    final canReviewCards = permissions['canReviewCards'] == true;
    final canViewBalance = permissions['canViewBalance'] != false;
    final canViewTransactions = permissions['canViewTransactions'] != false;
    final canViewInventory = permissions['canViewInventory'] == true;
    final canViewQuickTransfer = permissions['canViewQuickTransfer'] == true;
    final canViewSecuritySettings =
        permissions['canViewSecuritySettings'] != false;
    final canRequestCardPrinting =
        permissions['canRequestCardPrinting'] == true;

    if (canReviewCards && !canIssueCards) {
      return [
        _HomeServiceItem(
          title: 'قراءة الباركود',
          subtitle: 'فحص البطاقة.',
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          onTap: () => Navigator.pushNamed(context, '/scan-card'),
        ),
      ];
    }

    return [
      if (canScanCards)
        _HomeServiceItem(
          title: 'قراءة الباركود',
          subtitle: 'فحص البطاقة أو إعادة بيع.',
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          onTap: () => Navigator.pushNamed(context, '/scan-card'),
        ),
      if (canViewBalance)
        _HomeServiceItem(
          title: 'الرصيد',
          subtitle: 'الرصيد والحركات.',
          icon: Icons.account_balance_wallet_rounded,
          color: AppTheme.primary,
          onTap: () => Navigator.pushNamed(context, '/balance'),
        ),
      if (canIssueCards)
        _HomeServiceItem(
          title: 'إصدار البطاقات',
          subtitle: 'إنشاء بطاقات جديدة.',
          icon: Icons.add_card_rounded,
          color: const Color(0xFF0B75B7),
          onTap: () => Navigator.pushNamed(context, '/create-card'),
        ),
      if (canViewQuickTransfer && _canTransfer)
        _HomeServiceItem(
          title: 'النقل السريع',
          subtitle: 'تحويل فوري.',
          icon: Icons.send_to_mobile_rounded,
          color: AppTheme.accent,
          onTap: () => Navigator.pushNamed(context, '/quick-transfer'),
        ),
      if (canViewInventory && canIssueCards)
        _HomeServiceItem(
          title: 'أرشيف البطاقات',
          subtitle: 'عرض وطباعة البطاقات.',
          icon: Icons.inventory_2_rounded,
          color: AppTheme.textSecondary,
          onTap: () => Navigator.pushNamed(context, '/inventory'),
        ),
      if (canRequestCardPrinting)
        _HomeServiceItem(
          title: 'طلب طباعة',
          subtitle: 'إرسال ومتابعة طلبات طباعة البطاقات.',
          icon: Icons.print_rounded,
          color: AppTheme.secondary,
          onTap: () => Navigator.pushNamed(context, '/card-print-requests'),
        ),
      if (canViewTransactions)
        _HomeServiceItem(
          title: 'المعاملات',
          subtitle: 'سجل الحركات.',
          icon: Icons.receipt_long_rounded,
          color: AppTheme.warning,
          onTap: () => Navigator.pushNamed(context, '/transactions'),
        ),
      if (canViewSecuritySettings)
        _HomeServiceItem(
          title: 'إعدادات الأمان',
          subtitle: 'إدارة الحماية.',
          icon: Icons.security_rounded,
          color: AppTheme.secondary,
          onTap: () => Navigator.pushNamed(context, '/security-settings'),
        ),
    ];
  }

  Widget _buildHeroCard({required bool isMobile}) {
    final l = context.loc;
    final username = _user?['username']?.toString() ?? '';
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    final role =
        _user?['roleLabel']?.toString() ?? _user?['role']?.toString() ?? '';
    final displayName = fullName.isNotEmpty ? fullName : username;
    final serviceCount = _serviceItems(context).length;

    return ShwakelCard(
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      gradient: const LinearGradient(
        colors: [Color(0xFF25C4D9), Color(0xFF17A79A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shadowLevel: ShwakelShadowLevel.premium,
      withBorder: false,
      borderRadius: BorderRadius.circular(34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isEmpty
                          ? l.tr('screens_home_screen.006')
                          : l.text(
                              'مرحبًا $displayName',
                              'Welcome, $displayName',
                            ),
                      style: AppTheme.h2.copyWith(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 22,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      role.isEmpty ? l.tr('screens_home_screen.007') : role,
                      style: AppTheme.bodyBold.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: isMobile ? 62 : 70,
                height: isMobile ? 62 : 70,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: const ShwakelLogo(size: 38, framed: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_home_screen.008'),
                  style: AppTheme.bodyBold.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l.text(
                    'كل خدماتك في مكان واحد.',
                    'All your services in one place.',
                  ),
                  style: AppTheme.h1.copyWith(
                    color: Colors.white,
                    fontSize: isMobile ? 20 : 28,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l.text(
                    'اختر الخدمة وابدأ مباشرة.',
                    'Choose a service and get started instantly.',
                  ),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildHeroChip(
                      icon: Icons.verified_user_rounded,
                      label: _isVerifiedAccount
                          ? l.tr('screens_home_screen.009')
                          : l.tr('screens_home_screen.010'),
                    ),
                    if (role.isNotEmpty)
                      _buildHeroChip(icon: Icons.badge_rounded, label: role),
                    _buildHeroChip(
                      icon: Icons.grid_view_rounded,
                      label: l.text(
                        '$serviceCount خدمة متاحة',
                        '$serviceCount services available',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool compact,
  }) {
    return ShwakelCard(
      onTap: onTap,
      padding: EdgeInsets.all(compact ? 20 : 22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: compact ? 58 : 66,
            height: compact ? 58 : 66,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: color, size: compact ? 28 : 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTheme.h3.copyWith(
                    color: color,
                    fontSize: compact ? 17 : 19,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTheme.bodyAction.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_left_rounded, color: color, size: 26),
        ],
      ),
    );
  }

  Widget _buildHeroChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
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
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeBarcodeCard({required bool isMobile}) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(30),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_home_screen.011'),
                      style: AppTheme.h2.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.text(
                        'افتح الكاميرا لقراءة البطاقة.',
                        'Open the camera to scan the card.',
                      ),
                      style: AppTheme.bodyAction.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                width: isMobile ? 68 : 76,
                height: isMobile ? 68 : 76,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: AppTheme.primary,
                  size: 36,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          ShwakelButton(
            label: l.tr('screens_home_screen.012'),
            icon: Icons.camera_alt_rounded,
            onPressed: _startHomeBarcodeScan,
          ),
        ],
      ),
    );
  }
}

class _HomeServiceItem {
  const _HomeServiceItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
