import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
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
    final user = await _authService.currentUser();
    if (user == null || !mounted) {
      return;
    }

    setState(() {
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
    if (_profileLocked) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final response = await _authService.updateProfile(
        fullName: _fullNameController.text,
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
        title: 'تم الحفظ',
        message: 'تم تحديث بيانات الملف الشخصي بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر الحفظ',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final current = _currentPassController.text.trim();
    final next = _newPassController.text;
    final confirm = _confirmNewPassController.text;

    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      AppAlertService.showError(
        context,
        title: 'بيانات ناقصة',
        message: 'أدخل كلمة المرور الحالية والجديدة وتأكيدها.',
      );
      return;
    }
    if (next != confirm) {
      AppAlertService.showError(
        context,
        title: 'عدم تطابق',
        message: 'تأكيد كلمة المرور الجديدة غير مطابق.',
      );
      return;
    }
    if (next.length < 8) {
      AppAlertService.showError(
        context,
        title: 'كلمة المرور قصيرة',
        message: 'يجب أن تكون كلمة المرور الجديدة 8 أحرف على الأقل.',
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
        title: 'تم التحديث',
        message: 'تم تغيير كلمة المرور بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر التحديث',
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('إعدادات الحساب'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: EdgeInsets.all(6),
                  labelPadding: EdgeInsets.symmetric(horizontal: 8),
                  tabs: [
                    Tab(
                      text: 'البيانات',
                      icon: Icon(Icons.person_rounded, size: 20),
                    ),
                    Tab(
                      text: 'الكلمة',
                      icon: Icon(Icons.lock_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        drawer: const AppSidebar(),
        body: TabBarView(children: [_buildProfileTab(), _buildPasswordTab()]),
      ),
    );
  }

  Widget _buildProfileTab() {
    final isMobile = MediaQuery.of(context).size.width < 760;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHero(),
            if (_hasPendingProfileCompletion) ...[
              const SizedBox(height: 16),
              _buildCompletionNotice(),
            ],
            if (_profileLocked) ...[
              const SizedBox(height: 16),
              _buildLockedNotice(),
            ],
            const SizedBox(height: 20),
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
              label: 'حفظ التغييرات',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: ResponsiveScaffoldContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShwakelCard(
              padding: const EdgeInsets.all(28),
              gradient: AppTheme.primaryGradient,
              shadowLevel: ShwakelShadowLevel.premium,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تحديث كلمة المرور',
                    style: AppTheme.h2.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أدخل الكلمة الحالية ثم الجديدة.',
                    style: AppTheme.bodyAction.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(
                    'كلمة المرور الحالية',
                    _currentPassController,
                    Icons.lock_outline_rounded,
                    obscure: true,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    'كلمة المرور الجديدة',
                    _newPassController,
                    Icons.lock_reset_rounded,
                    obscure: true,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    'تأكيد كلمة المرور الجديدة',
                    _confirmNewPassController,
                    Icons.verified_user_rounded,
                    obscure: true,
                  ),
                  const SizedBox(height: 24),
                  ShwakelButton(
                    label: 'تحديث كلمة المرور',
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

  Widget _buildProfileHero() {
    final name = _fullNameController.text.trim().isEmpty
        ? _usernameController.text.trim()
        : _fullNameController.text.trim();
    final verification =
        _user?['transferVerificationStatus']?.toString() ?? 'unverified';
    final isApproved = verification == 'approved';
    final pendingFieldsCount = _editableProfileFields.length;

    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      gradient: AppTheme.primaryGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white24,
            child: Text(
              name.isEmpty ? 'ش' : name.substring(0, 1).toUpperCase(),
              style: AppTheme.h1.copyWith(color: Colors.white, fontSize: 28),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTheme.h2.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '@${_usernameController.text}',
                  style: AppTheme.bodyAction.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isApproved ? 'الحساب موثق' : 'الحساب غير موثق',
                    style: AppTheme.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildHeroStatusChip(
                      icon: Icons.phone_rounded,
                      label: _whatsappController.text.trim().isEmpty
                          ? 'Ø±Ù‚Ù… ØºÙŠØ± Ù…Ø­Ø¯Ø¯'
                          : _whatsappController.text.trim(),
                    ),
                    if (_hasPendingProfileCompletion)
                      _buildHeroStatusChip(
                        icon: Icons.edit_note_rounded,
                        label:
                            '$pendingFieldsCount Ø­Ù‚Ù„ ÙŠØ­ØªØ§Ø¬ Ø¥ÙƒÙ…Ø§Ù„',
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
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('البيانات الأساسية', style: AppTheme.h3),
          const SizedBox(height: 18),
          _field(
            'الاسم الكامل',
            _fullNameController,
            Icons.badge_rounded,
            enabled: _canEditField('fullName'),
          ),
          const SizedBox(height: 16),
          _field(
            'اسم المستخدم',
            _usernameController,
            Icons.alternate_email_rounded,
            enabled: false,
          ),
          const SizedBox(height: 16),
          _field(
            'رقم الهاتف / واتساب',
            _whatsappController,
            Icons.phone_rounded,
            enabled: false,
          ),
          const SizedBox(height: 16),
          _field(
            'البريد الإلكتروني',
            _emailController,
            Icons.email_rounded,
            enabled: _canEditField('email'),
          ),
          const SizedBox(height: 16),
          _field(
            'العنوان',
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
    final isMobile = MediaQuery.of(context).size.width < 760;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الهوية والمعلومات الإضافية', style: AppTheme.h3),
          const SizedBox(height: 18),
          _field(
            'رقم الهوية',
            _nationalIdController,
            Icons.credit_card_rounded,
            enabled: _canEditField('nationalId'),
          ),
          const SizedBox(height: 16),
          _field(
            'تاريخ الميلاد',
            _birthDateController,
            Icons.cake_rounded,
            enabled: _canEditField('birthDate'),
            readOnly: true,
            onTap: _canEditField('birthDate') ? _pickDate : null,
          ),
          const SizedBox(height: 16),
          _field(
            'رقم الإحالة',
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
              'بعض البيانات مقفلة بعد التوثيق. للتعديل تواصل مع الدعم.',
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
              'Ø¨Ø¥Ù…ÙƒØ§Ù†Ùƒ Ø¥ÙƒÙ…Ø§Ù„ Ø§Ù„Ø­Ù‚ÙˆÙ„ Ø§Ù„Ù†Ø§Ù‚ØµØ© ÙÙ‚Ø·. Ø¨Ø¹Ø¯ Ø§Ù„Ø­ÙØ¸ Ø³ÙŠØªÙ… Ø¥ØºÙ„Ø§Ù‚Ù‡Ø§ ØªÙ„Ù‚Ø§Ø¦ÙŠÙ‹Ø§ Ù„Ø£Ù† Ø§Ù„Ø­Ø³Ø§Ø¨ Ù…ÙˆØ«Ù‚.',
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
    final remoteLogoUrl = _user?['printLogoUrl']?.toString();
    final hasRemoteLogo = remoteLogoUrl != null && remoteLogoUrl.isNotEmpty;

    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('شعار الطباعة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text('شعار يظهر على البطاقات عند الطباعة.', style: AppTheme.caption),
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
                          ? 'تم حفظ شعار مخصص'
                          : 'لا يوجد شعار مخصص حتى الآن'),
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
                label: 'رفع شعار',
                icon: Icons.upload_rounded,
                onPressed: _pickAndUploadPrintLogo,
                isLoading: _isUploadingLogo,
                width: 160,
              ),
              if (hasRemoteLogo)
                ShwakelButton(
                  label: 'حذف الشعار',
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

  Widget _buildHeroStatusChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
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

  Future<void> _pickAndUploadPrintLogo() async {
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
        title: 'تعذر القراءة',
        message: 'تعذر قراءة ملف الشعار.',
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
        title: 'تم الرفع',
        message: 'تم تحديث شعار الطباعة بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر الرفع',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingLogo = false);
      }
    }
  }

  Future<void> _removePrintLogo() async {
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
        title: 'تم الحذف',
        message: 'تم حذف شعار الطباعة بنجاح.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر الحذف',
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
