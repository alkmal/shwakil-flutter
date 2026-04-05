import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_card.dart';

class UsagePolicyScreen extends StatefulWidget {
  const UsagePolicyScreen({super.key});
  @override
  State<UsagePolicyScreen> createState() => _UsagePolicyScreenState();
}

class _UsagePolicyScreenState extends State<UsagePolicyScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String _title = 'سياسة الاستخدام';
  String _content = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _apiService.getUsagePolicy();
      if (mounted) setState(() { _title = p['title'] ?? 'سياسة الاستخدام'; _content = p['content'] ?? ''; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(_title)),
      drawer: const AppSidebar(),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            children: [
              _buildLegalHero(),
              const SizedBox(height: 24),
              ShwakelCard(
                padding: const EdgeInsets.all(32),
                child: Text(_content.isEmpty ? 'لا تتوفر سياسة استخدام حالياً.' : _content, style: AppTheme.bodyAction.copyWith(height: 1.8, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalHero() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.darkGradient,
      child: Row(
        children: [
          const Icon(Icons.gavel_rounded, color: Colors.white, size: 40),
          const SizedBox(width: 24),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('الميثاق القانوني والخصوصية', style: AppTheme.h2.copyWith(color: Colors.white)), Text('التزامنا بتقديم خدمات آمنة ومنظّمة لجميع مستخدمي شواكل.', style: AppTheme.caption.copyWith(color: Colors.white70))])),
        ],
      ),
    );
  }
}
