import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/index.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_button.dart';

class SupportedLocationsScreen extends StatefulWidget {
  const SupportedLocationsScreen({super.key});
  @override
  State<SupportedLocationsScreen> createState() =>
      _SupportedLocationsScreenState();
}

class _SupportedLocationsScreenState extends State<SupportedLocationsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _locations = const [];
  Position? _pos;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final locs = await _apiService.getSupportedLocations();
      final pos = await TransactionLocationService.currentPosition();
      final sorted = locs.map((l) => Map<String, dynamic>.from(l)).toList();
      if (pos != null) {
        for (final l in sorted) {
          final lat = (l['latitude'] as num?)?.toDouble();
          final lon = (l['longitude'] as num?)?.toDouble();
          if (lat != null && lon != null)
            l['dist'] = Geolocator.distanceBetween(
              pos.latitude,
              pos.longitude,
              lat,
              lon,
            );
        }
        sorted.sort(
          (a, b) => (a['dist'] as double? ?? 999999).compareTo(
            b['dist'] as double? ?? 999999,
          ),
        );
      }
      if (mounted)
        setState(() {
          _locations = sorted;
          _pos = pos;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('الفروع ومراكز الخدمة')),
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
                      if (_pos != null) _buildDistanceHint(),
                      const SizedBox(height: 16),
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
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.primaryGradient,
      child: Row(
        children: [
          const Icon(Icons.map_rounded, color: Colors.white, size: 40),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'خريطة شواكل التفاعلية',
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                Text(
                  'اعثر على أقرب وكيل أو نقطة شحن أو توزيع معتمدة في منطقتك.',
                  style: AppTheme.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceHint() {
    return ShwakelCard(
      padding: const EdgeInsets.all(12),
      color: AppTheme.success.withOpacity(0.05),
      borderColor: AppTheme.success.withOpacity(0.2),
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
              'تم ترتيب المواقع تلقائيًا حسب المسافة من موقعك الحالي.',
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

  Widget _buildLocationTile(Map<String, dynamic> l) {
    final dist = l['dist'] as double?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ShwakelCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: Icon(
                    Icons.storefront_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l['title'] ?? 'فرع شواكل', style: AppTheme.bodyBold),
                      Text(
                        l['type'] ?? 'نقطة بيع معتمدة',
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (dist != null)
                  Text(
                    _fmtDist(dist),
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textTertiary,
                    ),
                  ),
              ],
            ),
            const Divider(height: 32),
            _info(Icons.location_on_rounded, l['address'] ?? '-'),
            const SizedBox(height: 8),
            _info(Icons.phone_rounded, l['phone'] ?? '-'),
            const SizedBox(height: 24),
            ShwakelButton(
              label: 'فتح في الخرائط',
              icon: Icons.directions_rounded,
              onPressed: () => _openMap(l),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(60),
      child: Column(
        children: [
          Icon(
            Icons.map_outlined,
            size: 60,
            color: AppTheme.textTertiary.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'لا توجد مواقع مسجلة حالياً',
            style: AppTheme.h3.copyWith(color: AppTheme.textTertiary),
          ),
        ],
      ),
    ),
  );
  Widget _info(IconData i, String v) => Row(
    children: [
      Icon(i, size: 16, color: AppTheme.textTertiary),
      const SizedBox(width: 12),
      Expanded(child: Text(v, style: AppTheme.caption)),
    ],
  );
  String _fmtDist(double m) =>
      m < 1000 ? '${m.round()} متر' : '${(m / 1000).toStringAsFixed(1)} كم';

  Future<void> _openMap(Map<String, dynamic> l) async {
    final lat = l['latitude'], lon = l['longitude'];
    if (lat == null || lon == null) return;
    await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
      mode: LaunchMode.externalApplication,
    );
  }
}
