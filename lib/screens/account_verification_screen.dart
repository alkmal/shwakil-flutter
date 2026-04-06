import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
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
  final ApiService _apiService = ApiService();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isApproved = false;
  String? _identityBase64;
  String? _selfieBase64;
  Map<String, dynamic>? _verification;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
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
      setState(() {
        _verification = verification;
        _isApproved = status == 'approved';
        _isLoading = false;
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) {
      return;
    }
    final extension = (result?.files.single.extension ?? 'png').toLowerCase();
    final mimeType = extension == 'jpg' || extension == 'jpeg'
        ? 'image/jpeg'
        : 'image/png';
    final base64 = 'data:$mimeType;base64,${base64Encode(bytes)}';
    setState(() {
      if (identity) {
        _identityBase64 = base64;
      } else {
        _selfieBase64 = base64;
      }
    });
  }

  Future<void> _submit() async {
    final l = context.loc;
    if (_isApproved) {
      return;
    }
    if ((_identityBase64 ?? '').isEmpty || (_selfieBase64 ?? '').isEmpty) {
      await AppAlertService.showError(
        context,
        title: l.tr('screens_account_verification_screen.001'),
        message: l.text(
          'يرجى اختيار صورة الهوية وصورة السيلفي أولًا.',
          'Please select the identity document and selfie image first.',
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _apiService.submitVerification(
        identityDocumentBase64: _identityBase64!,
        selfieImageBase64: _selfieBase64!,
        notes: _notesController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      await AppAlertService.showSuccess(
        context,
        title: l.tr('screens_account_verification_screen.002'),
        message: l.text(
          'طلب التوثيق قيد المراجعة الآن.',
          'Your verification request is now under review.',
        ),
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
                  l.text(
                    'ارفع وثائقك بشكل واضح لتفعيل التحويلات الكاملة وميزات الحساب المتقدمة.',
                    'Upload clear documents to unlock full transfers and advanced account features.',
                  ),
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

    switch (status) {
      case 'pending':
        color = AppTheme.warning;
        title = l.tr('screens_account_verification_screen.006');
        text = l.text(
          'طلبك قيد المراجعة من قبل الإدارة، وسيتم إشعارك عند تحديث الحالة.',
          'Your request is under review by the administration. You will be notified when the status changes.',
        );
        icon = Icons.timer_rounded;
        break;
      case 'rejected':
        color = AppTheme.error;
        title = l.tr('screens_account_verification_screen.007');
        text = l.text(
          'تم رفض الطلب السابق، يرجى إعادة رفع صور أوضح للهوية والسيلفي.',
          'Your previous request was rejected. Please upload clearer identity and selfie images.',
        );
        icon = Icons.cancel_rounded;
        break;
      default:
        color = AppTheme.primary;
        title = l.tr('screens_account_verification_screen.008');
        text = l.text(
          'حسابك غير موثق حاليًا، ارفع المستندات المطلوبة لإكمال التفعيل.',
          'Your account is not verified yet. Upload the required documents to complete activation.',
        );
        icon = Icons.info_rounded;
    }

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      color: color.withValues(alpha: 0.05),
      borderColor: color.withValues(alpha: 0.2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.bodyBold.copyWith(color: color)),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: AppTheme.bodyAction.copyWith(
                    color: color,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadSection(String status) {
    final l = context.loc;
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
            l.text(
              'ارفع صورة واضحة للهوية وصورة سيلفي تحمل الهوية نفسها لتسريع المراجعة.',
              'Upload a clear identity image and a selfie holding the same identity document to speed up review.',
            ),
            style: AppTheme.bodyAction.copyWith(height: 1.6),
          ),
          const SizedBox(height: 22),
          _docPicker(
            l.tr('screens_account_verification_screen.010'),
            _identityBase64,
            () => _pickImage(true),
          ),
          const SizedBox(height: 16),
          _docPicker(
            l.tr('screens_account_verification_screen.011'),
            _selfieBase64,
            () => _pickImage(false),
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
                l.text(
                  'يمكنك إعادة الإرسال بعد تعديل الصور أو استبدالها.',
                  'You can resubmit after editing or replacing the uploaded images.',
                ),
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

  Widget _docPicker(String label, String? base64, VoidCallback onTap) {
    final l = context.loc;
    final hasFile = base64 != null && base64.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMd,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasFile
              ? AppTheme.success.withValues(alpha: 0.05)
              : AppTheme.background,
          border: Border.all(
            color: hasFile
                ? AppTheme.success.withValues(alpha: 0.30)
                : AppTheme.border,
          ),
          borderRadius: AppTheme.radiusMd,
        ),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.check_circle_rounded : Icons.camera_alt_rounded,
              color: hasFile ? AppTheme.success : AppTheme.textTertiary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTheme.bodyText.copyWith(
                  color: hasFile ? AppTheme.success : AppTheme.textPrimary,
                ),
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}
