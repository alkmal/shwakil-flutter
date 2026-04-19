import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'screens/index.dart';
import 'services/index.dart';
import 'utils/app_theme.dart';
import 'widgets/shwakel_button.dart';
import 'widgets/shwakel_logo.dart';

final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLocaleService.instance.init();
      RealtimeNotificationService.registerBackgroundHandler();
      await LocalNotificationService.initialize();
      await LocalSecurityService.getOrCreateDeviceId();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(
          AppAlertService.showGlobalError(
            title: 'خطأ في التطبيق',
            message: 'حدث خطأ غير متوقع. يمكنك المتابعة أو إعادة المحاولة.',
          ),
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          AppAlertService.showGlobalError(
            title: 'خطأ غير متوقع',
            message: 'حدث خطأ غير معالج داخل التطبيق.',
          ),
        );
        return true;
      };
      runApp(const MyApp());
    },
    (error, stack) {
      unawaited(
        AppAlertService.showGlobalError(
          title: 'خطأ غير متوقع',
          message: 'حدث خطأ غير متوقع أثناء تشغيل التطبيق.',
        ),
      );
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppLocaleService.instance,
      builder: (context, _) {
        final locale = AppLocaleService.instance.locale ?? const Locale('ar');
        final localizer = AppLocalizer(locale);

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: AppAlertService.navigatorKey,
          title: localizer.tr('main.001'),
          locale: locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorObservers: [appRouteObserver],
          theme: AppTheme.lightTheme,
          builder: (context, child) {
            SystemChrome.setSystemUIOverlayStyle(
              const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: Colors.white,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
            );
            return Directionality(
              textDirection: context.loc.textDirection,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1)),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const _AppLifecycleShell(),
          routes: {
            '/app-shell': (context) => const _AppLifecycleShell(),
            '/home': (context) => const HomeScreen(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/unlock': (context) => const DeviceUnlockScreen(),
            '/balance': (context) => const BalanceScreen(),
            '/create-card': (context) => const CreateCardScreen(),
            '/quick-transfer': (context) => const QuickTransferScreen(),
            '/card-print-requests': (context) =>
                const CardPrintRequestsScreen(),
            '/scan-card': (context) => const ScanCardScreen(),
            '/inventory': (context) => const InventoryScreen(),
            '/transactions': (context) => const TransactionsScreen(),
            '/security-settings': (context) => const SecuritySettingsScreen(),
            '/account-settings': (context) => const AccountSettingsScreen(),
            '/admin-dashboard': (context) => const AdminDashboardScreen(),
            '/admin-card-print-requests': (context) =>
                const AdminCardPrintRequestsScreen(),
            '/admin-customers': (context) => const AdminCustomersScreen(),
            '/admin-device-requests': (context) =>
                const AdminDeviceRequestsScreen(),
            '/admin-locations': (context) => const AdminLocationsScreen(),
            '/admin-system-settings': (context) =>
                const AdminSystemSettingsScreen(),
            '/admin-permissions': (context) => const AdminPermissionsScreen(),
            '/withdrawal-requests': (context) =>
                const WithdrawalRequestsScreen(),
            '/topup-requests': (context) => const TopupRequestsScreen(),
            '/usage-policy': (context) => const UsagePolicyScreen(),
            '/contact-us': (context) => const ContactUsScreen(),
            '/supported-locations': (context) =>
                const SupportedLocationsScreen(),
            '/forgot-password': (context) => const ForgotPasswordScreen(),
            '/account-verification': (context) =>
                const AccountVerificationScreen(),
            '/sub-users': (context) => const SubUsersScreen(),
          },
        );
      },
    );
  }
}

class _AppLifecycleShell extends StatefulWidget {
  const _AppLifecycleShell();
  @override
  State<_AppLifecycleShell> createState() => _AppLifecycleShellState();
}

class _AppLifecycleShellState extends State<_AppLifecycleShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(LocalSecurityService.markAppBackgrounded());
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.resumed:
        unawaited(LocalSecurityService.handleAppResumed());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const AppEntryPoint();
  }
}

enum _LaunchState { onboarding, login, unlock, home, updateRequired }

class _LaunchDecision {
  const _LaunchDecision({required this.state, this.updateRequirement});

