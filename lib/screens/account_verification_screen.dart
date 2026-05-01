import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AccountVerificationScreen extends StatefulWidget {
  const AccountVerificationScreen({super.key});

  @override
  State<AccountVerificationScreen> createState() =>
      _AccountVerificationScreenState();
}

class _AccountVerificationScreenState extends State<AccountVerificationScreen> {
  static const int _maxSelectedImageBytes = 25 * 1024 * 1024;
  static const int _targetUploadImageBytes = 4 * 1024 * 1024;
  static const int _maxImageDimension = 2600;

  final ApiService _apiService = ApiService();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _nationalIdController = TextEditingController();
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isApproved = false;
  String _requestedRole = 'verified_member';
  String? _identityBase64;
  String? _selfieBase64;
  String? _identityFileLabel;
  String? _selfieFileLabel;
  Uint8List? _identityPreviewBytes;
  Uint8List? _selfiePreviewBytes;
  Map<String, dynamic>? _verification;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _nationalIdController.dispose();
    _birthDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final response = await _apiService.getVerificationStatus();
      if (!mounted) {
        return;
      }
      final verification = Map<String, dynamic>.from(
        response['verification'] as Map? ?? const <String, dynamic>{},
      );
      final status = verification['status']?.toString() ?? 'unverified';
      final fullName = verification['fullName']?.toString() ?? '';
      final nationalId = verification['nationalId']?.toString() ?? '';
      final birthDate = verification['birthDate']?.toString() ?? '';
      final latestRequest = Map<String, dynamic>.from(
        verification['latestRequest'] as Map? ?? const <String, dynamic>{},
      );
      setState(() {
        _verification = verification;
        _isApproved = status == 'approved';
        _requestedRole = latestRequest['requestedRole']?.toString() == 'driver'
            ? 'driver'
            : 'verified_member';
        _isLoading = false;
        if (fullName.isNotEmpty) {
          _fullNameController.text = fullName;
        }
        if (nationalId.isNotEmpty) {
          _nationalIdController.text = nationalId;
        }
        if (birthDate.isNotEmpty) {
          _birthDateController.text = birthDate;
        }
      });
      if (_isApproved) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/account-settings');
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage(bool identity) async {
    final l = context.loc;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || bytes.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }

