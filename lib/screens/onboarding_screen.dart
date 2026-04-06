import 'package:flutter/material.dart';

import '../services/index.dart';
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
      id: 'wallet',
      icon: Icons.account_balance_wallet_rounded,
      accentColor: Color(0xFF0F766E),
    ),
    _OnboardingSlideData(
      id: 'speed',
      icon: Icons.qr_code_scanner_rounded,
      accentColor: Color(0xFF2563EB),
    ),
    _OnboardingSlideData(
      id: 'security',
      icon: Icons.verified_user_rounded,
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
    final l = context.loc;
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
                      child: Text(l.text('تخطي', 'Skip')),
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
                      ? l.text('ابدأ الآن', 'Get Started')
                      : l.text('التالي', 'Next'),
                  icon: _currentPage == _slides.length - 1
                      ? (l.isArabic
                            ? Icons.arrow_back_rounded
                            : Icons.arrow_forward_rounded)
                      : (l.isArabic
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded),
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
    final l = context.loc;
    final title = switch (slide.id) {
      'wallet' => l.text(
          'رصيدك وخدماتك في مكان واحد',
          'Your balance and services in one place',
        ),
      'speed' => l.text(
          'تنفيذ أسرع للبطاقات والتحويلات',
          'Faster card and transfer actions',
        ),
      _ => l.text(
          'حماية وتجربة استخدام موثوقة',
          'Trusted protection and a reliable experience',
        ),
    };
    final description = switch (slide.id) {
      'wallet' => l.text(
          'تابع الرصيد، أنشئ البطاقات، وادخل إلى أهم العمليات اليومية من واجهة بسيطة وواضحة.',
          'Track your balance, create cards, and access daily operations from a clear and simple interface.',
        ),
      'speed' => l.text(
          'التطبيق مصمم لتقليل الخطوات وتسريع الوصول إلى إنشاء البطاقات، المسح، والتحويل.',
          'The app is designed to reduce steps and speed up access to card creation, scanning, and transfers.',
        ),
      _ => l.text(
          'التحقق، إدارة الحساب، والعمليات الحساسة كلها منظمة بطريقة آمنة ومريحة للمستخدم.',
          'Verification, account management, and sensitive actions are organized in a secure and user-friendly way.',
        ),
    };

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
          title,
          textAlign: TextAlign.center,
          style: AppTheme.h1.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            description,
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
    required this.id,
    required this.icon,
    required this.accentColor,
  });

  final String id;
  final IconData icon;
  final Color accentColor;
}
