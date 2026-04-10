import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_logo.dart';

class ScanCardScreen extends StatefulWidget {
  const ScanCardScreen({super.key, this.initialBarcode});

  final String? initialBarcode;

  @override
  State<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends State<ScanCardScreen> with RouteAware {
  final TextEditingController _bcC = TextEditingController();
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final OfflineCardService _offlineCardService = OfflineCardService();

  VirtualCard? _card;
  Map<String, dynamic>? _user;
  bool _isSearching = false;
  bool _isSubmitting = false;
  bool _showDetails = false;
  bool _isOfflineResult = false;
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.initialBarcode?.isNotEmpty == true) {
      _bcC.text = widget.initialBarcode!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
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
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _bcC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    if (mounted) {
      setState(() => _user = user);
    }
    await _syncOfflineRedeems();
  }

  Future<void> _syncOfflineRedeems() async {
    final user = _user ?? await _auth.currentUser();
    if (user == null || user['id'] == null) {
      return;
    }
    final permissions = AppPermissions.fromUser(user);
    if (!permissions.canOfflineCardScan) {
      return;
    }
    final queue = await _offlineCardService.getRedeemQueue(
      user['id'].toString(),
    );
    if (queue.isEmpty) {
      return;
    }
    try {
      final result = await _api.syncOfflineCardRedeems(items: queue);
      await _offlineCardService.clearRedeemQueue(user['id'].toString());
      if (!mounted) {
        return;
      }
      final updatedBalance = (result['balance'] as num?)?.toDouble();
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
    } catch (_) {
      // Keep queue for the next attempt when connection is available.
    }
  }

