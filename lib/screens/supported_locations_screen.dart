import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';
import 'merchant_directions_webview_screen.dart';

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
  _SupportedLocationsView _viewMode = _SupportedLocationsView.list;

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
                displayName: titleController.text,
                address: addressController.text,
                phone: phoneController.text,
                displayPhone: phoneController.text,
                displayWhatsapp: phoneController.text,
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
                        labelText: l.tr(
                          'screens_supported_locations_screen.021',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_supported_locations_screen.022',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_supported_locations_screen.023',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_supported_locations_screen.024',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final selected = await _pickLocationFromMap(
                            initialLatitude:
                                double.tryParse(latController.text.trim()) ??
                                (_position?.latitude ?? 31.5),
                            initialLongitude:
                                double.tryParse(lngController.text.trim()) ??
                                (_position?.longitude ?? 34.47),
                          );
                          if (selected == null) {
                            return;
                          }
                          latController.text = selected.latitude
                              .toStringAsFixed(7);
                          lngController.text = selected.longitude
                              .toStringAsFixed(7);
                        },
                        icon: const Icon(Icons.map_rounded),
                        label: Text(
                          l.tr('screens_supported_locations_screen.039'),
                        ),
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
                    const SizedBox(height: 8),
                    Text(
                      l.tr('screens_supported_locations_screen.040'),
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
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
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.10,
                                  ),
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
                                  l.tr(
                                    'screens_supported_locations_screen.031',
                                  ),
                                  style: AppTheme.bodyAction.copyWith(
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_canSubmit && !permissions.hasAdminWorkspaceAccess)
                        const SizedBox(height: 16),
                      ShwakelCard(
                        padding: const EdgeInsets.all(18),
                        borderRadius: BorderRadius.circular(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.tr('screens_supported_locations_screen.041'),
                              style: AppTheme.h3,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l.tr(
                                'screens_supported_locations_screen.042',
                                params: {'count': _locations.length.toString()},
                              ),
                              style: AppTheme.bodyAction.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ChoiceChip(
                                  label: Text(
                                    l.tr(
                                      'screens_supported_locations_screen.043',
                                    ),
                                  ),
                                  selected:
                                      _viewMode == _SupportedLocationsView.list,
                                  onSelected: (_) {
                                    setState(
                                      () => _viewMode =
                                          _SupportedLocationsView.list,
                                    );
                                  },
                                ),
                                ChoiceChip(
                                  label: Text(
                                    l.tr(
                                      'screens_supported_locations_screen.044',
                                    ),
                                  ),
                                  selected:
                                      _viewMode == _SupportedLocationsView.map,
                                  onSelected: (_) {
                                    setState(
                                      () => _viewMode =
                                          _SupportedLocationsView.map,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
                      if (_viewMode == _SupportedLocationsView.map &&
                          _locations.isNotEmpty) ...[
                        _buildMerchantMap(),
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
                        location['publicDisplayName']?.toString() ??
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
            if ((location['displayPhone']?.toString().trim().isNotEmpty ??
                    false) ||
                (location['displayWhatsapp']?.toString().trim().isNotEmpty ??
                    false)) ...[
              if (location['displayPhone']?.toString().trim().isNotEmpty ??
                  false)
                _info(
                  Icons.phone_rounded,
                  location['displayPhone']?.toString() ?? '-',
                ),
              if ((location['displayPhone']?.toString().trim().isNotEmpty ??
                      false) &&
                  (location['displayWhatsapp']?.toString().trim().isNotEmpty ??
                      false))
                const SizedBox(height: 10),
              if (location['displayWhatsapp']?.toString().trim().isNotEmpty ??
                  false)
                _info(
                  Icons.chat_rounded,
                  location['displayWhatsapp']?.toString() ?? '-',
                ),
            ] else
              _info(Icons.phone_rounded, location['phone']?.toString() ?? '-'),
            const SizedBox(height: 20),
            ShwakelButton(
              label: l.tr('screens_supported_locations_screen.045'),
              icon: Icons.directions_rounded,
              onPressed: () => _showMerchantActions(location),
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _myLocationChip(
                  Icons.visibility_rounded,
                  (location['isActive'] == true)
                      ? context.loc.tr('screens_supported_locations_screen.049')
                      : context.loc.tr(
                          'screens_supported_locations_screen.050',
                        ),
                ),
                if (location['displayName']?.toString().trim().isNotEmpty ??
                    false)
                  _myLocationChip(
                    Icons.storefront_rounded,
                    location['displayName']?.toString() ?? '-',
                  ),
                if (location['displayPhone']?.toString().trim().isNotEmpty ??
                    false)
                  _myLocationChip(
                    Icons.phone_rounded,
                    location['displayPhone']?.toString() ?? '-',
                  ),
                if (location['displayWhatsapp']?.toString().trim().isNotEmpty ??
                    false)
                  _myLocationChip(
                    Icons.chat_rounded,
                    location['displayWhatsapp']?.toString() ?? '-',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ShwakelButton(
                label: context.loc.tr('screens_supported_locations_screen.051'),
                icon: Icons.edit_location_alt_rounded,
                isSecondary: true,
                onPressed: () => _showEditMyLocationDialog(location),
              ),
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

  Widget _buildMerchantMap() {
    final first = _locations.first;
    final initialCenter = LatLng(
      _position?.latitude ?? ((first['latitude'] as num?)?.toDouble() ?? 31.5),
      _position?.longitude ??
          ((first['longitude'] as num?)?.toDouble() ?? 34.47),
    );
    return ShwakelCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 360,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _position != null ? 12.2 : 10.8,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.shwakil.app',
              ),
              MarkerLayer(
                markers: [
                  if (_position != null)
                    Marker(
                      point: LatLng(_position!.latitude, _position!.longitude),
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ..._locations.map((location) {
                    final latitude = (location['latitude'] as num?)?.toDouble();
                    final longitude = (location['longitude'] as num?)
                        ?.toDouble();
                    if (latitude == null || longitude == null) {
                      return Marker(
                        point: initialCenter,
                        width: 0,
                        height: 0,
                        child: const SizedBox.shrink(),
                      );
                    }
                    return Marker(
                      point: LatLng(latitude, longitude),
                      width: 54,
                      height: 54,
                      child: GestureDetector(
                        onTap: () => _showMerchantActions(location),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.warning,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
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

  Widget _myLocationChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(label, style: AppTheme.caption),
        ],
      ),
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

  Future<void> _showMerchantActions(Map<String, dynamic> location) async {
    final l = context.loc;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location['title']?.toString() ??
                    l.tr('screens_supported_locations_screen.008'),
                style: AppTheme.h3,
              ),
              const SizedBox(height: 8),
              Text(
                location['address']?.toString() ?? '-',
                style: AppTheme.bodyAction.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ShwakelButton(
                  label: l.tr('screens_supported_locations_screen.046'),
                  icon: Icons.map_rounded,
                  onPressed: () async {
                    Navigator.pop(context);
                    await _openDirectionsInWebView(location);
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ShwakelButton(
                  label: l.tr('screens_supported_locations_screen.010'),
                  icon: Icons.open_in_new_rounded,
                  isSecondary: true,
                  onPressed: () async {
                    Navigator.pop(context);
                    await _openMap(location);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDirectionsInWebView(Map<String, dynamic> location) async {
    final latitude = (location['latitude'] as num?)?.toDouble();
    final longitude = (location['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null || !mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantDirectionsWebViewScreen(
          title:
              location['title']?.toString() ??
              context.loc.tr('screens_supported_locations_screen.008'),
          destinationLatitude: latitude,
          destinationLongitude: longitude,
          originLatitude: _position?.latitude,
          originLongitude: _position?.longitude,
        ),
        settings: const RouteSettings(name: '/merchant-directions'),
      ),
    );
  }

  Future<void> _showEditMyLocationDialog(Map<String, dynamic> location) async {
    final l = context.loc;
    final titleController = TextEditingController(
      text: location['title']?.toString() ?? '',
    );
    final displayNameController = TextEditingController(
      text:
          location['displayName']?.toString() ??
          location['publicDisplayName']?.toString() ??
          '',
    );
    final addressController = TextEditingController(
      text: location['address']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: location['phone']?.toString() ?? '',
    );
    final displayPhoneController = TextEditingController(
      text: location['displayPhone']?.toString() ?? '',
    );
    final displayWhatsappController = TextEditingController(
      text:
          location['displayWhatsapp']?.toString() ??
          location['linkedWhatsapp']?.toString() ??
          '',
    );
    final typeController = TextEditingController(
      text: location['type']?.toString() ?? 'shop',
    );
    final latController = TextEditingController(
      text: ((location['latitude'] as num?)?.toDouble() ?? 31.5)
          .toStringAsFixed(7),
    );
    final lngController = TextEditingController(
      text: ((location['longitude'] as num?)?.toDouble() ?? 34.47)
          .toStringAsFixed(7),
    );
    var isVisible = location['isActive'] == true;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l.tr('screens_supported_locations_screen.051')),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    value: isVisible,
                    onChanged: (value) =>
                        setDialogState(() => isVisible = value),
                    title: Text(l.tr('screens_supported_locations_screen.052')),
                    subtitle: Text(
                      l.tr('screens_supported_locations_screen.053'),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  TextField(
                    controller: displayNameController,
                    decoration: InputDecoration(
                      labelText: l.tr('screens_supported_locations_screen.054'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: displayPhoneController,
                    decoration: InputDecoration(
                      labelText: l.tr('screens_supported_locations_screen.055'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: displayWhatsappController,
                    decoration: InputDecoration(
                      labelText: l.tr('screens_supported_locations_screen.056'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: l.tr('screens_supported_locations_screen.057'),
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
                      labelText: l.tr('screens_supported_locations_screen.058'),
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final selected = await _pickLocationFromMap(
                          initialLatitude:
                              double.tryParse(latController.text.trim()) ??
                              (_position?.latitude ?? 31.5),
                          initialLongitude:
                              double.tryParse(lngController.text.trim()) ??
                              (_position?.longitude ?? 34.47),
                        );
                        if (selected == null) {
                          return;
                        }
                        latController.text = selected.latitude.toStringAsFixed(
                          7,
                        );
                        lngController.text = selected.longitude.toStringAsFixed(
                          7,
                        );
                      },
                      icon: const Icon(Icons.map_rounded),
                      label: Text(
                        l.tr('screens_supported_locations_screen.039'),
                      ),
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
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final updated = await _apiService
                            .saveMySupportedLocation(
                              locationId: location['id']?.toString() ?? '',
                              title: titleController.text,
                              displayName: displayNameController.text,
                              address: addressController.text,
                              phone: phoneController.text,
                              displayPhone: displayPhoneController.text,
                              displayWhatsapp: displayWhatsappController.text,
                              type: typeController.text,
                              latitude:
                                  double.tryParse(latController.text.trim()) ??
                                  31.5,
                              longitude:
                                  double.tryParse(lngController.text.trim()) ??
                                  34.47,
                              isActive: isVisible,
                            );
                        if (!dialogContext.mounted) {
                          return;
                        }
                        Navigator.pop(dialogContext);
                        if (!mounted) {
                          return;
                        }
                        setState(() => _myLocations = updated);
                        await _load();
                        if (!mounted) {
                          return;
                        }
                        await AppAlertService.showSuccess(
                          context,
                          title: l.tr('screens_supported_locations_screen.059'),
                          message: l.tr(
                            'screens_supported_locations_screen.060',
                          ),
                        );
                      } catch (error) {
                        if (!dialogContext.mounted) {
                          return;
                        }
                        setDialogState(() => isSaving = false);
                        await AppAlertService.showError(
                          dialogContext,
                          title: l.tr('screens_supported_locations_screen.061'),
                          message: ErrorMessageService.sanitize(error),
                        );
                      }
                    },
              child: Text(l.tr('screens_supported_locations_screen.062')),
            ),
          ],
        ),
      ),
    );

    titleController.dispose();
    displayNameController.dispose();
    addressController.dispose();
    phoneController.dispose();
    displayPhoneController.dispose();
    displayWhatsappController.dispose();
    typeController.dispose();
    latController.dispose();
    lngController.dispose();
  }

  Future<LatLng?> _pickLocationFromMap({
    required double initialLatitude,
    required double initialLongitude,
  }) async {
    LatLng selected = LatLng(initialLatitude, initialLongitude);
    return showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) => SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.76,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.loc.tr('screens_supported_locations_screen.039'),
                    style: AppTheme.h3,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.loc.tr('screens_supported_locations_screen.047'),
                    style: AppTheme.bodyAction.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: selected,
                          initialZoom: 13,
                          onTap: (_, point) {
                            setModalState(() => selected = point);
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.shwakil.app',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: selected,
                                width: 52,
                                height: 52,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.place_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ShwakelButton(
                          label: context.loc.tr(
                            'screens_supported_locations_screen.048',
                          ),
                          icon: Icons.check_rounded,
                          onPressed: () => Navigator.pop(context, selected),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SupportedLocationsView { list, map }
