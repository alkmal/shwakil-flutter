import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _referralPhoneController =
      TextEditingController();
  final TextEditingController _currentPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmNewPassController =
      TextEditingController();

  bool _isLoading = true;
  bool _isAuthorized = false;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  bool _profileLocked = false;
  Set<String> _editableProfileFields = const <String>{};
  Uint8List? _printLogoPreview;
  String? _printLogoFileName;
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _nationalIdController.dispose();
    _birthDateController.dispose();
    _referralPhoneController.dispose();
    _currentPassController.dispose();
    _newPassController.dispose();
    _confirmNewPassController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = AuthService.peekCurrentUser() ?? await _authService.currentUser();
    if (!mounted) {
      return;
    }
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() {
      _isAuthorized = AppPermissions.fromUser(user).canViewAccountSettings;
      _user = user;
      _fullNameController.text = user['fullName']?.toString() ?? '';
      _usernameController.text = user['username']?.toString() ?? '';
      _whatsappController.text = user['whatsapp']?.toString() ?? '';
      _emailController.text = user['email']?.toString() ?? '';
      _addressController.text = user['address']?.toString() ?? '';
      _nationalIdController.text = user['nationalId']?.toString() ?? '';
      _birthDateController.text = user['birthDate']?.toString() ?? '';
      _referralPhoneController.text = user['referralPhone']?.toString() ?? '';

      final verification =
          user['transferVerificationStatus']?.toString() ?? 'unverified';
      _editableProfileFields = Set<String>.from(
        (user['editableProfileFields'] as List? ?? const []).map(
          (item) => item.toString(),
        ),
      );
      _profileLocked =
          user['profileEditable'] == false ||
          (verification == 'approved' && _editableProfileFields.isEmpty);
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final l = context.loc;
    if (_profileLocked) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final response = await _authService.updateProfile(
        fullName: _fullNameController.text,
        username: _usernameController.text,
        email: _emailController.text,
        address: _addressController.text,
        nationalId: _nationalIdController.text,
        birthDate: _birthDateController.text,
        referralPhone: _referralPhoneController.text,
      );
      final user = Map<String, dynamic>.from(response['user'] as Map);
      if (!mounted) {
        return;
      }
      setState(() {
        _user = user;
        _editableProfileFields = Set<String>.from(
          (user['editableProfileFields'] as List? ?? const []).map(
            (item) => item.toString(),
          ),
        );
        _profileLocked = user['profileEditable'] == false;
      });
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_account_settings_screen.001'),
        message: l.tr('screens_account_settings_screen.039'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.002'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final l = context.loc;
    final current = _currentPassController.text.trim();
    final next = _newPassController.text;
    final confirm = _confirmNewPassController.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.003'),
        message: l.tr('screens_account_settings_screen.040'),
      );
      return;
    }
    if (next != confirm) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.004'),
        message: l.tr('screens_account_settings_screen.041'),
      );
      return;
    }
    if (next.length < 8) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.005'),
        message: l.tr('screens_account_settings_screen.042'),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _authService.changePassword(
        currentPassword: current,
        newPassword: next,
      );
      _currentPassController.clear();
      _newPassController.clear();
      _confirmNewPassController.clear();
      if (!mounted) {
        return;
      }
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_account_settings_screen.006'),
        message: l.tr('screens_account_settings_screen.043'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.007'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.loc.tr('screens_account_settings_screen.056')),
        content: Text(context.loc.tr('screens_account_settings_screen.057')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.loc.tr('screens_account_settings_screen.058')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              context.loc.tr('screens_account_settings_screen.056'),
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _authService.deleteAccount();
      await RealtimeNotificationService.stop();
      await LocalSecurityService.clearTrustedState();
      await LocalSecurityService.clearRelockRequirement();
      await LocalSecurityService.skipNextUnlock();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: context.loc.tr('screens_account_settings_screen.059'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool get _hasPendingProfileCompletion {
    final verification =
        _user?['transferVerificationStatus']?.toString() ?? 'unverified';
    return verification == 'approved' && _editableProfileFields.isNotEmpty;
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
          title: Text(l.tr('screens_account_settings_screen.008')),
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
                  l.tr('screens_account_settings_screen.060'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_user == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_account_settings_screen.008')),
          actions: const [AppNotificationAction(), QuickLogoutAction()],
        ),
        drawer: const AppSidebar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: ResponsiveScaffoldContainer(
              child: ShwakelCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_person_rounded,
                      color: AppTheme.primary,
                      size: 52,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l.tr('screens_account_settings_screen.061'),
                      style: AppTheme.h2,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.tr('screens_account_settings_screen.062'),
                      style: AppTheme.bodyAction.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ShwakelButton(
                      label: l.tr('screens_account_settings_screen.063'),
                      icon: Icons.login_rounded,
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/login', (route) => false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(l.tr('screens_account_settings_screen.008')),
          actions: [
            IconButton(
              tooltip: l.tr('screens_account_settings_screen.064'),
              onPressed: _showHelpDialog,
              icon: const Icon(Icons.info_outline_rounded),
            ),
            const AppNotificationAction(),
            const QuickLogoutAction(),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(78),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: SizedBox(
                  height: 56,
                  child: TabBar(
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorPadding: const EdgeInsets.all(6),
                    labelPadding: EdgeInsets.zero,
                    tabs: [
                      Tab(
                        height: 56,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(l.tr('screens_account_settings_screen.009')),
                            ],
                          ),
                        ),
                      ),
                      Tab(
                        height: 56,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lock_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(l.tr('screens_account_settings_screen.010')),
                            ],
                          ),
                        ),
                      ),
                      Tab(
                        height: 56,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.manage_accounts_rounded,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(l.tr('screens_account_settings_screen.068')),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        drawer: const AppSidebar(),
        body: TabBarView(
          children: [
            _buildProfileTab(),
            _buildPasswordTab(),
            _buildAccountActionsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final l = context.loc;
    final isMobile = MediaQuery.of(context).size.width < 760;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_hasPendingProfileCompletion) ...[
              _buildCompletionNotice(),
              const SizedBox(height: 16),
            ],
            if (_profileLocked) ...[
              _buildLockedNotice(),
              const SizedBox(height: 16),
            ],
            if (isMobile) ...[
              _buildBasicInfoCard(),
              const SizedBox(height: 16),
              _buildIdentityCard(),
              const SizedBox(height: 16),
              _buildPrintLogoCard(),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildBasicInfoCard()),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildIdentityCard()),
                ],
              ),
              const SizedBox(height: 16),
              _buildPrintLogoCard(),
            ],
            const SizedBox(height: 24),
            ShwakelButton(
              label: l.tr('screens_account_settings_screen.011'),
              icon: Icons.save_rounded,
              onPressed: _profileLocked ? null : _save,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordTab() {
    final l = context.loc;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(
                    l.tr('screens_account_settings_screen.013'),
                    _currentPassController,
                    Icons.lock_outline_rounded,
                    obscure: true,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    l.tr('screens_account_settings_screen.014'),
                    _newPassController,
                    Icons.lock_reset_rounded,
                    obscure: true,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    l.tr('screens_account_settings_screen.045'),
                    _confirmNewPassController,
                    Icons.verified_user_rounded,
                    obscure: true,
                  ),
                  const SizedBox(height: 24),
                  ShwakelButton(
                    label: l.tr('screens_account_settings_screen.015'),
                    icon: Icons.security_rounded,
                    onPressed: _changePassword,
                    isLoading: _isSaving,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountActionsTab() {
    final l = context.loc;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              borderColor: AppTheme.textPrimary.withValues(alpha: 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.tr('screens_account_settings_screen.053'),
                    style: AppTheme.h3,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.tr('screens_account_settings_screen.054'),
                    style: AppTheme.bodyAction.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ShwakelButton(
                    label: l.tr('screens_account_settings_screen.055'),
                    icon: Icons.logout_rounded,
                    isSecondary: true,
                    onPressed: _isSaving
                        ? null
                        : () => QuickLogoutAction.logout(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              borderColor: AppTheme.error.withValues(alpha: 0.24),
              color: AppTheme.error.withValues(alpha: 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.tr('screens_account_settings_screen.056'),
                    style: AppTheme.h3.copyWith(color: AppTheme.error),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.tr('screens_account_settings_screen.065'),
                    style: AppTheme.bodyAction.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ShwakelButton(
                    label: l.tr('screens_account_settings_screen.056'),
                    icon: Icons.delete_forever_rounded,
                    isDanger: true,
                    onPressed: _isSaving ? null : _deleteAccount,
                    isLoading: _isSaving,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.tr('screens_account_settings_screen.066'),
      message: l.tr('screens_account_settings_screen.067'),
    );
  }

  bool _canEditField(String fieldKey) {
    if (_user == null) {
      return false;
    }
    final verification =
        _user?['transferVerificationStatus']?.toString() ?? 'unverified';
    if (verification != 'approved') {
      return true;
    }
    return _editableProfileFields.contains(fieldKey);
  }

  Widget _buildBasicInfoCard() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tr('screens_account_settings_screen.019'), style: AppTheme.h3),
          const SizedBox(height: 18),
          _field(
            l.tr('screens_account_settings_screen.020'),
            _fullNameController,
            Icons.badge_rounded,
            enabled: _canEditField('fullName'),
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_account_settings_screen.021'),
            _usernameController,
            Icons.alternate_email_rounded,
            enabled: _canEditField('username'),
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_account_settings_screen.022'),
            _whatsappController,
            Icons.phone_rounded,
            enabled: false,
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_account_settings_screen.023'),
            _emailController,
            Icons.email_rounded,
            enabled: _canEditField('email'),
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_account_settings_screen.024'),
            _addressController,
            Icons.location_on_rounded,
            enabled: _canEditField('address'),
            lines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    final l = context.loc;
    final isMobile = MediaQuery.of(context).size.width < 760;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tr('screens_account_settings_screen.025'), style: AppTheme.h3),
          const SizedBox(height: 18),
          _field(
            l.tr('screens_account_settings_screen.026'),
            _nationalIdController,
            Icons.credit_card_rounded,
            enabled: _canEditField('nationalId'),
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_account_settings_screen.027'),
            _birthDateController,
            Icons.cake_rounded,
            enabled: _canEditField('birthDate'),
            readOnly: true,
            onTap: _canEditField('birthDate') ? _pickDate : null,
          ),
          const SizedBox(height: 16),
          _field(
            l.tr('screens_account_settings_screen.028'),
            _referralPhoneController,
            Icons.call_split_rounded,
            enabled: _canEditField('referralPhone'),
          ),
          if (!isMobile) const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildLockedNotice() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      color: AppTheme.warning.withValues(alpha: 0.06),
      borderColor: AppTheme.warning.withValues(alpha: 0.18),
      child: Row(
        children: [
          const Icon(Icons.lock_person_rounded, color: AppTheme.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.tr('screens_account_settings_screen.047'),
              style: AppTheme.bodyText.copyWith(
                color: AppTheme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionNotice() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(16),
      color: AppTheme.secondary.withValues(alpha: 0.08),
      borderColor: AppTheme.secondary.withValues(alpha: 0.16),
      child: Row(
        children: [
          const Icon(Icons.edit_note_rounded, color: AppTheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.tr('screens_account_settings_screen.048'),
              style: AppTheme.bodyText.copyWith(
                color: AppTheme.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrintLogoCard() {
    final l = context.loc;
    final remoteLogoUrl = _user?['printLogoUrl']?.toString();
    final hasRemoteLogo = remoteLogoUrl != null && remoteLogoUrl.isNotEmpty;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tr('screens_account_settings_screen.029'), style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_account_settings_screen.049'),
            style: AppTheme.caption,
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.05),
              borderRadius: AppTheme.radiusLg,
              border: Border.all(
                color: AppTheme.secondary.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                if (_printLogoPreview != null)
                  ClipRRect(
                    borderRadius: AppTheme.radiusMd,
                    child: Image.memory(
                      _printLogoPreview!,
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                  )
                else if (hasRemoteLogo)
                  ClipRRect(
                    borderRadius: AppTheme.radiusMd,
                    child: Image.network(
                      remoteLogoUrl,
                      height: 90,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stackTrace) => const Icon(
                        Icons.image_not_supported_rounded,
                        size: 54,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.image_rounded,
                    size: 54,
                    color: AppTheme.textTertiary,
                  ),
                const SizedBox(height: 12),
                Text(
                  _printLogoFileName ??
                      (hasRemoteLogo
                          ? l.tr('screens_account_settings_screen.030')
                          : l.tr('screens_account_settings_screen.031')),
                  style: AppTheme.bodyText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ShwakelButton(
                label: l.tr('screens_account_settings_screen.032'),
                icon: Icons.upload_rounded,
                onPressed: _pickAndUploadPrintLogo,
                isLoading: _isUploadingLogo,
                width: 160,
              ),
              if (hasRemoteLogo)
                ShwakelButton(
                  label: l.tr('screens_account_settings_screen.033'),
                  icon: Icons.delete_outline_rounded,
                  isSecondary: true,
                  onPressed: _isUploadingLogo ? null : _removePrintLogo,
                  width: 160,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadPrintLogo() async {
    final l = context.loc;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) {
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.034'),
        message: l.tr('screens_account_settings_screen.050'),
      );
      return;
    }

    setState(() {
      _isUploadingLogo = true;
      _printLogoPreview = bytes;
      _printLogoFileName = file.name;
    });

    try {
      final response = await _apiService.updatePrintLogo(
        logoBase64: _asDataUri(file.name, bytes),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _user = Map<String, dynamic>.from(response['user'] as Map);
      });
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_account_settings_screen.035'),
        message: l.tr('screens_account_settings_screen.051'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.036'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingLogo = false);
      }
    }
  }

  Future<void> _removePrintLogo() async {
    final l = context.loc;
    setState(() => _isUploadingLogo = true);
    try {
      final response = await _apiService.updatePrintLogo(remove: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _user = Map<String, dynamic>.from(response['user'] as Map);
        _printLogoPreview = null;
        _printLogoFileName = null;
      });
      AppAlertService.showSuccess(
        context,
        title: l.tr('screens_account_settings_screen.037'),
        message: l.tr('screens_account_settings_screen.052'),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: l.tr('screens_account_settings_screen.038'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingLogo = false);
      }
    }
  }

  String _asDataUri(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    final mime = lower.endsWith('.jpg') || lower.endsWith('.jpeg')
        ? 'image/jpeg'
        : lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/png';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool enabled = true,
    bool obscure = false,
    bool readOnly = false,
    VoidCallback? onTap,
    int lines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      readOnly: readOnly,
      onTap: onTap,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: enabled
            ? null
            : const Icon(Icons.lock_outline_rounded, size: 18),
        filled: !enabled,
        fillColor: enabled ? null : AppTheme.background,
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _birthDateController.text = picked.toIso8601String().split('T').first;
    });
  }
}
