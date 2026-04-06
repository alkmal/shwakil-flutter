import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_logo.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  static const List<_OnboardingSlideData> _slides = [
    _OnboardingSlideData(
      icon: Icons.account_balance_wallet_rounded,
      title: 'رصيدك وخدماتك في مكان واحد',
      description:
          'تابع الرصيد، أنشئ البطاقات، وادخل إلى أهم العمليات اليومية من واجهة بسيطة وواضحة.',
      accentColor: Color(0xFF0F766E),
    ),
    _OnboardingSlideData(
      icon: Icons.qr_code_scanner_rounded,
      title: 'تنفيذ أسرع للبطاقات والتحويلات',
      description:
          'التطبيق مصمم لتقليل الخطوات وتسريع الوصول إلى إنشاء البطاقات، المسح، والتحويل.',
      accentColor: Color(0xFF2563EB),
    ),
    _OnboardingSlideData(
      icon: Icons.verified_user_rounded,
      title: 'حماية وتجربة استخدام موثوقة',
      description:
          'التحقق، إدارة الحساب، والعمليات الحساسة كلها منظمة بطريقة آمنة ومريحة للمستخدم.',
      accentColor: Color(0xFFF97316),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (_currentPage < _slides.length - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    if (_isFinishing) {
      return;
    }

    setState(() => _isFinishing = true);
    try {
      await widget.onFinished();
    } finally {
      if (mounted) {
        setState(() => _isFinishing = false);
      }
    }
  }

  Future<void> _skip() async {
    if (_isFinishing) {
      return;
    }

    setState(() => _isFinishing = true);
    try {
      await widget.onFinished();
    } finally {
      if (mounted) {
        setState(() => _isFinishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              const Color(0xFFF1F8F7),
              AppTheme.primarySoft.withValues(alpha: 0.75),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ResponsiveScaffoldContainer(
            maxWidth: 720,
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              children: [
                Row(
                  children: [
                    const ShwakelLogo(size: 56, framed: true),
                    const Spacer(),
                    TextButton(
                      onPressed: _isFinishing ? null : _skip,
                      child: const Text('تخطي'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemBuilder: (context, index) {
                      final slide = _slides[index];
                      return _OnboardingSlide(slide: slide);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (index) {
                    final isActive = index == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: isActive ? 28 : 10,
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? _slides[_currentPage].accentColor
                            : AppTheme.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                ShwakelButton(
                  label: _currentPage == _slides.length - 1
                      ? 'ابدأ الآن'
                      : 'التالي',
                  icon: _currentPage == _slides.length - 1
                      ? Icons.arrow_forward_rounded
                      : Icons.chevron_left_rounded,
                  iconAtEnd: true,
                  isLoading: _isFinishing,
                  onPressed: _goNext,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.slide});

  final _OnboardingSlideData slide;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                slide.accentColor.withValues(alpha: 0.16),
                slide.accentColor.withValues(alpha: 0.04),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Container(
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                color: slide.accentColor,
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: slide.accentColor.withValues(alpha: 0.26),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Icon(slide.icon, color: Colors.white, size: 54),
            ),
          ),
        ),
        const SizedBox(height: 36),
        Text(
          slide.title,
          textAlign: TextAlign.center,
          style: AppTheme.h1.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            slide.description,
            textAlign: TextAlign.center,
            style: AppTheme.bodyAction.copyWith(
              color: AppTheme.textSecondary,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }
}

class _OnboardingSlideData {
  const _OnboardingSlideData({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
}