    if (bytes.length > _maxSelectedImageBytes) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_account_verification_screen.003'),
        message: l.tr('screens_account_verification_screen.030'),
      );
      return;
    }

    final prepared = _prepareImageForVerification(bytes);
    if (prepared == null) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_account_verification_screen.003'),
        message: l.tr('screens_account_verification_screen.029'),
      );
      return;
    }

    setState(() {
      if (identity) {
        _identityBase64 = prepared.dataUri;
        _identityFileLabel =
            '${file.name} - ${_formatBytes(prepared.bytes.length)}';
        _identityPreviewBytes = prepared.bytes;
      } else {
        _selfieBase64 = prepared.dataUri;
        _selfieFileLabel =
            '${file.name} - ${_formatBytes(prepared.bytes.length)}';
        _selfiePreviewBytes = prepared.bytes;
      }
    });
  }

  Future<void> _submit() async {
    final l = context.loc;
    final fullName = _fullNameController.text.trim();
    final nationalId = _nationalIdController.text.trim();
    final birthDate = _birthDateController.text.trim();
    if (_isApproved) {
      return;
    }
    if ((_identityBase64 ?? '').isEmpty ||
        (_selfieBase64 ?? '').isEmpty ||
        fullName.isEmpty ||
        nationalId.isEmpty ||
        birthDate.isEmpty) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_account_verification_screen.001'),
        message: l.tr('screens_account_verification_screen.016'),
      );
      return;
    }

    if (!_hasFourPartFullName) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_account_verification_screen.001'),
        message: l.tr('screens_account_verification_screen.031'),
      );
      return;
    }

    if (DateTime.tryParse(birthDate) == null) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_account_verification_screen.001'),
        message: l.tr('screens_account_verification_screen.026'),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _apiService.submitVerification(
        identityDocumentBase64: _identityBase64!,
        selfieImageBase64: _selfieBase64!,
        fullName: fullName,
        nationalId: nationalId,
        birthDate: birthDate,
        requestedRole: _requestedRole,
        notes: _notesController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_account_verification_screen.002'),
        message: l.tr('screens_account_verification_screen.017'),
      );
      await _loadStatus();
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.tr('screens_account_verification_screen.003'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  bool get _hasIdentityImage => (_identityBase64 ?? '').isNotEmpty;

  bool get _hasSelfieImage => (_selfieBase64 ?? '').isNotEmpty;

  bool get _hasFourPartFullName {
    final parts = _fullNameController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.length >= 4;
  }

  bool get _hasNationalId => _nationalIdController.text.trim().isNotEmpty;

  bool get _hasValidBirthDate =>
      DateTime.tryParse(_birthDateController.text.trim()) != null;

  List<_VerificationRequirement> _requirementsForStatus(String status) {
    final l = context.loc;
    final needsRefreshUploads = status == 'rejected';

    return [
      _VerificationRequirement(
        label: 'رفع صورة الهوية',
        completed: _hasIdentityImage,
        highlighted: needsRefreshUploads || !_hasIdentityImage,
        icon: Icons.badge_rounded,
      ),
      _VerificationRequirement(
        label: 'رفع صورة السيلفي مع الهوية',
        completed: _hasSelfieImage,
        highlighted: needsRefreshUploads || !_hasSelfieImage,
        icon: Icons.face_rounded,
      ),
      _VerificationRequirement(
        label: l.tr('screens_account_verification_screen.032'),
        completed: _hasFourPartFullName,
        highlighted: !_hasFourPartFullName,
        icon: Icons.person_rounded,
      ),
      _VerificationRequirement(
        label: 'إدخال رقم الهوية',
        completed: _hasNationalId,
        highlighted: !_hasNationalId,
        icon: Icons.credit_card_rounded,
      ),
      _VerificationRequirement(
        label: 'اختيار تاريخ ميلاد صحيح',
        completed: _hasValidBirthDate,
        highlighted: !_hasValidBirthDate,
        icon: Icons.cake_rounded,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    if (_isApproved) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final status = _verification?['status']?.toString() ?? 'unverified';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_account_verification_screen.004')),
        actions: const [AppNotificationAction(), QuickLogoutAction()],
      ),
      drawer: const AppSidebar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: ResponsiveScaffoldContainer(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildStatusIndicator(status),
                    const SizedBox(height: 24),
                    _buildUploadSection(status),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(30),
      gradient: AppTheme.darkGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 680;
          final iconBox = Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Colors.white,
              size: 36,
            ),
          );

          final content = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr('screens_account_verification_screen.005'),
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  l.tr('screens_account_verification_screen.018'),
                  style: AppTheme.bodyAction.copyWith(
                    color: Colors.white70,
                    height: 1.6,
                  ),
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

  Widget _buildStatusIndicator(String status) {
    final l = context.loc;
    Color color;
    String title;
    String text;
    IconData icon;
    final latestRequest = Map<String, dynamic>.from(
      _verification?['latestRequest'] as Map? ?? const <String, dynamic>{},
    );
    final reviewNotes = latestRequest['reviewNotes']?.toString().trim() ?? '';
    final requestedRoleLabel =
        latestRequest['requestedRoleLabel']?.toString().trim().isNotEmpty ==
            true
        ? latestRequest['requestedRoleLabel'].toString().trim()
        : (_requestedRole == 'driver'
              ? l.tr('shared.role_driver')
              : l.tr('shared.role_verified_member'));

    switch (status) {
      case 'pending':
        color = AppTheme.warning;
        title = l.tr('screens_account_verification_screen.006');
        text = l.tr('screens_account_verification_screen.019');
        icon = Icons.timer_rounded;
        break;
      case 'rejected':
        color = AppTheme.error;
        title = l.tr('screens_account_verification_screen.007');
        text = l.tr('screens_account_verification_screen.020');
        icon = Icons.cancel_rounded;
        break;
      default:
        color = AppTheme.primary;
        title = l.tr('screens_account_verification_screen.008');
        text = l.tr('screens_account_verification_screen.021');
        icon = Icons.info_rounded;
    }

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      color: color.withValues(alpha: 0.05),
      borderColor: color.withValues(alpha: 0.2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.bodyBold.copyWith(color: color)),
              const SizedBox(height: 6),
              Text(
                text,
                style: AppTheme.bodyAction.copyWith(color: color, height: 1.6),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.badge_outlined, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l.tr('account_verification.requested_role_label')}: $requestedRoleLabel',
                        style: AppTheme.bodyAction.copyWith(
                          color: AppTheme.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (status == 'rejected' && reviewNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.tr('account_verification.rejection_reason_label'),
                        style: AppTheme.bodyBold.copyWith(color: color),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        reviewNotes,
                        style: AppTheme.bodyAction.copyWith(
                          color: AppTheme.textPrimary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 14),
                details,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 16),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUploadSection(String status) {
    final l = context.loc;
    final requirements = _requirementsForStatus(status);
    return ShwakelCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.tr('screens_account_verification_screen.009'),
            style: AppTheme.h3,
          ),
          const SizedBox(height: 10),
          Text(
            l.tr('screens_account_verification_screen.022'),
            style: AppTheme.bodyAction.copyWith(height: 1.6),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.security_rounded,
                  color: AppTheme.warning,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.tr('screens_account_verification_screen.028'),
                    style: AppTheme.bodyAction.copyWith(
                      height: 1.6,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.tr('screens_account_verification_screen.027'),
            style: AppTheme.caption.copyWith(
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _requirementChip(Icons.badge_rounded, 'الهوية واضحة وكاملة'),
              _requirementChip(
                Icons.face_rounded,
                'السيلفي يظهر الوجه والهوية',
              ),
              _requirementChip(Icons.image_rounded, 'JPG / PNG / WEBP'),
              _requirementChip(Icons.speed_rounded, 'الضغط يتم تلقائيًا'),
            ],
          ),
          const SizedBox(height: 18),
          _buildSubmissionChecklist(status, requirements),
          const SizedBox(height: 22),
          Text(
            context.loc.tr('account_verification.post_verification_role'),
            style: AppTheme.bodyBold,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [
                    _roleChoiceCard(
                      value: 'verified_member',
                      label: l.tr('shared.role_verified_member'),
                      icon: Icons.storefront_rounded,
                    ),
                    const SizedBox(height: 12),
                    _roleChoiceCard(
                      value: 'driver',
                      label: l.tr('shared.role_driver'),
                      icon: Icons.local_shipping_rounded,
                    ),
                  ],
                );
              }

              return SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                    value: 'verified_member',
                    icon: const Icon(Icons.storefront_rounded),
                    label: Text(l.tr('shared.role_verified_member')),
                  ),
                  ButtonSegment<String>(
                    value: 'driver',
                    icon: const Icon(Icons.local_shipping_rounded),
                    label: Text(l.tr('shared.role_driver')),
                  ),
                ],
                selected: {_requestedRole},
                onSelectionChanged: (selection) {
                  setState(() => _requestedRole = selection.first);
                },
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            _requestedRole == 'driver'
                ? context.loc.tr('account_verification.delivery_driver_note')
                : context.loc.tr('account_verification.verified_member_note'),
            style: AppTheme.caption.copyWith(height: 1.5, fontSize: 13),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _fullNameController,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration:
                _verificationInputDecoration(
                  highlight: !_hasFourPartFullName,
                  labelText: l.tr('screens_account_verification_screen.033'),
                  prefixIcon: const Icon(Icons.person_rounded),
                ).copyWith(
                  helperText: l.tr('screens_account_verification_screen.034'),
                ),
          ),
          const SizedBox(height: 16),
          _docPicker(
            l.tr('screens_account_verification_screen.010'),
            _identityBase64,
            _identityFileLabel,
            _identityPreviewBytes,
            () => _clearPickedImage(true),
            () => _pickImage(true),
          ),
          const SizedBox(height: 16),
          _docPicker(
            l.tr('screens_account_verification_screen.011'),
            _selfieBase64,
            _selfieFileLabel,
            _selfiePreviewBytes,
            () => _clearPickedImage(false),
            () => _pickImage(false),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _nationalIdController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: _verificationInputDecoration(
              highlight: !_hasNationalId,
              labelText: l.tr('screens_account_verification_screen.024'),
              prefixIcon: const Icon(Icons.credit_card_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _birthDateController,
            readOnly: true,
            onTap: _pickBirthDate,
            decoration: _verificationInputDecoration(
              highlight:
                  _birthDateController.text.trim().isNotEmpty &&
                  !_hasValidBirthDate,
              labelText: l.tr('screens_account_verification_screen.025'),
              prefixIcon: const Icon(Icons.cake_rounded),
            ),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l.tr('screens_account_verification_screen.012'),
              alignLabelWithHint: true,
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.note_rounded),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (status == 'rejected')
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                l.tr('screens_account_verification_screen.023'),
                style: AppTheme.caption.copyWith(color: AppTheme.error),
              ),
            ),
          ShwakelButton(
            label: l.tr('screens_account_verification_screen.013'),
            icon: Icons.cloud_upload_rounded,
            onPressed: _submit,
            isLoading: _isSubmitting,
          ),
        ],
      ),
    );
  }

  Widget _docPicker(
    String label,
    String? base64,
    String? fileLabel,
    Uint8List? previewBytes,
    VoidCallback onClear,
    VoidCallback onTap,
  ) {
    final l = context.loc;
    final hasFile = base64 != null && base64.isNotEmpty;
    final borderColor = hasFile
        ? AppTheme.success.withValues(alpha: 0.30)
        : AppTheme.error.withValues(alpha: 0.22);
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMd,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasFile
              ? AppTheme.success.withValues(alpha: 0.05)
              : AppTheme.background,
          border: Border.all(color: borderColor),
          borderRadius: AppTheme.radiusMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: hasFile ? Colors.white : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasFile
                      ? AppTheme.success.withValues(alpha: 0.20)
                      : AppTheme.border,
                ),
              ),
              child: hasFile && previewBytes != null
                  ? Image.memory(previewBytes, fit: BoxFit.cover)
                  : const Icon(
                      Icons.camera_alt_rounded,
                      color: AppTheme.textTertiary,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTheme.bodyText.copyWith(
                      color: hasFile ? AppTheme.success : AppTheme.textPrimary,
                    ),
                  ),
                  if (hasFile && fileLabel != null && fileLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      fileLabel,
                      style: AppTheme.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hasFile
                      ? l.tr('screens_account_verification_screen.014')
                      : l.tr('screens_account_verification_screen.015'),
                  style: TextStyle(
                    color: hasFile ? AppTheme.success : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (hasFile) ...[
                  const SizedBox(height: 8),
                  IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: AppTheme.error,
                    tooltip: 'حذف الصورة',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _requirementChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTheme.caption.copyWith(color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionChecklist(
    String status,
    List<_VerificationRequirement> requirements,
  ) {
    final pendingCount = requirements.where((item) => !item.completed).length;
    final title = pendingCount == 0
        ? 'الطلب جاهز للإرسال'
        : 'المتبقي قبل الإرسال: $pendingCount';
    final accent = pendingCount == 0 ? AppTheme.success : AppTheme.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status == 'rejected' ? 'راجع هذه العناصر قبل إعادة الإرسال' : title,
            style: AppTheme.bodyBold.copyWith(color: accent),
          ),
          const SizedBox(height: 10),
          ...requirements.map(_buildRequirementRow),
        ],
      ),
    );
  }

  Widget _buildRequirementRow(_VerificationRequirement item) {
    final color = item.completed ? AppTheme.success : AppTheme.textSecondary;
    final bgColor = item.completed
        ? AppTheme.success.withValues(alpha: 0.08)
        : item.highlighted
        ? AppTheme.error.withValues(alpha: 0.08)
        : AppTheme.surfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: item.completed
                ? AppTheme.success.withValues(alpha: 0.18)
                : item.highlighted
                ? AppTheme.error.withValues(alpha: 0.20)
                : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              item.completed ? Icons.check_circle_rounded : item.icon,
              color: item.completed
                  ? AppTheme.success
                  : item.highlighted
                  ? AppTheme.error
                  : color,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: AppTheme.bodyAction.copyWith(
                  color: item.completed
                      ? AppTheme.success
                      : item.highlighted
                      ? AppTheme.error
                      : AppTheme.textPrimary,
                  fontWeight: item.highlighted ? FontWeight.w700 : null,
                ),
              ),
            ),
            Text(
              item.completed ? 'مكتمل' : 'مطلوب',
              style: AppTheme.caption.copyWith(
                color: item.completed
                    ? AppTheme.success
                    : item.highlighted
                    ? AppTheme.error
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _verificationInputDecoration({
    required bool highlight,
    required String labelText,
    required Widget prefixIcon,
  }) {
    final borderColor = highlight ? AppTheme.error : AppTheme.border;
    return InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: highlight ? AppTheme.error : AppTheme.primary,
          width: 1.4,
        ),
      ),
    );
  }

  Widget _roleChoiceCard({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final selected = _requestedRole == value;

    return InkWell(
      onTap: () => setState(() => _requestedRole = value),
      borderRadius: AppTheme.radiusMd,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.surfaceVariant,
          borderRadius: AppTheme.radiusMd,
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTheme.bodyBold.copyWith(
                  color: selected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) {
      return;
    }
    _birthDateController.text = picked.toIso8601String().split('T').first;
    setState(() {});
  }

  void _clearPickedImage(bool identity) {
    setState(() {
      if (identity) {
        _identityBase64 = null;
        _identityFileLabel = null;
        _identityPreviewBytes = null;
      } else {
        _selfieBase64 = null;
        _selfieFileLabel = null;
        _selfiePreviewBytes = null;
      }
    });
  }

  _PreparedVerificationImage? _prepareImageForVerification(Uint8List bytes) {
    final decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      return null;
    }
    var decoded = decodedImage;

    if (decoded.width > _maxImageDimension ||
        decoded.height > _maxImageDimension) {
      decoded = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? _maxImageDimension : null,
        height: decoded.height > decoded.width ? _maxImageDimension : null,
        interpolation: img.Interpolation.average,
      );
    }

    var quality = 86;
    Uint8List encoded = Uint8List.fromList(
      img.encodeJpg(decoded, quality: quality),
    );

    while (encoded.length > _targetUploadImageBytes && quality > 48) {
      quality -= 8;
      encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    }

    while (encoded.length > _targetUploadImageBytes &&
        decoded.width > 1200 &&
        decoded.height > 1200) {
      decoded = img.copyResize(
        decoded,
        width: (decoded.width * 0.88).round(),
        height: (decoded.height * 0.88).round(),
        interpolation: img.Interpolation.average,
      );
      encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    }

    return _PreparedVerificationImage(
      bytes: encoded,
      dataUri: 'data:image/jpeg;base64,${base64Encode(encoded)}',
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }
}

class _PreparedVerificationImage {
  const _PreparedVerificationImage({
    required this.bytes,
    required this.dataUri,
  });

  final Uint8List bytes;
  final String dataUri;
}

class _VerificationRequirement {
  const _VerificationRequirement({
    required this.label,
    required this.completed,
    required this.highlighted,
    required this.icon,
  });

  final String label;
  final bool completed;
  final bool highlighted;
  final IconData icon;
}
