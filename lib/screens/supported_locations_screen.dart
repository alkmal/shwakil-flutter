import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class SupportedLocationsScreen extends StatefulWidget {
  const SupportedLocationsScreen({super.key});

  @override
  State<SupportedLocationsScreen> createState() =>
      _SupportedLocationsScreenState();
}

class _SupportedLocationsScreenState extends State<SupportedLocationsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _locations = const [];
  List<Map<String, dynamic>> _myLocations = const [];
  Map<String, dynamic>? _user;
  Position? _position;
  bool _isLoading = true;
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getSupportedLocationsDashboard(),
        _authService.currentUser(),
        TransactionLocationService.currentPosition(),
      ]);
      final dashboard = Map<String, dynamic>.from(
        results[0] as Map<String, dynamic>,
      );
      final user = results[1] as Map<String, dynamic>?;
      final currentPosition = results[2] as Position?;
      final sorted = List<Map<String, dynamic>>.from(
        (dashboard['locations'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

      if (currentPosition != null) {
        for (final location in sorted) {
          final latitude = (location['latitude'] as num?)?.toDouble();
          final longitude = (location['longitude'] as num?)?.toDouble();
          if (latitude != null && longitude != null) {
            location['dist'] = Geolocator.distanceBetween(
              currentPosition.latitude,
              currentPosition.longitude,
              latitude,
              longitude,
            );
          }
        }
        sorted.sort(
          (a, b) => (a['dist'] as double? ?? 999999).compareTo(
            b['dist'] as double? ?? 999999,
          ),
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _locations = sorted;
        _myLocations = List<Map<String, dynamic>>.from(
          (dashboard['myLocations'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _user = user;
        _position = currentPosition;
        _canSubmit = dashboard['canSubmit'] == true;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddLocationDialog() async {
    final l = context.loc;
    final titleController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController(
      text: _user?['whatsapp']?.toString() ?? '',
    );
    final typeController = TextEditingController(text: 'shop');
    final latController = TextEditingController(
      text: (_position?.latitude ?? 31.5).toStringAsFixed(7),
    );
    final lngController = TextEditingController(
      text: (_position?.longitude ?? 34.47).toStringAsFixed(7),
    );
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (titleController.text.trim().isEmpty ||
                addressController.text.trim().isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_supported_locations_screen.015'),
                message: l.tr('screens_supported_locations_screen.016'),
              );
              return;
            }

            setDialogState(() => isSaving = true);
            try {
              final locations = await _apiService.submitSupportedLocation(
                title: titleController.text,
                address: addressController.text,
                phone: phoneController.text,
                type: typeController.text.trim().isEmpty
                    ? 'shop'
                    : typeController.text.trim(),
                latitude: double.tryParse(latController.text.trim()) ?? 31.5,
                longitude: double.tryParse(lngController.text.trim()) ?? 34.47,
              );
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!mounted) {
                return;
              }
              setState(() => _myLocations = locations);
              await AppAlertService.showSuccess(
                context,
                title: l.tr('screens_supported_locations_screen.017'),
                message: l.tr('screens_supported_locations_screen.018'),
              );
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_supported_locations_screen.019'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(l.tr('screens_supported_locations_screen.020')),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_supported_locations_screen.021'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_supported_locations_screen.022'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_supported_locations_screen.023'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_supported_locations_screen.024'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            decoration: InputDecoration(
                              labelText: l.tr(
                                'screens_supported_locations_screen.025',
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: lngController,
                            decoration: InputDecoration(
                              labelText: l.tr(
                                'screens_supported_locations_screen.026',
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_supported_locations_screen.027')),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(
                  isSaving
                      ? l.tr('screens_supported_locations_screen.028')
                      : l.tr('screens_supported_locations_screen.029'),
                ),
              ),
            ],
          );
        },
      ),
    );

    titleController.dispose();
    addressController.dispose();
    phoneController.dispose();
    typeController.dispose();
    latController.dispose();
    lngController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final permissions = AppPermissions.fromUser(_user);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_supported_locations_screen.001')),
        actions: [
          if (_canSubmit && !permissions.hasAdminWorkspaceAccess)
            IconButton(
              tooltip: l.tr('screens_supported_locations_screen.030'),
              onPressed: _showAddLocationDialog,
              icon: const Icon(Icons.add_business_rounded),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: ResponsiveScaffoldContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_canSubmit && !permissions.hasAdminWorkspaceAccess)
                        ShwakelCard(
                          padding: const EdgeInsets.all(18),
                          borderRadius: BorderRadius.circular(22),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.store_mall_directory_rounded,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  l.tr('screens_supported_locations_screen.031'),
                                  style: AppTheme.bodyAction.copyWith(height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_canSubmit && !permissions.hasAdminWorkspaceAccess)
                        const SizedBox(height: 16),
                      if (_myLocations.isNotEmpty) ...[
                        Text(
                          l.tr('screens_supported_locations_screen.032'),
                          style: AppTheme.h3,
                        ),
                        const SizedBox(height: 10),
                        ..._myLocations.map(_buildMyLocationTile),
                        const SizedBox(height: 18),
                      ],
                      if (_position != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l.tr('screens_supported_locations_screen.007'),
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.success,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (_locations.isEmpty)
                        _buildEmptyState()
                      else
                        ..._locations.map(_buildLocationTile),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.tr('screens_transactions_screen.039'),
      message: l.tr('screens_supported_locations_screen.033'),
    );
  }

  Widget _buildLocationTile(Map<String, dynamic> location) {
    final l = context.loc;
    final distance = location['dist'] as double?;
    final linkedUsername = location['linkedUsername']?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ShwakelCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location['title']?.toString() ??
                            l.tr('screens_supported_locations_screen.008'),
                        style: AppTheme.bodyBold,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location['type']?.toString() ??
                            l.tr('screens_supported_locations_screen.009'),
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.primary,
                        ),
                      ),
                      if (linkedUsername.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          l.tr(
                            'screens_supported_locations_screen.034',
                            params: {'username': linkedUsername},
                          ),
                          style: AppTheme.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                if (distance != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatDistance(distance),
                      style: AppTheme.caption.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 30),
            _info(
              Icons.location_on_rounded,
              location['address']?.toString() ?? '-',
            ),
            const SizedBox(height: 10),
            _info(Icons.phone_rounded, location['phone']?.toString() ?? '-'),
            const SizedBox(height: 20),
            ShwakelButton(
              label: l.tr('screens_supported_locations_screen.010'),
              icon: Icons.directions_rounded,
              onPressed: () => _openMap(location),
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyLocationTile(Map<String, dynamic> location) {
    final l = context.loc;
    final status = location['status']?.toString() ?? 'pending';
    final color = switch (status) {
      'approved' => AppTheme.success,
      'rejected' => AppTheme.error,
      _ => AppTheme.warning,
    };
    final statusLabel = switch (status) {
      'approved' => l.tr('screens_supported_locations_screen.035'),
      'rejected' => l.tr('screens_supported_locations_screen.036'),
      _ => l.tr('screens_supported_locations_screen.037'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        padding: const EdgeInsets.all(18),
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    location['title']?.toString() ?? '-',
                    style: AppTheme.bodyBold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: AppTheme.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              location['address']?.toString() ?? '-',
              style: AppTheme.caption,
            ),
            if (status == 'rejected' &&
                (location['rejectionReason']?.toString().trim().isNotEmpty ??
                    false)) ...[
              const SizedBox(height: 8),
              Text(
                l.tr(
                  'screens_supported_locations_screen.038',
                  params: {'reason': location['rejectionReason'].toString()},
                ),
                style: AppTheme.caption.copyWith(color: AppTheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l = context.loc;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(
          children: [
            Icon(
              Icons.map_outlined,
              size: 60,
              color: AppTheme.textTertiary.withValues(alpha: 0.30),
            ),
            const SizedBox(height: 24),
            Text(
              l.tr('screens_supported_locations_screen.011'),
              style: AppTheme.h3.copyWith(color: AppTheme.textTertiary),
            ),
            const SizedBox(height: 10),
            Text(
              l.tr('screens_supported_locations_screen.012'),
              textAlign: TextAlign.center,
              style: AppTheme.bodyAction,
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textTertiary),
        const SizedBox(width: 12),
        Expanded(child: Text(value, style: AppTheme.caption)),
      ],
    );
  }

  String _formatDistance(double meters) {
    final l = context.loc;
    return meters < 1000
        ? l.tr(
            'screens_supported_locations_screen.013',
            params: {'count': '${meters.round()}'},
          )
        : l.tr(
            'screens_supported_locations_screen.014',
            params: {'count': (meters / 1000).toStringAsFixed(1)},
          );
  }

  Future<void> _openMap(Map<String, dynamic> location) async {
    final latitude = location['latitude'];
    final longitude = location['longitude'];
    if (latitude == null || longitude == null) {
      return;
    }
    await launchUrl(
      Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      ),
      mode: LaunchMode.externalApplication,
    );
  }
}