  Future<void> _search() async {
    final l = context.loc;
    final barcode = _bcC.text.trim();
    if (barcode.isEmpty) return;

    setState(() => _isSearching = true);
    try {
      final result = await _api.getCardByBarcode(barcode);
      if (!mounted) return;
      setState(() {
        _card = result;
        _showDetails = false;
        _isOfflineResult = false;
        _isSearching = false;
      });
      if (result == null) {
        AppAlertService.showError(
          context,
          title: l.tr('screens_scan_card_screen.039'),
          message: l.tr('screens_scan_card_screen.040'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final user = _user;
      final permissions = AppPermissions.fromUser(user);
      if (permissions.canOfflineCardScan && user?['id'] != null) {
        final cached = await _offlineCardService.findCachedCard(
          user!['id'].toString(),
          barcode,
        );
        if (cached != null) {
          setState(() {
            _card = cached;
            _showDetails = false;
            _isOfflineResult = true;
            _isSearching = false;
          });
          AppAlertService.showInfo(
            context,
            title: l.tr('screens_scan_card_screen.061'),
            message: l.tr('screens_scan_card_screen.062'),
          );
          return;
        }
      }

      setState(() => _isSearching = false);
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.039'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _openScannerDialog() async {
    final l = context.loc;
    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    var didScan = false;
    var torchEnabled = false;

    final scannedValue = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: ShwakelCard(
              padding: const EdgeInsets.all(20),
              borderRadius: BorderRadius.circular(28),
              shadowLevel: ShwakelShadowLevel.premium,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.tr('screens_scan_card_screen.001'),
                              style: AppTheme.h3,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.tr('screens_scan_card_screen.041'),
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await controller.dispose();
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: SizedBox(
                      height: 360,
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
                              Navigator.of(dialogContext).pop(value);
                            },
                          ),
                          Positioned(
                            top: 14,
                            left: 14,
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
                          Center(
                            child: IgnorePointer(
                              child: Container(
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    width: 2.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.tr('screens_scan_card_screen.042'),
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    await controller.dispose();
    if (!mounted || scannedValue == null || scannedValue.isEmpty) {
      return;
    }

    setState(() {
      _bcC.text = scannedValue;
    });
    await _search();
  }

  Future<void> _redeem() async {
    final l = context.loc;
    if (_card == null) return;

    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    if (permissions['canRedeemCards'] != true) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.043'),
        message: l.tr('screens_scan_card_screen.022'),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    Map<String, dynamic>? location;
    try {
      try {
        location = await TransactionLocationService.captureCurrentLocation();
      } catch (_) {
        location = null;
      }
      final response = await _api.redeemCard(
        cardId: _card!.id,
        customerName:
            _user?['fullName'] ??
            _user?['username'] ??
            l.tr('screens_scan_card_screen.060'),
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      await _search();
      if (!mounted) return;
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_scan_card_screen.044'),
        message: l.tr('screens_scan_card_screen.045'),
      );
    } catch (error) {
      if (!mounted) return;
      final user = _user;
      final permissions = AppPermissions.fromUser(user);
      if (permissions.canOfflineCardScan &&
          user?['id'] != null &&
          _card != null &&
          _card!.status != CardStatus.used) {
        final customerName =
            _user?['fullName'] ?? _user?['username'] ?? l.tr('screens_scan_card_screen.060');
        await _offlineCardService.enqueueRedeem(
          user!['id'].toString(),
          {
            'barcode': _card!.barcode,
            'customerName': customerName,
            'location': location,
            'queuedAt': DateTime.now().toIso8601String(),
          },
        );
        await _offlineCardService.markCardUsed(
          userId: user['id'].toString(),
          barcode: _card!.barcode,
          customerName: customerName,
          usedBy: _user?['username']?.toString(),
        );
        setState(() {
          _card = _card!.copyWith(
            status: CardStatus.used,
            usedAt: DateTime.now(),
            usedBy: _user?['username']?.toString(),
          );
          _isOfflineResult = true;
        });
        AppAlertService.showSuccess(
          context,
          title: l.tr('screens_scan_card_screen.063'),
          message: l.tr('screens_scan_card_screen.064'),
        );
      } else {
        AppAlertService.showError(
          context,
          title: l.tr('screens_scan_card_screen.046'),
          message: ErrorMessageService.sanitize(error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resell() async {
    final l = context.loc;
    if (_card == null) return;

    final permissions = Map<String, dynamic>.from(
      _user?['permissions'] as Map? ?? const {},
    );
    if (permissions['canResellCards'] != true) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.043'),
        message: l.tr('screens_scan_card_screen.047'),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.tr('screens_scan_card_screen.048')),
        content: Text(l.tr('screens_scan_card_screen.049')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.tr('screens_scan_card_screen.050')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.autorenew_rounded),
            label: Text(l.tr('screens_scan_card_screen.011')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final location =
          await TransactionLocationService.captureCurrentLocation();
      final response = await _api.resellCard(
        cardId: _card!.id,
        location: location,
      );
      final updatedBalance = (response['balance'] as num?)?.toDouble();
      await _search();
      if (!mounted) return;
      if (updatedBalance != null) {
        setState(() {
          _user = {...?_user, 'balance': updatedBalance};
        });
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_scan_card_screen.051'),
        message: l.tr('screens_scan_card_screen.052'),
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: l.tr('screens_scan_card_screen.046'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _statusLabel(VirtualCard card) {
    final l = context.loc;
    switch (card.status) {
      case CardStatus.used:
        return l.tr('screens_scan_card_screen.053');
      case CardStatus.archived:
        return l.tr('screens_scan_card_screen.054');
      case CardStatus.unused:
        return l.tr('screens_scan_card_screen.055');
    }
  }

  String _cardTypeLabel(VirtualCard card) {
    final l = context.loc;
    final scope = card.visibilityScope.trim().toLowerCase();
    final isLocationSpecific =
        card.isSingleUse ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    if (isLocationSpecific) {
      return l.tr('screens_scan_card_screen.065');
    }
    return card.isPrivate
        ? l.tr('screens_scan_card_screen.066')
        : l.tr('screens_scan_card_screen.067');
  }

  String _visibilityLabel(VirtualCard card) {
    final l = context.loc;
    final scope = card.visibilityScope.trim().toLowerCase();
    final isLocationSpecific =
        card.isSingleUse ||
        scope == 'location' ||
        scope == 'place' ||
        scope == 'branch' ||
        scope == 'specific';
    if (isLocationSpecific) {
      return l.tr('screens_scan_card_screen.065');
    }
    return card.isPrivate
        ? l.tr('screens_scan_card_screen.058')
        : l.tr('screens_scan_card_screen.059');
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$year-$month-$day  $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l.tr('screens_scan_card_screen.001'))),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            children: [
              _buildHero(),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  if (!isWide) {
                    return Column(
                      children: [
                        _buildScannerPanel(),
                        const SizedBox(height: 18),
                        _card == null ? _buildEmptyPreview() : _buildDetails(),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildScannerPanel()),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: _card == null
                            ? _buildEmptyPreview()
                            : _buildDetails(),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final l = context.loc;
    final balance = (_user?['balance'] as num?)?.toDouble() ?? 0;
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: const LinearGradient(
        colors: [Color(0xFF25C4D9), Color(0xFF17A79A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      withBorder: false,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_scan_card_screen.012'),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  l.tr(
                    'screens_scan_card_screen.013',
                    params: {'balance': CurrencyFormatter.ils(balance)},
                  ),
                  style: AppTheme.bodyBold.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerPanel() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.tr('screens_scan_card_screen.002'), style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_scan_card_screen.003'),
            style: AppTheme.bodyAction,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _bcC,
            decoration: InputDecoration(
              labelText: l.tr('screens_scan_card_screen.004'),
              prefixIcon: const Icon(Icons.qr_code_rounded),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 520;
              if (isCompact) {
                return Column(
                  children: [
                    ShwakelButton(
                      label: l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _openScannerDialog,
                    ),
                    const SizedBox(height: 12),
                    ShwakelButton(
                      label: l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: ShwakelButton(
                      label: l.tr('screens_scan_card_screen.005'),
                      icon: Icons.camera_alt_rounded,
                      isSecondary: true,
                      onPressed: _openScannerDialog,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShwakelButton(
                      label: l.tr('screens_scan_card_screen.006'),
                      icon: Icons.search_rounded,
                      onPressed: _search,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final l = context.loc;
    final card = _card!;
    final isUsed = card.status == CardStatus.used;
    final accent = isUsed ? AppTheme.error : AppTheme.success;
    final appPermissions = AppPermissions.fromUser(_user);
    final canRedeemCards = appPermissions.canRedeemCards;
    final canResellCards = appPermissions.canResellCards;
    final canReviewCards = appPermissions.canReviewCards;
    final canViewCardDetails = canReviewCards || canResellCards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShwakelCard(
          padding: const EdgeInsets.all(24),
          color: accent.withValues(alpha: 0.08),
          borderColor: accent.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(30),
          shadowLevel: ShwakelShadowLevel.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isUsed ? Icons.cancel_rounded : Icons.verified_rounded,
                      color: accent,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.tr('screens_scan_card_screen.014'),
                          style: AppTheme.caption.copyWith(color: accent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isUsed
                              ? l.tr('screens_scan_card_screen.015')
                              : l.tr('screens_scan_card_screen.016'),
                          style: AppTheme.h2.copyWith(color: accent),
                        ),
                      ],
                    ),
                  ),
                  if (isUsed && canResellCards)
                    IconButton.filledTonal(
                      tooltip: context.loc.tr('screens_scan_card_screen.011'),
                      onPressed: _isSubmitting ? null : _resell,
                      icon: const Icon(Icons.autorenew_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isUsed
                      ? l.tr('screens_scan_card_screen.017')
                      : l.tr('screens_scan_card_screen.018'),
                  style: AppTheme.bodyBold.copyWith(color: accent),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _resultBadge(
                      l.tr('screens_scan_card_screen.019'),
                      _statusLabel(card),
                      accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _resultBadge(
                      l.tr('screens_scan_card_screen.020'),
                      CurrencyFormatter.ils(card.value),
                      AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!isUsed && canRedeemCards) ...[
          ShwakelButton(
            label: l.tr('screens_scan_card_screen.021'),
            icon: Icons.download_done_rounded,
            onPressed: _redeem,
            isLoading: _isSubmitting,
          ),
          const SizedBox(height: 16),
        ],
        if (isUsed && canResellCards) ...[
          ShwakelButton(
            label: l.tr('screens_scan_card_screen.011'),
            icon: Icons.autorenew_rounded,
            onPressed: _resell,
            isLoading: _isSubmitting,
          ),
          const SizedBox(height: 16),
        ],
        if (!isUsed && !canRedeemCards) ...[
          ShwakelCard(
            padding: const EdgeInsets.all(18),
            color: AppTheme.warning.withValues(alpha: 0.08),
            borderColor: AppTheme.warning.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(24),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, color: AppTheme.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.tr('screens_scan_card_screen.022'),
                    style: AppTheme.bodyText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (canViewCardDetails)
          OutlinedButton.icon(
            onPressed: () => setState(() => _showDetails = !_showDetails),
            icon: Icon(
              _showDetails
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
            label: Text(
              _showDetails
                  ? context.loc.tr('screens_scan_card_screen.009')
                  : context.loc.tr('screens_scan_card_screen.010'),
            ),
          ),
        if (_showDetails && canViewCardDetails) ...[
          const SizedBox(height: 16),
          ShwakelCard(
            padding: const EdgeInsets.all(24),
            borderRadius: BorderRadius.circular(28),
            shadowLevel: ShwakelShadowLevel.medium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ShwakelLogo(size: 40, framed: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.loc.tr('screens_scan_card_screen.007'),
                        style: AppTheme.h2,
                      ),
                    ),
                    Text(
                      CurrencyFormatter.ils(card.value),
                      style: AppTheme.h2.copyWith(color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 620;
                    final items = [
                      _detailTile(
                        l.tr('screens_scan_card_screen.023'),
                        card.barcode,
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.019'),
                        _statusLabel(card),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.024'),
                        _cardTypeLabel(card),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.025'),
                        _visibilityLabel(card),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.026'),
                        CurrencyFormatter.ils(card.value),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.027'),
                        CurrencyFormatter.ils(card.issueCost),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.028'),
                        card.ownerUsername ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.029'),
                        card.issuedByUsername ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.030'),
                        card.usedBy ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.031'),
                        card.customerName ?? '-',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.032'),
                        _formatDate(card.createdAt),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.033'),
                        _formatDate(card.usedAt),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.034'),
                        _formatDate(card.lastResoldAt),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.035'),
                        '${card.useCount}',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.036'),
                        '${card.resaleCount}',
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.037'),
                        CurrencyFormatter.ils(card.totalRedeemedValue),
                      ),
                      _detailTile(
                        l.tr('screens_scan_card_screen.038'),
                        card.allowedUsernames.isEmpty
                            ? '-'
                            : card.allowedUsernames.join('، '),
                        spanTwo: true,
                      ),
                    ];

                    if (isCompact) {
                      return Column(
                        children: items
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: item,
                              ),
                            )
                            .toList(),
                      );
                    }

                    return Wrap(spacing: 12, runSpacing: 12, children: items);
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _resultBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(value, style: AppTheme.bodyBold.copyWith(color: color)),
        ],
      ),
    );
  }

  Widget _detailTile(String label, String value, {bool spanTwo = false}) {
    return SizedBox(
      width: spanTwo ? 420 : 204,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTheme.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(value, style: AppTheme.bodyBold),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPreview() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(40),
      borderRadius: BorderRadius.circular(28),
      child: Column(
        children: [
          Icon(
            Icons.credit_card_off_rounded,
            size: 56,
            color: AppTheme.textTertiary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 18),
          Text(l.tr('screens_scan_card_screen.007'), style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_scan_card_screen.008'),
            style: AppTheme.bodyAction,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
