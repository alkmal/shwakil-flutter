import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
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
    return AppPermissions.fromUser(_user).canIssueCards;
  }

  bool get _canTransfer {
    return AppPermissions.fromUser(_user).canTransfer;
  }

  bool get _canReviewCards {
    return AppPermissions.fromUser(_user).canReviewCards;
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
    var torchEnabled = false;
    final scannedValue = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            title: Text(
              l.tr('screens_home_screen.014'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.tr('screens_home_screen.013'),
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyAction,
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 320,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: controller,
                          onDetect: (capture) {
                            if (didScan) return;
                            final value = capture.barcodes
                                .map(
                                  (barcode) => barcode.rawValue?.trim() ?? '',
                                )
                                .firstWhere(
                                  (candidate) => candidate.isNotEmpty,
                                  orElse: () => '',
                                );
                            if (value.isEmpty) return;
                            didScan = true;
                            Navigator.of(context).pop(value);
                          },
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: FilledButton.tonalIcon(
                            onPressed: () async {
                              await controller.toggleTorch();
                              setDialogState(() {
                                torchEnabled = !torchEnabled;
                              });
                            },
                            icon: Icon(
                              torchEnabled
                                  ? Icons.flash_off_rounded
                                  : Icons.flash_on_rounded,
                            ),
                            label: Text(
                              context.loc.text(
                                torchEnabled
                                    ? 'إطفاء الإضاءة'
                                    : 'تشغيل الإضاءة',
                                torchEnabled ? 'Torch off' : 'Torch on',
                              ),
                            ),
                          ),
                        ),
                      ],
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
          ),
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
                        final showBarcodeCard =
                            _canIssueCards || _canReviewCards;
                        final columns = width < 360
                            ? 1
                            : (isMobile ? 2 : (isTablet ? 2 : 3));
                        final spacing = 18.0;
                        final itemWidth =
                            (width - (spacing * (columns - 1))) / columns;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopSection(
                              isMobile: isMobile,
                              showBarcodeCard: showBarcodeCard,
                            ),
                            const SizedBox(height: 22),
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
    final permissions = AppPermissions.fromUser(_user);
    final canIssueCards = permissions.canIssueCards;
    final canScanCards = permissions.canOpenCardTools;
    final canReviewCards = permissions.canReviewCards;
    final canViewBalance = permissions.canViewBalance;
    final canViewTransactions = permissions.canViewTransactions;
    final canViewInventory = permissions.canViewInventory;
    final canViewQuickTransfer = permissions.canOpenQuickTransfer;
    final canViewSecuritySettings = permissions.canViewSecuritySettings;
    final canRequestCardPrinting = permissions.canRequestCardPrinting;
    final l = context.loc;

    if (canReviewCards && !canIssueCards) {
      return [
        _HomeServiceItem(
          title: l.tr('screens_home_screen.015'),
          subtitle: l.tr('screens_home_screen.016'),
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          onTap: () => Navigator.pushNamed(context, '/scan-card'),
        ),
      ];
    }

    return [
      if (canScanCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.015'),
          subtitle: l.tr('screens_home_screen.016'),
          icon: Icons.qr_code_scanner_rounded,
          color: AppTheme.success,
          onTap: () => Navigator.pushNamed(context, '/scan-card'),
        ),
      if (canViewBalance)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.017'),
          subtitle: l.tr('screens_home_screen.018'),
          icon: Icons.account_balance_wallet_rounded,
          color: AppTheme.primary,
          onTap: () => Navigator.pushNamed(context, '/balance'),
        ),
      if (canIssueCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.019'),
          subtitle: l.tr('screens_home_screen.020'),
          icon: Icons.add_card_rounded,
          color: const Color(0xFF0B75B7),
          onTap: () => Navigator.pushNamed(context, '/create-card'),
        ),
      if (canViewQuickTransfer && _canTransfer)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.021'),
          subtitle: l.tr('screens_home_screen.022'),
          icon: Icons.send_to_mobile_rounded,
          color: AppTheme.accent,
          onTap: () => Navigator.pushNamed(context, '/quick-transfer'),
        ),
      if (canViewInventory && canIssueCards)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.023'),
          subtitle: l.tr('screens_home_screen.024'),
          icon: Icons.inventory_2_rounded,
          color: AppTheme.textSecondary,
          onTap: () => Navigator.pushNamed(context, '/inventory'),
        ),
      if (canRequestCardPrinting)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.025'),
          subtitle: l.tr('screens_home_screen.026'),
          icon: Icons.print_rounded,
          color: AppTheme.secondary,
          onTap: () => Navigator.pushNamed(context, '/card-print-requests'),
        ),
      if (canViewTransactions)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.027'),
          subtitle: l.tr('screens_home_screen.028'),
          icon: Icons.receipt_long_rounded,
          color: AppTheme.warning,
          onTap: () => Navigator.pushNamed(context, '/transactions'),
        ),
      if (canViewSecuritySettings)
        _HomeServiceItem(
          title: l.tr('screens_home_screen.029'),
          subtitle: l.tr('screens_home_screen.030'),
          icon: Icons.security_rounded,
          color: AppTheme.secondary,
          onTap: () => Navigator.pushNamed(context, '/security-settings'),
        ),
    ];
  }

  Widget _buildTopSection({
    required bool isMobile,
    required bool showBarcodeCard,
  }) {
    if (isMobile) {
      return Column(
        children: [
          _buildHeroCard(isMobile: true),
          if (showBarcodeCard) ...[
            const SizedBox(height: 16),
            _buildHomeBarcodeCard(isMobile: true),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: showBarcodeCard ? 3 : 1,
          child: _buildHeroCard(isMobile: false),
        ),
        if (showBarcodeCard) ...[
          const SizedBox(width: 18),
          Expanded(flex: 2, child: _buildHomeBarcodeCard(isMobile: false)),
        ],
      ],
    );
  }

  Widget _buildHeroCard({required bool isMobile}) {
    final l = context.loc;
    final username = _user?['username']?.toString() ?? '';
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    final role =
        _user?['roleLabel']?.toString() ?? _user?['role']?.toString() ?? '';
    final displayName = fullName.isNotEmpty ? fullName : username;
    final serviceCount = _serviceItems(context).length;
    final heroChips = [
      _HeroChipData(
        icon: Icons.verified_user_rounded,
        label: _isVerifiedAccount
            ? l.tr('screens_home_screen.009')
            : l.tr('screens_home_screen.010'),
      ),
      if (role.isNotEmpty)
        _HeroChipData(icon: Icons.badge_rounded, label: role),
      _HeroChipData(
        icon: Icons.grid_view_rounded,
        label: l.tr(
          'screens_home_screen.034',
          params: {'count': serviceCount.toString()},
        ),
      ),
    ];

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
                          : l.tr(
                              'screens_home_screen.031',
                              params: {'name': displayName},
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
            padding: EdgeInsets.all(isMobile ? 18 : 22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: isMobile
                ? Column(
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
                        l.tr('screens_home_screen.032'),
                        style: AppTheme.h1.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l.tr('screens_home_screen.033'),
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: heroChips
                            .map(
                              (chip) => _buildHeroChip(
                                icon: chip.icon,
                                label: chip.label,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
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
                              l.tr('screens_home_screen.032'),
                              style: AppTheme.h1.copyWith(
                                color: Colors.white,
                                fontSize: 28,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l.tr('screens_home_screen.033'),
                              style: AppTheme.bodyAction.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 2,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: heroChips
                              .map(
                                (chip) => _buildHeroChip(
                                  icon: chip.icon,
                                  label: chip.label,
                                ),
                              )
                              .toList(),
                        ),
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
      padding: EdgeInsets.all(compact ? 18 : 22),
      borderRadius: BorderRadius.circular(28),
      shadowLevel: ShwakelShadowLevel.medium,
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: color,
                      size: 24,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: AppTheme.h3.copyWith(color: color, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyAction.copyWith(
                    height: 1.4,
                    fontSize: 13.5,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTheme.h3.copyWith(color: color, fontSize: 19),
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
                Icon(Icons.arrow_forward_rounded, color: color, size: 26),
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
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      borderRadius: BorderRadius.circular(30),
      shadowLevel: ShwakelShadowLevel.medium,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppTheme.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.tr('screens_home_screen.011'),
                            style: AppTheme.h2.copyWith(fontSize: 17),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l.tr('screens_home_screen.035'),
                            style: AppTheme.bodyAction.copyWith(height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ShwakelButton(
                  label: l.tr('screens_home_screen.012'),
                  icon: Icons.camera_alt_rounded,
                  onPressed: _startHomeBarcodeScan,
                ),
              ],
            )
          : Column(
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
                            l.tr('screens_home_screen.035'),
                            style: AppTheme.bodyAction.copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 76,
                      height: 76,
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

class _HeroChipData {
  const _HeroChipData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