  final _LaunchState state;
  final AppUpdateRequirement? updateRequirement;
}

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({super.key});
  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  static const String _onboardingSeenKey = 'onboarding_seen_v1';
  late Future<_LaunchDecision> _launchStateFuture;
  bool _localUnlockSatisfiedThisSession = false;
  @override
  void initState() {
    super.initState();
    _launchStateFuture = _resolveLaunchState();
    LocalSecurityService.securityStateListenable.addListener(
      _refreshLaunchState,
    );
  }

  @override
  void dispose() {
    LocalSecurityService.securityStateListenable.removeListener(
      _refreshLaunchState,
    );
    super.dispose();
  }

  void _refreshLaunchState() {
    if (!mounted) {
      return;
    }
    setState(() {
      _launchStateFuture = _resolveLaunchState();
    });
  }

  Future<_LaunchDecision> _resolveLaunchState() async {
    final updateRequirement = await AppVersionService.fetchRequiredUpdate();
    if (updateRequirement != null) {
      return _LaunchDecision(
        state: _LaunchState.updateRequired,
        updateRequirement: updateRequirement,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool(_onboardingSeenKey) ?? false;
    if (!hasSeenOnboarding) {
      return const _LaunchDecision(state: _LaunchState.onboarding);
    }

    final authService = AuthService();
    final isLoggedIn = await authService.isLoggedIn();
    if (!isLoggedIn) {
      _localUnlockSatisfiedThisSession = false;
      await RealtimeNotificationService.stop();
      return const _LaunchDecision(state: _LaunchState.login);
    }
    final skipNextUnlock = await LocalSecurityService.consumeSkipNextUnlock();
    if (skipNextUnlock) {
      _localUnlockSatisfiedThisSession = true;
      await RealtimeNotificationService.start();
      return const _LaunchDecision(state: _LaunchState.home);
    }
    final relockRequired = LocalSecurityService.relockRequired;
    final canUseTrustedUnlock =
        await LocalSecurityService.canUseTrustedUnlock();
    if (relockRequired || canUseTrustedUnlock) {
      if (!relockRequired && _localUnlockSatisfiedThisSession) {
        await RealtimeNotificationService.start();
        return const _LaunchDecision(state: _LaunchState.home);
      }
      await RealtimeNotificationService.stop();
      if (canUseTrustedUnlock) {
        return const _LaunchDecision(state: _LaunchState.unlock);
      }
      _localUnlockSatisfiedThisSession = false;
      await authService.logout();
      return const _LaunchDecision(state: _LaunchState.login);
    }
    try {
      await authService.refreshCurrentUser();
    } catch (_) {
      _localUnlockSatisfiedThisSession = false;
      await authService.logout();
      await RealtimeNotificationService.stop();
      return const _LaunchDecision(state: _LaunchState.login);
    }
    _localUnlockSatisfiedThisSession = true;
    await RealtimeNotificationService.start();
    return const _LaunchDecision(state: _LaunchState.home);
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
    _refreshLaunchState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LaunchDecision>(
      future: _launchStateFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const _SplashScreen();
        }
        final decision = snapshot.data!;
        switch (decision.state) {
          case _LaunchState.onboarding:
            return OnboardingScreen(onFinished: _finishOnboarding);
          case _LaunchState.unlock:
            return const DeviceUnlockScreen();
          case _LaunchState.home:
            return const HomeScreen();
          case _LaunchState.login:
            return const LoginScreen();
          case _LaunchState.updateRequired:
            return _ForcedUpdateScreen(
              requirement: decision.updateRequirement!,
              onRetry: _refreshLaunchState,
            );
        }
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 132,
                height: 132,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/shwakel_app_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'شواكل',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'نظام بطاقات رقمية ورصيد داخلي لإدارة الاستخدام',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForcedUpdateScreen extends StatelessWidget {
  const _ForcedUpdateScreen({required this.requirement, required this.onRetry});

  final AppUpdateRequirement requirement;
  final VoidCallback onRetry;

  Future<void> _openStore() async {
    if (!requirement.hasStoreUrl) {
      return;
    }

    await launchUrl(
      Uri.parse(requirement.storeUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.pageBackgroundGradient,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ShwakelLogo(size: 78, framed: true),
                      const SizedBox(height: 20),
                      Text(
                        'تحديث مطلوب',
                        style: AppTheme.h1,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'يجب تحديث التطبيق للمتابعة بأمان.',
                        style: AppTheme.bodyAction.copyWith(height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _versionRow('نسختك الحالية', requirement.currentVersion),
                      const SizedBox(height: 10),
                      _versionRow(
                        'أقل نسخة مسموحة',
                        requirement.minSupportedVersion,
                      ),
                      const SizedBox(height: 10),
                      _versionRow('أحدث نسخة', requirement.latestVersion),
                      const SizedBox(height: 24),
                      ShwakelButton(
                        label: requirement.hasStoreUrl
                            ? 'فتح صفحة التحديث'
                            : 'رابط التحديث غير متوفر',
                        icon: Icons.system_update_rounded,
                        onPressed: requirement.hasStoreUrl ? _openStore : null,
                      ),
                      const SizedBox(height: 12),
                      ShwakelButton(
                        label: 'إعادة التحقق',
                        isSecondary: true,
                        icon: Icons.refresh_rounded,
                        onPressed: onRetry,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _versionRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.bodyAction)),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppTheme.bodyBold.copyWith(color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}
