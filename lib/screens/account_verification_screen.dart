import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/index.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../utils/app_theme.dart';
import '../widgets/shwakel_card.dart';
import '../widgets/shwakel_button.dart';

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
      if (!mounted) return;
      final ver = Map<String, dynamic>.from(
        response['verification'] as Map? ?? {},
      );
      final status = ver['status']?.toString() ?? 'unverified';
      setState(() {
        _verification = ver;
        _isApproved = status == 'approved';
        _isLoading = false;
      });
      if (_isApproved) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted)
            Navigator.pushReplacementNamed(context, '/account-settings');
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(bool identity) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    final ext = (result?.files.single.extension ?? 'png').toLowerCase();
    final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';
    final base64 = 'data:$mime;base64,${base64Encode(bytes)}';
    setState(() {
      if (identity) {
        _identityBase64 = base64;
      } else {
        _selfieBase64 = base64;
      }
    });
  }

  Future<void> _submit() async {
    if (_isApproved) return;
    if ((_identityBase64 ?? '').isEmpty || (_selfieBase64 ?? '').isEmpty) {
      AppAlertService.showError(
        context,
        message: 'يرجى اختيار صورة الهوية وصورة السيلفي أولاً.',
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _apiService.submitVerification(
        identityDocumentBase64: _identityBase64!,
        selfieImageBase64: _selfieBase64!,
        notes: _notesController.text,
      );
      if (!mounted) return;
      AppAlertService.showSuccess(
        context,
        title: 'تم الإرسال بنجاح',
        message: 'طلب التوثيق قيد المراجعة الآن.',
      );
      await _loadStatus();
    } catch (e) {
      if (mounted)
        AppAlertService.showError(
          context,
          message: ErrorMessageService.sanitize(e),
        );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isApproved)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final status = _verification?['status']?.toString() ?? 'unverified';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('توثيق الهوية')),
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
                    _buildUploadSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      gradient: AppTheme.darkGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'توثيق الحساب',
                  style: AppTheme.h2.copyWith(color: Colors.white),
                ),
                Text(
                  'ارفع وثائقك لتفعيل كامل ميزات الحساب والتحويلات المباشرة.',
                  style: AppTheme.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String status) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case 'pending':
        color = AppTheme.warning;
        text = 'طلبك قيد المراجعة من قبل الإدارة.';
        icon = Icons.timer_rounded;
        break;
      case 'rejected':
        color = AppTheme.error;
        text = 'تم رفض الطلب السابق، يرجى إعادة المحاولة مع وثائق أوضح.';
        icon = Icons.cancel_rounded;
        break;
      default:
        color = AppTheme.primary;
        text = 'حسابك غير موثق حالياً، يرجى رفع الوثائق المطلوبة.';
        icon = Icons.info_rounded;
    }

    return ShwakelCard(
      padding: const EdgeInsets.all(20),
      color: color.withOpacity(0.05),
      borderColor: color.withOpacity(0.2),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(text, style: AppTheme.bodyBold.copyWith(color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadSection() {
    return ShwakelCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('المرفقات المطلوبة', style: AppTheme.h3),
          const SizedBox(height: 24),
          _docPicker(
            'صورة الهوية / جواز السفر',
            _identityBase64,
            () => _pickImage(true),
          ),
          const SizedBox(height: 16),
          _docPicker(
            'صورة شخصية (سيلفي) مع الهوية',
            _selfieBase64,
            () => _pickImage(false),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'ملاحظات إضافية (اختياري)',
              alignLabelWithHint: true,
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.note_rounded),
              ),
            ),
          ),
          const SizedBox(height: 32),
          ShwakelButton(
            label: 'إرسال طلب التوثيق',
            icon: Icons.cloud_upload_rounded,
            onPressed: _submit,
            isLoading: _isSubmitting,
          ),
        ],
      ),
    );
  }

  Widget _docPicker(String label, String? base64, VoidCallback onTap) {
    final hasFile = base64 != null && base64.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.radiusMd,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasFile
              ? AppTheme.success.withOpacity(0.05)
              : AppTheme.background,
          border: Border.all(
            color: hasFile
                ? AppTheme.success.withOpacity(0.3)
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
            if (hasFile)
              const Text(
                'تم الاختيار',
                style: TextStyle(
                  color: AppTheme.success,
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
