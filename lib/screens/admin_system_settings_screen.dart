import 'dart:async';

import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AdminSystemSettingsScreen extends StatefulWidget {
  const AdminSystemSettingsScreen({super.key});

  @override
  State<AdminSystemSettingsScreen> createState() =>
      _AdminSystemSettingsScreenState();
}

class _AdminSystemSettingsScreenState extends State<AdminSystemSettingsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  final _contactTitleController = TextEditingController();
  final _contactWhatsappController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactAddressController = TextEditingController();
  final _policyTitleController = TextEditingController();
  final _policyContentController = TextEditingController();
  final _unverifiedTransferLimitController = TextEditingController(text: '200');
  final _topupRequestInstructionsController = TextEditingController();
  final _minSupportedVersionController = TextEditingController();
  final _latestVersionController = TextEditingController();
  final _androidStoreUrlController = TextEditingController();
  final _iosStoreUrlController = TextEditingController();
  final _webStoreUrlController = TextEditingController();
  final _walletTopupFeeController = TextEditingController();
  final _walletTransferFeeController = TextEditingController();
  final _cardRedeemFeeController = TextEditingController();
  final _cardResellFeeController = TextEditingController();
  final _cardPrintRequestFeeController = TextEditingController();
  final _withdrawFeeController = TextEditingController();
  final _standardCardIssueCostController = TextEditingController();
  final _deliveryCardIssueCostController = TextEditingController();
  final _privateCardIssueCostController = TextEditingController();
  final _singleUseTicketIssueCostController = TextEditingController();
  final _appointmentTicketIssueCostController = TextEditingController();
  final _queueTicketIssueCostController = TextEditingController();
  final _scanDefaultLimitController = TextEditingController();
  final _scanRestrictedLimitController = TextEditingController();
  final _scanBasicLimitController = TextEditingController();
  final _scanVerifiedLimitController = TextEditingController();
  final _scanDriverLimitController = TextEditingController();
  final _scanMarketerLimitController = TextEditingController();
  final _scanSupportLimitController = TextEditingController();
  final _scanFinanceLimitController = TextEditingController();
  final _scanAdminLimitController = TextEditingController();
  final _offlineMaxPendingAmountController = TextEditingController();
  final _offlineMaxPendingCountController = TextEditingController();
  final _offlineCacheLimitController = TextEditingController();
  final _offlineSyncIntervalController = TextEditingController();
  final _prepaidMaxCardAmountController = TextEditingController();
  final _prepaidMaxPaymentAmountController = TextEditingController();
  final _prepaidMaxActiveCardsController = TextEditingController();
  final _prepaidMaxExpiryDaysController = TextEditingController();
  final _prepaidDailyAmountLimitController = TextEditingController();
  final _prepaidDailyCountLimitController = TextEditingController();
  final _prepaidReportBuyerIdController = TextEditingController();
  final _prepaidReportMerchantIdController = TextEditingController();
  final _prepaidReportDateFromController = TextEditingController();
  final _prepaidReportDateToController = TextEditingController();
  final _prepaidReportSearchController = TextEditingController();
  final _affiliateRewardAmountController = TextEditingController();
  final _affiliateFirstTopupMinAmountController = TextEditingController();
  final _affiliateMarketerDebtLimitController = TextEditingController();
  final _withdrawalRequestInstructionsController = TextEditingController();
  final _withdrawalMinAmountController = TextEditingController();
  final _withdrawalMaxAmountController = TextEditingController();
  final _topupMinAmountController = TextEditingController();
  final _topupMaxAmountController = TextEditingController();
  final _cardQtyDefaultController = TextEditingController();
  final _cardQtyRestrictedController = TextEditingController();
  final _cardQtyBasicController = TextEditingController();
  final _cardQtyVerifiedController = TextEditingController();
  final _cardQtyDriverController = TextEditingController();
  final _cardQtyMarketerController = TextEditingController();
  final _cardQtySupportController = TextEditingController();
  final _cardQtyFinanceController = TextEditingController();
  final _cardQtyAdminController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAuthorized = false;
  bool _registrationEnabled = true;
  bool _loginOtpRequired = false;
  bool _registrationWhatsappVerificationRequired = true;
  String _whatsappUsageMode = 'all';
  String _messageDeliveryPriority = 'whatsapp';
  bool _topupRequestEnabled = true;
  bool _withdrawalRequestEnabled = true;
  bool _affiliateEnabled = true;
  bool _scanAutoRedeemGlobalForced = false;
  bool _isLoadingPrepaidReport = false;
  String _prepaidReportCardStatus = 'all';
  List<Map<String, dynamic>> _topupPaymentMethods = const [];
  List<Map<String, dynamic>> _withdrawalMethods = const [];
  List<Map<String, dynamic>> _prepaidReportPayments = const [];
  Map<String, dynamic> _prepaidReportSummary = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contactTitleController.dispose();
    _contactWhatsappController.dispose();
    _contactEmailController.dispose();
    _contactAddressController.dispose();
    _policyTitleController.dispose();
    _policyContentController.dispose();
    _unverifiedTransferLimitController.dispose();
    _topupRequestInstructionsController.dispose();
    _minSupportedVersionController.dispose();
    _latestVersionController.dispose();
    _androidStoreUrlController.dispose();
    _iosStoreUrlController.dispose();
    _webStoreUrlController.dispose();
    _walletTopupFeeController.dispose();
    _walletTransferFeeController.dispose();
    _cardRedeemFeeController.dispose();
    _cardResellFeeController.dispose();
    _cardPrintRequestFeeController.dispose();
    _withdrawFeeController.dispose();
    _standardCardIssueCostController.dispose();
    _deliveryCardIssueCostController.dispose();
    _privateCardIssueCostController.dispose();
    _singleUseTicketIssueCostController.dispose();
    _appointmentTicketIssueCostController.dispose();
    _queueTicketIssueCostController.dispose();
    _scanDefaultLimitController.dispose();
    _scanRestrictedLimitController.dispose();
    _scanBasicLimitController.dispose();
    _scanVerifiedLimitController.dispose();
    _scanDriverLimitController.dispose();
    _scanMarketerLimitController.dispose();
    _scanSupportLimitController.dispose();
    _scanFinanceLimitController.dispose();
    _scanAdminLimitController.dispose();
    _offlineMaxPendingAmountController.dispose();
    _offlineMaxPendingCountController.dispose();
    _offlineCacheLimitController.dispose();
    _offlineSyncIntervalController.dispose();
    _prepaidMaxCardAmountController.dispose();
    _prepaidMaxPaymentAmountController.dispose();
    _prepaidMaxActiveCardsController.dispose();
    _prepaidMaxExpiryDaysController.dispose();
    _prepaidDailyAmountLimitController.dispose();
    _prepaidDailyCountLimitController.dispose();
    _prepaidReportBuyerIdController.dispose();
    _prepaidReportMerchantIdController.dispose();
    _prepaidReportDateFromController.dispose();
    _prepaidReportDateToController.dispose();
    _prepaidReportSearchController.dispose();
    _affiliateRewardAmountController.dispose();
    _affiliateFirstTopupMinAmountController.dispose();
    _affiliateMarketerDebtLimitController.dispose();
    _withdrawalRequestInstructionsController.dispose();
    _withdrawalMinAmountController.dispose();
    _withdrawalMaxAmountController.dispose();
    _topupMinAmountController.dispose();
    _topupMaxAmountController.dispose();
    _cardQtyDefaultController.dispose();
    _cardQtyRestrictedController.dispose();
    _cardQtyBasicController.dispose();
    _cardQtyVerifiedController.dispose();
    _cardQtyDriverController.dispose();
    _cardQtyMarketerController.dispose();
    _cardQtySupportController.dispose();
    _cardQtyFinanceController.dispose();
    _cardQtyAdminController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final currentAppVersionFuture = AppVersionService.currentVersion();
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canManageSystemSettings) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }
      final results = await Future.wait<dynamic>([
        currentAppVersionFuture,
        _apiService.getContactInfo(),
        _apiService.getAuthSettings(),
        _apiService.getTransferSettings(),
        _apiService.getOfflineCardSettings(),
        _apiService.getFeeSettings(),
        _apiService.getCardScanLimitSettings(),
        _apiService.getAdminTopupRequestSettings(),
        _apiService.getAdminWithdrawalRequestSettings(),
        _apiService.getAdminAffiliateSettings(),
        _apiService.getAdminTopupPaymentMethods(),
        _apiService.getAdminWithdrawalMethods(),
        _apiService.getUsagePolicy(),
        _apiService.getAdminPrepaidMultipaySettings(),
        _apiService.getCardQuantityLimitSettings(),
      ]);

      if (!mounted) {
        return;
      }

      final currentAppVersion = results[0] as String;
      final contactSettings = Map<String, dynamic>.from(results[1] as Map);
      final authSettings = Map<String, dynamic>.from(results[2] as Map);
      final transferSettings = Map<String, dynamic>.from(results[3] as Map);
      final offlineCardSettings = Map<String, dynamic>.from(results[4] as Map);
      final feeSettings = Map<String, dynamic>.from(results[5] as Map);
      final cardScanLimitSettings = Map<String, dynamic>.from(
        results[6] as Map,
      );
      final topupRequestSettings = Map<String, dynamic>.from(results[7] as Map);
      final withdrawalRequestSettings = Map<String, dynamic>.from(
        results[8] as Map,
      );
      final affiliateSettings = Map<String, dynamic>.from(results[9] as Map);
      final topupPaymentMethods = List<Map<String, dynamic>>.from(
        (results[10] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final withdrawalMethods = List<Map<String, dynamic>>.from(
        (results[11] as List).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final usagePolicy = Map<String, dynamic>.from(results[12] as Map);
      final prepaidMultipaySettings = Map<String, dynamic>.from(
        results[13] as Map,
      );
      final cardQuantityLimitSettings = Map<String, dynamic>.from(
        results[14] as Map,
      );

      _contactTitleController.text = contactSettings['title'] ?? '';
      _contactWhatsappController.text =
          contactSettings['supportWhatsapp'] ?? '';
      _contactEmailController.text = contactSettings['supportEmail'] ?? '';
      _contactAddressController.text = contactSettings['address'] ?? '';
      _registrationEnabled = authSettings['registrationEnabled'] == true;
      _loginOtpRequired = authSettings['loginOtpRequired'] != false;
      _registrationWhatsappVerificationRequired =
          authSettings['registrationWhatsappVerificationRequired'] != false;
      _whatsappUsageMode = _normalizeWhatsappUsageMode(
        authSettings['whatsappUsageMode'],
      );
      _messageDeliveryPriority = _normalizeMessageDeliveryPriority(
        authSettings['messageDeliveryPriority'],
      );
      final minSupportedVersion =
          authSettings['minSupportedVersion']?.toString().trim() ?? '';
      final latestVersion =
          authSettings['latestVersion']?.toString().trim() ?? '';
      _minSupportedVersionController.text = minSupportedVersion.isNotEmpty
          ? minSupportedVersion
          : currentAppVersion;
      _latestVersionController.text = latestVersion.isNotEmpty
          ? latestVersion
          : currentAppVersion;
      _androidStoreUrlController.text =
          authSettings['androidStoreUrl']?.toString() ?? '';
      _iosStoreUrlController.text =
          authSettings['iosStoreUrl']?.toString() ?? '';
      _webStoreUrlController.text =
          authSettings['webStoreUrl']?.toString() ?? '';
      _unverifiedTransferLimitController.text =
          (transferSettings['unverifiedTransferLimit'] as num?)
              ?.toStringAsFixed(2) ??
          '200';
      _walletTopupFeeController.text =
          (feeSettings['walletTopupPercent'] as num?)?.toString() ?? '1';
      _walletTransferFeeController.text =
          (feeSettings['walletTransferPercent'] as num?)?.toString() ?? '1';
      _cardRedeemFeeController.text =
          (feeSettings['cardRedeemPercent'] as num?)?.toString() ?? '1';
      _cardResellFeeController.text =
          (feeSettings['cardResellPercent'] as num?)?.toString() ?? '1';
      _cardPrintRequestFeeController.text =
          (feeSettings['cardPrintRequestPercent'] as num?)?.toString() ?? '1';
      _withdrawFeeController.text =
          (feeSettings['withdrawPercent'] as num?)?.toString() ?? '1';
      _standardCardIssueCostController.text =
          (feeSettings['standardCardIssueCost'] as num?)?.toString() ?? '0';
      _deliveryCardIssueCostController.text =
          (feeSettings['deliveryCardIssueCost'] as num?)?.toString() ?? '0';
      _privateCardIssueCostController.text =
          (feeSettings['privateCardIssueCost'] as num?)?.toString() ?? '0.01';
      _singleUseTicketIssueCostController.text =
          (feeSettings['singleUseTicketIssueCost'] as num?)?.toString() ??
          '0.02';
      _appointmentTicketIssueCostController.text =
          (feeSettings['appointmentTicketIssueCost'] as num?)?.toString() ??
          '0.25';
      _queueTicketIssueCostController.text =
          (feeSettings['queueTicketIssueCost'] as num?)?.toString() ?? '0.10';
      _scanDefaultLimitController.text =
          (cardScanLimitSettings['defaultLimit'] as num?)?.toString() ?? '30';
      _scanRestrictedLimitController.text =
          (cardScanLimitSettings['restrictedLimit'] as num?)?.toString() ??
          '10';
      _scanBasicLimitController.text =
          (cardScanLimitSettings['basicLimit'] as num?)?.toString() ?? '30';
      _scanVerifiedLimitController.text =
          (cardScanLimitSettings['verifiedLimit'] as num?)?.toString() ?? '60';
      _scanDriverLimitController.text =
          (cardScanLimitSettings['driverLimit'] as num?)?.toString() ?? '200';
      _scanMarketerLimitController.text =
          (cardScanLimitSettings['marketerLimit'] as num?)?.toString() ?? '40';
      _scanSupportLimitController.text =
          (cardScanLimitSettings['supportLimit'] as num?)?.toString() ?? '0';
      _scanFinanceLimitController.text =
          (cardScanLimitSettings['financeLimit'] as num?)?.toString() ?? '0';
      _scanAdminLimitController.text =
          (cardScanLimitSettings['adminLimit'] as num?)?.toString() ?? '0';
      _scanAutoRedeemGlobalForced =
          cardScanLimitSettings['autoRedeemGlobalForced'] == true;
      _offlineMaxPendingAmountController.text =
          (offlineCardSettings['maxPendingAmount'] as num?)?.toString() ??
          '500';
      _offlineMaxPendingCountController.text =
          (offlineCardSettings['maxPendingCount'] as num?)?.toString() ?? '50';
      _offlineCacheLimitController.text =
          (offlineCardSettings['maxCachedCards'] as num?)?.toString() ?? '1000';
      _offlineSyncIntervalController.text =
          (offlineCardSettings['syncIntervalMinutes'] as num?)?.toString() ??
          '60';
      _prepaidMaxCardAmountController.text =
          (prepaidMultipaySettings['maxCardAmount'] as num?)?.toString() ??
          '500';
      _prepaidMaxPaymentAmountController.text =
          (prepaidMultipaySettings['maxPaymentAmount'] as num?)?.toString() ??
          '250';
      _prepaidMaxActiveCardsController.text =
          (prepaidMultipaySettings['maxActiveCards'] as num?)?.toString() ??
          '5';
      _prepaidMaxExpiryDaysController.text =
          (prepaidMultipaySettings['maxExpiryDays'] as num?)?.toString() ??
          '365';
      _prepaidDailyAmountLimitController.text =
          (prepaidMultipaySettings['dailyPaymentAmountLimit'] as num?)
              ?.toString() ??
          '500';
      _prepaidDailyCountLimitController.text =
          (prepaidMultipaySettings['dailyPaymentCountLimit'] as num?)
              ?.toString() ??
          '20';
      _topupRequestEnabled = topupRequestSettings['enabled'] == true;
      _topupRequestInstructionsController.text =
          topupRequestSettings['instructions']?.toString() ?? '';
      _topupMinAmountController.text =
          (topupRequestSettings['minAmount'] as num?)?.toString() ?? '10';
      _topupMaxAmountController.text =
          (topupRequestSettings['maxAmount'] as num?)?.toString() ?? '10000';
      _withdrawalRequestEnabled = withdrawalRequestSettings['enabled'] == true;
      _withdrawalRequestInstructionsController.text =
          withdrawalRequestSettings['instructions']?.toString() ?? '';
      _withdrawalMinAmountController.text =
          (withdrawalRequestSettings['minAmount'] as num?)?.toString() ?? '100';
      _withdrawalMaxAmountController.text =
          (withdrawalRequestSettings['maxAmount'] as num?)?.toString() ??
          '10000';
      _cardQtyDefaultController.text =
          (cardQuantityLimitSettings['defaultLimit'] as num?)?.toString() ??
          '1';
      _cardQtyRestrictedController.text =
          (cardQuantityLimitSettings['restrictedLimit'] as num?)?.toString() ??
          '1';
      _cardQtyBasicController.text =
          (cardQuantityLimitSettings['basicLimit'] as num?)?.toString() ?? '30';
      _cardQtyVerifiedController.text =
          (cardQuantityLimitSettings['verifiedLimit'] as num?)?.toString() ??
          '30';
      _cardQtyDriverController.text =
          (cardQuantityLimitSettings['driverLimit'] as num?)?.toString() ??
          '30';
      _cardQtyMarketerController.text =
          (cardQuantityLimitSettings['marketerLimit'] as num?)?.toString() ??
          '10';
      _cardQtySupportController.text =
          (cardQuantityLimitSettings['supportLimit'] as num?)?.toString() ??
          '1';
      _cardQtyFinanceController.text =
          (cardQuantityLimitSettings['financeLimit'] as num?)?.toString() ??
          '1';
      _cardQtyAdminController.text =
          (cardQuantityLimitSettings['adminLimit'] as num?)?.toString() ?? '1';
      _affiliateEnabled = affiliateSettings['enabled'] == true;
      _affiliateRewardAmountController.text =
          (affiliateSettings['rewardAmount'] as num?)?.toString() ?? '5';
      _affiliateFirstTopupMinAmountController.text =
          (affiliateSettings['firstTopupMinAmount'] as num?)?.toString() ??
          '100';
      _affiliateMarketerDebtLimitController.text =
          (affiliateSettings['marketerDebtLimit'] as num?)?.toString() ?? '50';
      _policyTitleController.text = usagePolicy['title'] ?? '';
      _policyContentController.text = usagePolicy['content'] ?? '';

      setState(() {
        _isAuthorized = true;
        _topupPaymentMethods = topupPaymentMethods;
        _withdrawalMethods = withdrawalMethods;
        _isLoading = false;
      });
      unawaited(_loadPrepaidReport());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_system_settings_screen.066'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _loadPrepaidReport() async {
    if (!_isAuthorized) {
      return;
    }
    setState(() => _isLoadingPrepaidReport = true);
    try {
      final payload = await _apiService.getAdminPrepaidMultipayPayments(
        buyerUserId: _prepaidReportBuyerIdController.text,
        merchantUserId: _prepaidReportMerchantIdController.text,
        dateFrom: _prepaidReportDateFromController.text,
        dateTo: _prepaidReportDateToController.text,
        query: _prepaidReportSearchController.text,
        cardStatus: _prepaidReportCardStatus,
        perPage: 50,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _prepaidReportPayments = List<Map<String, dynamic>>.from(
          (payload['payments'] as List? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _prepaidReportSummary = Map<String, dynamic>.from(
          payload['summary'] as Map? ?? const {},
        );
        _isLoadingPrepaidReport = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingPrepaidReport = false);
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_system_settings_screen.125'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _exportPrepaidReport() async {
    if (_prepaidReportPayments.isEmpty) {
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_system_settings_screen.126'),
        message: context.loc.tr('screens_admin_system_settings_screen.127'),
      );
      return;
    }

    try {
      await _apiService.exportAdminPrepaidMultipayPaymentsCsv(
        payments: _prepaidReportPayments,
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: context.loc.tr('screens_admin_system_settings_screen.128'),
        message: context.loc.tr('screens_admin_system_settings_screen.129'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: context.loc.tr('screens_admin_system_settings_screen.130'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _save() async {
    final l = context.loc;
    setState(() => _isSaving = true);
    try {
      await Future.wait([
        _apiService.updateContactInfo(
          title: _contactTitleController.text,
          supportWhatsapp: _contactWhatsappController.text,
          supportEmail: _contactEmailController.text,
          address: _contactAddressController.text,
        ),
        _apiService.updateAuthSettings(
          registrationEnabled: _registrationEnabled,
          loginOtpRequired: _loginOtpRequired,
          registrationWhatsappVerificationRequired:
              _registrationWhatsappVerificationRequired,
          whatsappUsageMode: _whatsappUsageMode,
          messageDeliveryPriority: _messageDeliveryPriority,
          minSupportedVersion: _minSupportedVersionController.text,
          latestVersion: _latestVersionController.text,
          androidStoreUrl: _androidStoreUrlController.text,
          iosStoreUrl: _iosStoreUrlController.text,
          webStoreUrl: _webStoreUrlController.text,
        ),
        _apiService.updateTransferSettings(
          unverifiedTransferLimit:
              double.tryParse(_unverifiedTransferLimitController.text) ?? 200,
        ),
        _apiService.updateFeeSettings(
          walletTopupPercent:
              double.tryParse(_walletTopupFeeController.text) ?? 1,
          walletTransferPercent:
              double.tryParse(_walletTransferFeeController.text) ?? 1,
          cardRedeemPercent:
              double.tryParse(_cardRedeemFeeController.text) ?? 1,
          cardResellPercent:
              double.tryParse(_cardResellFeeController.text) ?? 1,
          cardPrintRequestPercent:
              double.tryParse(_cardPrintRequestFeeController.text) ?? 1,
          withdrawPercent: double.tryParse(_withdrawFeeController.text) ?? 1,
          standardCardIssueCost:
              double.tryParse(_standardCardIssueCostController.text) ?? 0,
          deliveryCardIssueCost:
              double.tryParse(_deliveryCardIssueCostController.text) ?? 0,
          privateCardIssueCost:
              double.tryParse(_privateCardIssueCostController.text) ?? 0.01,
          singleUseTicketIssueCost:
              double.tryParse(_singleUseTicketIssueCostController.text) ?? 0.02,
          appointmentTicketIssueCost:
              double.tryParse(_appointmentTicketIssueCostController.text) ??
              0.25,
          queueTicketIssueCost:
              double.tryParse(_queueTicketIssueCostController.text) ?? 0.10,
        ),
        _apiService.updateCardScanLimitSettings(
          defaultLimit: int.tryParse(_scanDefaultLimitController.text) ?? 30,
          restrictedLimit:
              int.tryParse(_scanRestrictedLimitController.text) ?? 10,
          basicLimit: int.tryParse(_scanBasicLimitController.text) ?? 30,
          verifiedLimit: int.tryParse(_scanVerifiedLimitController.text) ?? 60,
          driverLimit: int.tryParse(_scanDriverLimitController.text) ?? 200,
          marketerLimit: int.tryParse(_scanMarketerLimitController.text) ?? 40,
          supportLimit: int.tryParse(_scanSupportLimitController.text) ?? 0,
          financeLimit: int.tryParse(_scanFinanceLimitController.text) ?? 0,
          adminLimit: int.tryParse(_scanAdminLimitController.text) ?? 0,
          autoRedeemGlobalForced: _scanAutoRedeemGlobalForced,
        ),
        _apiService.updateAdminOfflineCardSettings(
          maxPendingAmount:
              double.tryParse(_offlineMaxPendingAmountController.text) ?? 500,
          maxPendingCount:
              int.tryParse(_offlineMaxPendingCountController.text) ?? 50,
          maxCachedCards:
              int.tryParse(_offlineCacheLimitController.text) ?? 1000,
          syncIntervalMinutes:
              int.tryParse(_offlineSyncIntervalController.text) ?? 60,
        ),
        _apiService.updateAdminPrepaidMultipaySettings(
          maxCardAmount:
              double.tryParse(_prepaidMaxCardAmountController.text) ?? 500,
          maxPaymentAmount:
              double.tryParse(_prepaidMaxPaymentAmountController.text) ?? 250,
          maxActiveCards:
              int.tryParse(_prepaidMaxActiveCardsController.text) ?? 5,
          maxExpiryDays:
              int.tryParse(_prepaidMaxExpiryDaysController.text) ?? 365,
          dailyPaymentAmountLimit:
              double.tryParse(_prepaidDailyAmountLimitController.text) ?? 500,
          dailyPaymentCountLimit:
              int.tryParse(_prepaidDailyCountLimitController.text) ?? 20,
        ),
        _apiService.updateAdminTopupRequestSettings(
          enabled: _topupRequestEnabled,
          instructions: _topupRequestInstructionsController.text,
          minAmount: double.tryParse(_topupMinAmountController.text) ?? 10,
          maxAmount: double.tryParse(_topupMaxAmountController.text) ?? 10000,
        ),
        _apiService.updateAdminWithdrawalRequestSettings(
          enabled: _withdrawalRequestEnabled,
          instructions: _withdrawalRequestInstructionsController.text,
          minAmount:
              double.tryParse(_withdrawalMinAmountController.text) ?? 100,
          maxAmount:
              double.tryParse(_withdrawalMaxAmountController.text) ?? 10000,
        ),
        _apiService.updateCardQuantityLimitSettings(
          defaultLimit: int.tryParse(_cardQtyDefaultController.text) ?? 1,
          restrictedLimit: int.tryParse(_cardQtyRestrictedController.text) ?? 1,
          basicLimit: int.tryParse(_cardQtyBasicController.text) ?? 30,
          verifiedLimit: int.tryParse(_cardQtyVerifiedController.text) ?? 30,
          driverLimit: int.tryParse(_cardQtyDriverController.text) ?? 30,
          marketerLimit: int.tryParse(_cardQtyMarketerController.text) ?? 10,
          supportLimit: int.tryParse(_cardQtySupportController.text) ?? 1,
          financeLimit: int.tryParse(_cardQtyFinanceController.text) ?? 1,
          adminLimit: int.tryParse(_cardQtyAdminController.text) ?? 1,
        ),
        _apiService.updateAffiliateSettings(
          enabled: _affiliateEnabled,
          rewardAmount:
              double.tryParse(_affiliateRewardAmountController.text) ?? 5,
          firstTopupMinAmount:
              double.tryParse(_affiliateFirstTopupMinAmountController.text) ??
              100,
          marketerDebtLimit:
              double.tryParse(_affiliateMarketerDebtLimitController.text) ?? 50,
        ),
        _apiService.updateUsagePolicy(
          title: _policyTitleController.text,
          content: _policyContentController.text,
        ),
      ]);
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_admin_system_settings_screen.001'),
        message: l.tr('screens_admin_system_settings_screen.035'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_system_settings_screen.002'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showTopupMethodDialog({Map<String, dynamic>? method}) async {
    final l = context.loc;
    final titleController = TextEditingController(
      text: method?['title']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: method?['description']?.toString() ?? '',
    );
    final imageUrlController = TextEditingController(
      text: method?['imageUrl']?.toString() ?? '',
    );
    final accountNumberController = TextEditingController(
      text: method?['accountNumber']?.toString() ?? '',
    );
    final sortOrderController = TextEditingController(
      text: (method?['sortOrder'] ?? 0).toString(),
    );
    var isActive = method?['isActive'] != false;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (titleController.text.trim().isEmpty ||
                accountNumberController.text.trim().isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_system_settings_screen.003'),
                message: l.tr('screens_admin_system_settings_screen.036'),
              );
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              final methods = await _apiService.saveAdminTopupPaymentMethod(
                methodId: method?['id']?.toString(),
                title: titleController.text,
                description: descriptionController.text,
                imageUrl: imageUrlController.text,
                accountNumber: accountNumberController.text,
                isActive: isActive,
                sortOrder: int.tryParse(sortOrderController.text) ?? 0,
              );
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!mounted) {
                return;
              }
              setState(() => _topupPaymentMethods = methods);
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_system_settings_screen.004'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(
              method == null
                  ? l.tr('screens_admin_system_settings_screen.005')
                  : l.tr('screens_admin_system_settings_screen.006'),
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.007',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountNumberController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.037',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: imageUrlController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.008',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sortOrderController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.009',
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.010',
                        ),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      title: Text(
                        l.tr('screens_admin_system_settings_screen.011'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_admin_system_settings_screen.012')),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(
                  isSaving
                      ? l.tr('screens_admin_system_settings_screen.013')
                      : l.tr('screens_admin_system_settings_screen.014'),
                ),
              ),
            ],
          );
        },
      ),
    );

    titleController.dispose();
    descriptionController.dispose();
    imageUrlController.dispose();
    accountNumberController.dispose();
    sortOrderController.dispose();
  }

  Future<void> _deleteTopupMethod(Map<String, dynamic> method) async {
    final l = context.loc;
    final methodId = method['id']?.toString().trim() ?? '';
    if (methodId.isEmpty) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_system_settings_screen.015'),
        message: 'تعذر تحديد طريقة الشحن المطلوبة.',
      );
      return;
    }

    try {
      final methods = await _apiService.deleteAdminTopupPaymentMethod(methodId);
      if (!mounted) {
        return;
      }
      setState(() => _topupPaymentMethods = methods);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_admin_system_settings_screen.015'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _showWithdrawalMethodDialog({
    Map<String, dynamic>? method,
  }) async {
    final l = context.loc;
    final codeController = TextEditingController(
      text: method?['code']?.toString() ?? '',
    );
    final titleController = TextEditingController(
      text: method?['title']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: method?['description']?.toString() ?? '',
    );
    final accountLabelController = TextEditingController(
      text: method?['accountLabel']?.toString() ?? 'رقم الحساب أو المحفظة',
    );
    final sortOrderController = TextEditingController(
      text: (method?['sortOrder'] ?? 0).toString(),
    );
    var requiresBankName = method?['requiresBankName'] == true;
    var isActive = method?['isActive'] != false;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (codeController.text.trim().isEmpty ||
                titleController.text.trim().isEmpty ||
                accountLabelController.text.trim().isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_system_settings_screen.131'),
                message: l.tr('screens_admin_system_settings_screen.132'),
              );
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              final methods = await _apiService.saveAdminWithdrawalMethod(
                methodId: method?['id']?.toString(),
                code: codeController.text,
                title: titleController.text,
                description: descriptionController.text,
                accountLabel: accountLabelController.text,
                requiresBankName: requiresBankName,
                isActive: isActive,
                sortOrder: int.tryParse(sortOrderController.text) ?? 0,
              );
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!mounted) {
                return;
              }
              setState(() => _withdrawalMethods = methods);
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.tr('screens_admin_system_settings_screen.133'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(
              method == null
                  ? l.tr('screens_admin_system_settings_screen.134')
                  : l.tr('screens_admin_system_settings_screen.135'),
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: codeController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.136',
                        ),
                        helperText: l.tr(
                          'screens_admin_system_settings_screen.137',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.138',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountLabelController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.139',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sortOrderController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.140',
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: l.tr(
                          'screens_admin_system_settings_screen.141',
                        ),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: requiresBankName,
                      onChanged: (value) =>
                          setDialogState(() => requiresBankName = value),
                      title: Text(
                        l.tr('screens_admin_system_settings_screen.142'),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      title: Text(
                        l.tr('screens_admin_system_settings_screen.143'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_admin_system_settings_screen.012')),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(
                  isSaving
                      ? l.tr('screens_admin_system_settings_screen.144')
                      : l.tr('screens_admin_system_settings_screen.145'),
                ),
              ),
            ],
          );
        },
      ),
    );

    codeController.dispose();
    titleController.dispose();
    descriptionController.dispose();
    accountLabelController.dispose();
    sortOrderController.dispose();
  }

  Future<void> _deleteWithdrawalMethod(Map<String, dynamic> method) async {
    final methodId = method['id']?.toString().trim() ?? '';
    if (methodId.isEmpty) {
      await AppAlertService.showError(
        context,
        title: 'تعذر الحذف',
        message: 'تعذر تحديد طريقة السحب المطلوبة.',
      );
      return;
    }

    try {
      final methods = await _apiService.deleteAdminWithdrawalMethod(methodId);
      if (!mounted) {
        return;
      }
      setState(() => _withdrawalMethods = methods);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: 'تعذر الحذف',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const AppSidebar(),
        body: Center(
          child: ShwakelCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 54,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(height: 14),
                Text(
                  l.tr('screens_admin_system_settings_screen.058'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 8,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const AppSidebar(),
        body: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShwakelCard(
                padding: const EdgeInsets.all(28),
                gradient: AppTheme.primaryGradient,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.tr('screens_admin_system_settings_screen.017'),
                      style: AppTheme.h2.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.tr('screens_admin_system_settings_screen.038'),
                      style: AppTheme.bodyAction.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ShwakelCard(
                padding: const EdgeInsets.all(10),
                borderRadius: BorderRadius.circular(24),
                shadowLevel: ShwakelShadowLevel.soft,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(4),
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.support_agent_rounded),
                      text: l.tr('screens_admin_system_settings_screen.053'),
                    ),
                    Tab(
                      icon: const Icon(Icons.system_update_rounded),
                      text: l.tr('screens_admin_system_settings_screen.054'),
                    ),
                    Tab(
                      icon: const Icon(Icons.add_card_rounded),
                      text: l.tr('screens_admin_system_settings_screen.055'),
                    ),
                    Tab(
                      icon: const Icon(Icons.cloud_off_rounded),
                      text: l.tr('screens_admin_system_settings_screen.075'),
                    ),
                    const Tab(
                      icon: Icon(Icons.credit_card_rounded),
                      text: 'بطاقات الدفع',
                    ),
                    Tab(
                      icon: Icon(Icons.campaign_rounded),
                      text: l.tr('screens_admin_system_settings_screen.066'),
                    ),
                    Tab(
                      icon: const Icon(Icons.policy_rounded),
                      text: l.tr('screens_admin_system_settings_screen.056'),
                    ),
                    Tab(
                      icon: const Icon(Icons.percent_rounded),
                      text: l.tr('screens_admin_system_settings_screen.057'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildContactTab(),
                    _buildAppTab(),
                    _buildTopupTab(),
                    _buildOfflineCardsTab(),
                    _buildPrepaidMultipayTab(),
                    _buildAffiliateTab(),
                    _buildPolicyTab(),
                    _buildFeesTab(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ShwakelButton(
                label: l.tr('screens_admin_system_settings_screen.034'),
                icon: Icons.save_rounded,
                onPressed: _save,
                isLoading: _isSaving,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return ShwakelCard(padding: const EdgeInsets.all(20), child: child);
  }

  String _normalizeWhatsappUsageMode(Object? value) {
    final mode = value?.toString().trim().toLowerCase();
    if (mode == 'registration' || mode == 'financial' || mode == 'all') {
      return mode!;
    }
    return 'all';
  }

  String _normalizeMessageDeliveryPriority(Object? value) {
    final priority = value?.toString().trim().toLowerCase();
    if (priority == 'whatsapp' || priority == 'sms') {
      return priority!;
    }
    return 'whatsapp';
  }

  Widget _buildContactTab() {
    final l = context.loc;
    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: l.tr('screens_admin_system_settings_screen.018'),
            subtitle: l.tr('screens_admin_system_settings_screen.061'),
            icon: Icons.support_agent_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              children: [
                TextField(
                  controller: _contactTitleController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.019'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contactWhatsappController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.020'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contactEmailController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.021'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contactAddressController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.022'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppTab() {
    final l = context.loc;
    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: l.tr('screens_admin_system_settings_screen.040'),
            subtitle: l.tr('screens_admin_system_settings_screen.062'),
            icon: Icons.tune_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _registrationEnabled,
                  onChanged: (value) =>
                      setState(() => _registrationEnabled = value),
                  title: Text(l.tr('screens_admin_system_settings_screen.042')),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _loginOtpRequired,
                  onChanged: (value) =>
                      setState(() => _loginOtpRequired = value),
                  title: Text(
                    l.tr('screens_admin_system_settings_screen.146'),
                  ),
                  subtitle: Text(
                    l.tr('screens_admin_system_settings_screen.147'),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _registrationWhatsappVerificationRequired,
                  onChanged: null,
                  title: Text(
                    l.tr('screens_admin_system_settings_screen.148'),
                  ),
                  subtitle: Text(
                    l.tr('screens_admin_system_settings_screen.149'),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _whatsappUsageMode,
                  decoration: InputDecoration(
                    labelText: l.tr(
                      'screens_admin_system_settings_screen.150',
                    ),
                    helperText: l.tr(
                      'screens_admin_system_settings_screen.151',
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'registration',
                      child: Text(
                        l.tr('screens_admin_system_settings_screen.152'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'financial',
                      child: Text(
                        l.tr('screens_admin_system_settings_screen.153'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'all',
                      child: Text(
                        l.tr('screens_admin_system_settings_screen.154'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () =>
                        _whatsappUsageMode = _normalizeWhatsappUsageMode(value),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _messageDeliveryPriority,
                  decoration: const InputDecoration(
                    labelText: 'أولوية إرسال الرسائل',
                    helperText:
                        'القناة الأولى للرسائل، ويتم استخدام القناة الأخرى تلقائيًا عند الفشل.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'whatsapp',
                      child: Text('واتساب ثم SMS'),
                    ),
                    DropdownMenuItem(
                      value: 'sms',
                      child: Text('SMS ثم واتساب'),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _messageDeliveryPriority =
                        _normalizeMessageDeliveryPriority(value),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _unverifiedTransferLimitController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.043'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _minSupportedVersionController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.044'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _latestVersionController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.045'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _androidStoreUrlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.051'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _iosStoreUrlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.052'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _webStoreUrlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.059'),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l.tr('screens_admin_system_settings_screen.060'),
                    style: AppTheme.caption,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopupTab() {
    final l = context.loc;
    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: l.tr('screens_admin_system_settings_screen.024'),
            subtitle: l.tr('screens_admin_system_settings_screen.063'),
            icon: Icons.add_card_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _topupRequestEnabled,
                  onChanged: (value) =>
                      setState(() => _topupRequestEnabled = value),
                  title: Text(l.tr('screens_admin_system_settings_screen.047')),
                ),
                TextField(
                  controller: _topupRequestInstructionsController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.048'),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildNumberField(
                      'الحد الأدنى لطلب الشحن',
                      _topupMinAmountController,
                      decimal: true,
                    ),
                    _buildNumberField(
                      'الحد الأعلى لطلب الشحن',
                      _topupMaxAmountController,
                      decimal: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.tr('screens_admin_system_settings_screen.155'),
                        style: AppTheme.bodyBold,
                      ),
                    ),
                    ShwakelButton(
                      label: l.tr('screens_admin_system_settings_screen.025'),
                      icon: Icons.playlist_add_rounded,
                      onPressed: _showTopupMethodDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_topupPaymentMethods.isEmpty)
                  Text(
                    l.tr('screens_admin_system_settings_screen.049'),
                    style: AppTheme.bodyAction,
                  )
                else
                  ..._topupPaymentMethods.map(
                    (method) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    method['title']?.toString() ?? '-',
                                    style: AppTheme.bodyBold,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    method['accountNumber']?.toString() ?? '-',
                                    style: AppTheme.bodyAction,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _showTopupMethodDialog(method: method),
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            IconButton(
                              onPressed: () => _deleteTopupMethod(method),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.tr('screens_admin_system_settings_screen.156'),
                        style: AppTheme.bodyBold,
                      ),
                    ),
                    ShwakelButton(
                      label: l.tr('screens_admin_system_settings_screen.134'),
                      icon: Icons.playlist_add_rounded,
                      onPressed: _showWithdrawalMethodDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _withdrawalRequestEnabled,
                  onChanged: (value) =>
                      setState(() => _withdrawalRequestEnabled = value),
                  title: Text(
                    l.tr('screens_admin_system_settings_screen.157'),
                  ),
                ),
                TextField(
                  controller: _withdrawalRequestInstructionsController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: l.tr(
                      'screens_admin_system_settings_screen.158',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.159'),
                      _withdrawalMinAmountController,
                      decimal: true,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.160'),
                      _withdrawalMaxAmountController,
                      decimal: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_withdrawalMethods.isEmpty)
                  Text(
                    l.tr('screens_admin_system_settings_screen.161'),
                    style: AppTheme.bodyAction,
                  )
                else
                  ..._withdrawalMethods.map(
                    (method) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    method['title']?.toString() ?? '-',
                                    style: AppTheme.bodyBold,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${method['code']} | ${method['accountLabel']}',
                                    style: AppTheme.bodyAction,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  _showWithdrawalMethodDialog(method: method),
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            IconButton(
                              onPressed: () => _deleteWithdrawalMethod(method),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_admin_system_settings_screen.173'),
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('screens_admin_system_settings_screen.174'),
                  style: AppTheme.bodyAction,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.175'),
                      _cardQtyDefaultController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.176'),
                      _cardQtyRestrictedController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.177'),
                      _cardQtyBasicController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.178'),
                      _cardQtyVerifiedController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.179'),
                      _cardQtyDriverController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.180'),
                      _cardQtyMarketerController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.181'),
                      _cardQtySupportController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.182'),
                      _cardQtyFinanceController,
                    ),
                    _buildNumberField(
                      l.tr('screens_admin_system_settings_screen.183'),
                      _cardQtyAdminController,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineCardsTab() {
    final l = context.loc;
    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: l.tr('screens_admin_system_settings_screen.075'),
            subtitle: l.tr('screens_admin_system_settings_screen.076'),
            icon: Icons.cloud_off_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildNumberField(
                  l.tr('screens_admin_system_settings_screen.077'),
                  _offlineSyncIntervalController,
                  suffixText: l.tr('screens_admin_system_settings_screen.081'),
                ),
                _buildNumberField(
                  l.tr('screens_admin_system_settings_screen.078'),
                  _offlineCacheLimitController,
                ),
                _buildNumberField(
                  l.tr('screens_admin_system_settings_screen.079'),
                  _offlineMaxPendingCountController,
                ),
                _buildNumberField(
                  l.tr('screens_admin_system_settings_screen.080'),
                  _offlineMaxPendingAmountController,
                  decimal: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrepaidMultipayTab() {
    final reportCount = (_prepaidReportSummary['count'] as num?)?.toInt() ?? 0;
    final reportTotal =
        (_prepaidReportSummary['totalAmount'] as num?)?.toDouble() ?? 0;

    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: context.loc.tr('screens_admin_system_settings_screen.184'),
            subtitle:
                context.loc.tr('screens_admin_system_settings_screen.185'),
            icon: Icons.credit_card_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildNumberField(
                  context.loc.tr('screens_admin_system_settings_screen.186'),
                  _prepaidMaxCardAmountController,
                  decimal: true,
                ),
                _buildNumberField(
                  context.loc.tr('screens_admin_system_settings_screen.187'),
                  _prepaidMaxPaymentAmountController,
                  decimal: true,
                ),
                _buildNumberField(
                  context.loc.tr('screens_admin_system_settings_screen.188'),
                  _prepaidMaxActiveCardsController,
                ),
                _buildNumberField(
                  context.loc.tr('screens_admin_system_settings_screen.189'),
                  _prepaidMaxExpiryDaysController,
                ),
                _buildNumberField(
                  context.loc.tr('screens_admin_system_settings_screen.190'),
                  _prepaidDailyAmountLimitController,
                  decimal: true,
                ),
                _buildNumberField(
                  context.loc.tr('screens_admin_system_settings_screen.191'),
                  _prepaidDailyCountLimitController,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AdminSectionHeader(
            title: context.loc.tr('screens_admin_system_settings_screen.162'),
            subtitle:
                context.loc.tr('screens_admin_system_settings_screen.163'),
            icon: Icons.receipt_long_rounded,
            trailing: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoadingPrepaidReport
                      ? null
                      : _loadPrepaidReport,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                    context.loc.tr('screens_admin_system_settings_screen.164'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoadingPrepaidReport
                      ? null
                      : _exportPrepaidReport,
                  icon: const Icon(Icons.file_download_rounded),
                  label: const Text('CSV'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildTextField(
                      context.loc.tr(
                        'screens_admin_system_settings_screen.165',
                      ),
                      _prepaidReportSearchController,
                      hintText: context.loc.tr(
                        'screens_admin_system_settings_screen.166',
                      ),
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.192'),
                      _prepaidReportBuyerIdController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.193'),
                      _prepaidReportMerchantIdController,
                    ),
                    _buildTextField(
                      context.loc.tr('screens_admin_system_settings_screen.194'),
                      _prepaidReportDateFromController,
                      hintText: '2026-04-26',
                    ),
                    _buildTextField(
                      context.loc.tr('screens_admin_system_settings_screen.195'),
                      _prepaidReportDateToController,
                      hintText: '2026-04-26',
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: _prepaidReportCardStatus,
                        decoration: InputDecoration(
                          labelText: context.loc.tr(
                            'screens_admin_system_settings_screen.167',
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(
                              context.loc.tr(
                                'screens_admin_system_settings_screen.168',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text(
                              context.loc.tr(
                                'screens_admin_system_settings_screen.196',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'frozen',
                            child: Text(
                              context.loc.tr(
                                'screens_admin_system_settings_screen.197',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'spent',
                            child: Text(
                              context.loc.tr(
                                'screens_admin_system_settings_screen.198',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'expired',
                            child: Text(
                              context.loc.tr(
                                'screens_admin_system_settings_screen.199',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'cancelled',
                            child: Text(
                              context.loc.tr(
                                'screens_admin_system_settings_screen.200',
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _prepaidReportCardStatus = value ?? 'all',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _reportPill(
                      Icons.format_list_numbered_rounded,
                      'عدد العمليات',
                      '$reportCount',
                    ),
                    _reportPill(
                      Icons.payments_rounded,
                      'الإجمالي',
                      CurrencyFormatter.ils(reportTotal),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_isLoadingPrepaidReport)
                  const Center(child: CircularProgressIndicator())
                else if (_prepaidReportPayments.isEmpty)
                  Text(
                    'لا توجد مدفوعات مطابقة للفلاتر الحالية.',
                    style: AppTheme.bodyAction,
                  )
                else
                  ..._prepaidReportPayments.map(
                    (payment) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildPrepaidReportRow(payment),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportPill(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text('$label: $value', style: AppTheme.caption),
        ],
      ),
    );
  }

  Widget _buildPrepaidReportRow(Map<String, dynamic> payment) {
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
    final buyer = payment['buyerUsername']?.toString() ?? '-';
    final merchant = payment['merchantUsername']?.toString() ?? '-';
    final note = payment['note']?.toString() ?? '';
    final createdAt = payment['createdAt']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$buyer ← $merchant', style: AppTheme.bodyBold),
                const SizedBox(height: 4),
                Text(
                  note.isEmpty ? createdAt : '$note · $createdAt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.ils(amount),
            style: AppTheme.bodyBold.copyWith(color: AppTheme.success),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyTab() {
    final l = context.loc;
    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: l.tr('screens_admin_system_settings_screen.026'),
            subtitle: l.tr('screens_admin_system_settings_screen.064'),
            icon: Icons.policy_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              children: [
                TextField(
                  controller: _policyTitleController,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.027'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _policyContentController,
                  minLines: 4,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: l.tr('screens_admin_system_settings_screen.028'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAffiliateTab() {
    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: context.loc.tr('screens_admin_system_settings_screen.067'),
            subtitle: context.loc.tr(
              'screens_admin_system_settings_screen.068',
            ),
            icon: Icons.campaign_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _affiliateEnabled,
                  onChanged: (value) =>
                      setState(() => _affiliateEnabled = value),
                  title: Text(
                    context.loc.tr('screens_admin_system_settings_screen.069'),
                  ),
                  subtitle: Text(
                    context.loc.tr('screens_admin_system_settings_screen.070'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _affiliateRewardAmountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.loc.tr(
                      'screens_admin_system_settings_screen.071',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _affiliateFirstTopupMinAmountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.loc.tr(
                      'screens_admin_system_settings_screen.072',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _affiliateMarketerDebtLimitController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.loc.tr(
                      'screens_admin_system_settings_screen.073',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.loc.tr('screens_admin_system_settings_screen.074'),
                    style: AppTheme.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeesTab() {
    final l = context.loc;
    return _tabScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: l.tr('screens_admin_system_settings_screen.057'),
            subtitle: l.tr('screens_admin_system_settings_screen.065'),
            icon: Icons.percent_rounded,
          ),
          const SizedBox(height: 16),
          _card(
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildFeeField(
                  l.tr('screens_admin_system_settings_screen.029'),
                  _walletTopupFeeController,
                ),
                _buildFeeField(
                  l.tr('screens_admin_system_settings_screen.030'),
                  _walletTransferFeeController,
                ),
                _buildFeeField(
                  l.tr('screens_admin_system_settings_screen.031'),
                  _cardRedeemFeeController,
                ),
                _buildFeeField(
                  l.tr('screens_admin_system_settings_screen.032'),
                  _cardResellFeeController,
                ),
                _buildFeeField(
                  l.tr('screens_admin_system_settings_screen.033'),
                  _cardPrintRequestFeeController,
                ),
                _buildFeeField('رسوم السحب', _withdrawFeeController),
                _buildFeeField(
                  'رسوم بطاقة رصيد عند الاستخدام',
                  _standardCardIssueCostController,
                ),
                _buildFeeField(
                  'رسوم بطاقة توصيل عند الاستخدام',
                  _deliveryCardIssueCostController,
                ),
                _buildFeeField(
                  'رسوم البطاقة الخاصة عند الإنشاء',
                  _privateCardIssueCostController,
                ),
                _buildFeeField(
                  'رسوم إصدار بطاقة خاصة لاستخدام واحد',
                  _singleUseTicketIssueCostController,
                ),
                _buildFeeField(
                  'رسوم إصدار تذكرة موعد',
                  _appointmentTicketIssueCostController,
                ),
                _buildFeeField(
                  'رسوم إصدار تذكرة طابور',
                  _queueTicketIssueCostController,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.loc.tr('screens_admin_system_settings_screen.169'),
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 8),
                Text(
                  context.loc.tr(
                    'screens_admin_system_settings_screen.170',
                  ),
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.201'),
                      _scanDefaultLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.202'),
                      _scanRestrictedLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.177'),
                      _scanBasicLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.203'),
                      _scanVerifiedLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.179'),
                      _scanDriverLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.180'),
                      _scanMarketerLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.204'),
                      _scanSupportLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.182'),
                      _scanFinanceLimitController,
                    ),
                    _buildNumberField(
                      context.loc.tr('screens_admin_system_settings_screen.183'),
                      _scanAdminLimitController,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.loc.tr(
                        'screens_admin_system_settings_screen.171',
                      ),
                    ),
                  subtitle: Text(
                    context.loc.tr(
                      'screens_admin_system_settings_screen.172',
                    ),
                  ),
                  value: _scanAutoRedeemGlobalForced,
                  onChanged: (value) =>
                      setState(() => _scanAutoRedeemGlobalForced = value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabScroll({required Widget child}) {
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
      ),
    );
  }

  Widget _buildFeeField(
    String label,
    TextEditingController controller, {
    String suffixText = '%',
  }) {
    return SizedBox(
      width: 190,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: suffixText),
      ),
    );
  }

  Widget _buildNumberField(
    String label,
    TextEditingController controller, {
    String? suffixText,
    bool decimal = false,
  }) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, suffixText: suffixText),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hintText,
  }) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hintText),
      ),
    );
  }
}
