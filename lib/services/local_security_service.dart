import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class LocalSecurityService {
  LocalSecurityService._();

  static const _deviceIdKey = 'device_id';
  static const _legacyPinKey = 'device_pin';
  static const _pinHashKey = 'device_pin_hash';
  static const _biometricEnabledKey = 'biometric_enabled';
  static const _trustedUsernameKey = 'trusted_username';
  static const _deviceTrustedKey = 'device_trusted';
  static const _lastAuthMethodKey = 'last_local_auth_method';
  static const _backgroundedAtKey = 'app_backgrounded_at';
  static const _relockTimeoutSecondsKey = 'relock_timeout_seconds';
  static const _pinFailedAttemptsKey = 'pin_failed_attempts';
  static const _pinLockoutUntilKey = 'pin_lockout_until';

  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const Uuid _uuid = Uuid();
  static final ValueNotifier<int> _securityStateVersion = ValueNotifier<int>(0);
  static const Sha256 _sha256 = Sha256();

  static bool _relockRequired = false;
  static bool _skipNextUnlock = false;

  static const List<int> relockTimeoutOptionsInSeconds = [0, 30, 60, 300];
  static const int _pinMaxFailedAttempts = 5;
  static const int _pinLockoutSeconds = 60;

  static const Map<String, String> _digitMap = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  static ValueListenable<int> get securityStateListenable =>
      _securityStateVersion;
  static bool get relockRequired => _relockRequired;

  static void _notifySecurityStateChanged() {
    _securityStateVersion.value++;
  }

  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _uuid.v4();
    await prefs.setString(_deviceIdKey, created);
    return created;
  }

  static Future<String> currentDeviceLabel() async {
    if (kIsWeb) {
      return 'Web Browser';
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android Device',
      TargetPlatform.iOS => 'iPhone / iPad',
      TargetPlatform.windows => 'Windows Device',
      TargetPlatform.macOS => 'macOS Device',
      TargetPlatform.linux => 'Linux Device',
      TargetPlatform.fuchsia => 'Fuchsia Device',
    };
  }

  static Future<String> currentDeviceDisplayName() async {
    final label = await currentDeviceLabel();
    final deviceId = await getOrCreateDeviceId();
    final shortId = deviceId.length <= 8 ? deviceId : deviceId.substring(0, 8);
    return '$label - $shortId';
  }

  static Future<void> markDeviceTrusted(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deviceTrustedKey, true);
    await prefs.setString(_trustedUsernameKey, username.trim());
  }

  static Future<void> clearTrustedState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPinKey);
    await prefs.remove(_biometricEnabledKey);
    await prefs.remove(_trustedUsernameKey);
    await prefs.remove(_deviceTrustedKey);
    await prefs.remove(_backgroundedAtKey);
    await prefs.remove(_pinFailedAttemptsKey);
    await prefs.remove(_pinLockoutUntilKey);
    await _secureStorage.delete(key: _pinHashKey);
    _relockRequired = false;
    _skipNextUnlock = false;
    _notifySecurityStateChanged();
  }

  static Future<void> skipNextUnlock() async {
    _skipNextUnlock = true;
  }

  static Future<bool> consumeSkipNextUnlock() async {
    final shouldSkip = _skipNextUnlock;
    _skipNextUnlock = false;
    return shouldSkip;
  }

  static Future<int> relockTimeoutInSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_relockTimeoutSecondsKey) ?? 30;
  }

  static Future<void> setRelockTimeoutInSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_relockTimeoutSecondsKey, seconds);
    _notifySecurityStateChanged();
  }

  static Future<bool> isTrustedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deviceTrustedKey) ?? false;
  }

  static Future<String?> trustedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_trustedUsernameKey);
  }

  static Future<void> savePin(String pin) async {
    final normalizedPin = _normalizePin(pin);
    if (normalizedPin.length != 4) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(
      key: _pinHashKey,
      value: await _hashPin(normalizedPin),
    );
    await prefs.remove(_legacyPinKey);
    await prefs.remove(_pinFailedAttemptsKey);
    await prefs.remove(_pinLockoutUntilKey);
    _notifySecurityStateChanged();
  }

  static Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPinKey);
    await prefs.remove(_pinFailedAttemptsKey);
    await prefs.remove(_pinLockoutUntilKey);
    await _secureStorage.delete(key: _pinHashKey);
    _notifySecurityStateChanged();
  }

  static Future<bool> hasPin() async {
    await _migrateLegacyPinIfNeeded();
    final storedHash = await _secureStorage.read(key: _pinHashKey);
    return (storedHash ?? '').isNotEmpty;
  }

  static Future<bool> verifyPin(String pin) async {
    await _migrateLegacyPinIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_pinLockoutUntilKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockoutUntil > now) {
      return false;
    }

    final normalizedPin = _normalizePin(pin);
    final storedHash = await _secureStorage.read(key: _pinHashKey);
    final isValid =
        normalizedPin.length == 4 &&
        (storedHash ?? '').isNotEmpty &&
        storedHash == await _hashPin(normalizedPin);

    if (isValid) {
      await prefs.remove(_pinFailedAttemptsKey);
      await prefs.remove(_pinLockoutUntilKey);
      await setLastLocalAuthMethod('pin');
      return true;
    }

    final failedAttempts = (prefs.getInt(_pinFailedAttemptsKey) ?? 0) + 1;
    await prefs.setInt(_pinFailedAttemptsKey, failedAttempts);
    if (failedAttempts >= _pinMaxFailedAttempts) {
      await prefs.setInt(
        _pinLockoutUntilKey,
        now + Duration(seconds: _pinLockoutSeconds).inMilliseconds,
      );
      await prefs.setInt(_pinFailedAttemptsKey, 0);
    }

    _notifySecurityStateChanged();
    return false;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, value);
    _notifySecurityStateChanged();
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  static Future<bool> canUseTrustedUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    final isTrusted = prefs.getBool(_deviceTrustedKey) ?? false;
    final hasPin = await LocalSecurityService.hasPin();
    final biometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;
    final biometricAvailable = biometricEnabled
        ? await canUseBiometrics()
        : false;
    return isTrusted && (hasPin || biometricAvailable);
  }

  static Future<bool> canUseBiometrics() async {
    if (kIsWeb) {
      return false;
    }
    final isSupported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    return isSupported && canCheck;
  }

  static Future<bool> authenticateWithBiometrics() async {
    if (kIsWeb) {
      return false;
    }
    final canUse = await canUseBiometrics();
    if (!canUse) {
      return false;
    }
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate with biometrics to continue in shwakil',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (authenticated) {
        await setLastLocalAuthMethod('biometric');
      }
      return authenticated;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setLastLocalAuthMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAuthMethodKey, method);
    _notifySecurityStateChanged();
  }

  static Future<String?> lastLocalAuthMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastAuthMethodKey);
  }

  static Future<void> markAppBackgrounded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _backgroundedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> handleAppResumed() async {
    final prefs = await SharedPreferences.getInstance();
    final backgroundedAt = prefs.getInt(_backgroundedAtKey);
    await prefs.remove(_backgroundedAtKey);
    if (backgroundedAt == null) {
      return;
    }
    final relockTimeout = await relockTimeoutInSeconds();
    final elapsed = DateTime.now().millisecondsSinceEpoch - backgroundedAt;
    final canUseUnlock = await canUseTrustedUnlock();
    if (canUseUnlock &&
        elapsed >= Duration(seconds: relockTimeout).inMilliseconds) {
      _relockRequired = true;
      _notifySecurityStateChanged();
    }
  }

  static Future<void> clearRelockRequirement() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backgroundedAtKey);
    _relockRequired = false;
    _notifySecurityStateChanged();
  }

  static Future<int> pinRetryAfterSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_pinLockoutUntilKey) ?? 0;
    final remainingMs = lockoutUntil - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) {
      return 0;
    }

    return (remainingMs / 1000).ceil();
  }

  static Future<void> _migrateLegacyPinIfNeeded() async {
    final legacyPrefs = await SharedPreferences.getInstance();
    final existingHash = await _secureStorage.read(key: _pinHashKey);
    if ((existingHash ?? '').isNotEmpty) {
      return;
    }

    final legacyPin = _normalizePin(legacyPrefs.getString(_legacyPinKey) ?? '');
    if (legacyPin.length != 4) {
      return;
    }

    await _secureStorage.write(
      key: _pinHashKey,
      value: await _hashPin(legacyPin),
    );
    await legacyPrefs.remove(_legacyPinKey);
  }

  static Future<String> _hashPin(String pin) async {
    final digest = await _sha256.hash(pin.codeUnits);
    return digest.bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _normalizePin(String pin) {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final rune in trimmed.runes) {
      final char = String.fromCharCode(rune);
      if (_digitMap.containsKey(char)) {
        buffer.write(_digitMap[char]);
      } else if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }
}
