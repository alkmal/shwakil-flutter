import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
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

  List<Map<String, dynamic>> _locations = const [];
  Position? _position;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final locations = await _apiService.getSupportedLocations();
      final currentPosition =
          await TransactionLocationService.currentPosition();
      final sorted = locations
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

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
        _position = currentPosition;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_supported_locations_screen.001')),
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
                    children: [
                      _buildMapHero(),
                      const SizedBox(height: 24),
                      if (_position != null) ...[
                        _buildDistanceHint(),
                        const SizedBox(height: 16),
                      ],
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

  Widget _buildMapHero() {
    final l = context.loc;
    final hasDistanceSorting = _position != null;

    return ShwakelCard(
      padding: const EdgeInsets.all(30),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 640;
          final iconBox = Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.map_rounded, color: Colors.white, size: 38),
          );

          final content = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_supported_locations_screen.002'),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('screens_supported_locations_screen.003'),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _heroChip(
                      icon: Icons.storefront_rounded,
                      label: l.tr(
                        'screens_supported_locations_screen.004',
                        params: {'count': '${_locations.length}'},
                      ),
                    ),
                    _heroChip(
                      icon: Icons.my_location_rounded,
                      label: hasDistanceSorting
                          ? l.tr('screens_supported_locations_screen.005')
                          : l.tr('screens_supported_locations_screen.006'),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [iconBox, const SizedBox(height: 18), content],
            );
          }

          return Row(children: [iconBox, const SizedBox(width: 20), content]);
        },
      ),
    );
  }

  Widget _buildDistanceHint() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(14),
      color: AppTheme.success.withValues(alpha: 0.05),
      borderColor: AppTheme.success.withValues(alpha: 0.20),
      child: Row(
        children: [
          const Icon(
            Icons.my_location_rounded,
            color: AppTheme.success,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.tr('screens_supported_locations_screen.007'),
              style: AppTheme.caption.copyWith(
                color: AppTheme.success,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTile(Map<String, dynamic> location) {
    final l = context.loc;
    final distance = location['dist'] as double?;
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

  Widget _heroChip({required IconData icon, required String label}) {
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
