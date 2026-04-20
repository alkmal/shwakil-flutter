import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class SubUsersScreen extends StatefulWidget {
  const SubUsersScreen({super.key});

  @override
  State<SubUsersScreen> createState() => _SubUsersScreenState();
}

class _SubUsersScreenState extends State<SubUsersScreen> {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  List<Map<String, dynamic>> _subUsers = const [];
  Map<String, dynamic>? _editing;
  bool _loading = true;
  bool _saving = false;
  bool _isDisabled = false;
  bool _canViewSubUsers = false;
  bool _canManageSubUsers = false;
  final Map<String, bool> _permissions = {
    'canViewQuickTransfer': false,
    'canTransfer': false,
    'canScanCards': false,
    'canOfflineCardScan': false,
    'canRedeemCards': false,
    'canWithdraw': false,
    'canReviewCards': false,
  };

  static const Map<String, String> _permissionLabels = {
    'canTransfer': 'الإرسال السريع',
    'canWithdraw': 'الاستلام السريع',
    'canScanCards': 'فحص البطاقات',
    'canRedeemCards': 'اعتماد البطاقات وسحب رصيدها',
    'canOfflineCardScan': 'الفحص والمزامنة أوف لاين',
    'canReviewCards': 'مراجعة البطاقات',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final currentUser = await _auth.currentUser();
      final appPermissions = AppPermissions.fromUser(currentUser);
      if (!appPermissions.canViewSubUsers) {
        if (!mounted) return;
        setState(() {
          _canViewSubUsers = false;
          _canManageSubUsers = false;
          _subUsers = const [];
          _loading = false;
        });
        return;
      }
      final users = await _api.getSubUsers();
      if (!mounted) return;
      setState(() {
        _canViewSubUsers = true;
        _canManageSubUsers = appPermissions.canManageSubUsers;
        _subUsers = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppAlertService.showError(
        context,
        title: 'تعذر تحميل المستخدمين التابعين',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  void _edit(Map<String, dynamic> user) {
    final permissions = Map<String, dynamic>.from(
      user['permissions'] as Map? ?? const {},
    );
    setState(() {
      _editing = user;
      _fullNameController.text = user['fullName']?.toString() ?? '';
      _usernameController.text = user['username']?.toString() ?? '';
      _passwordController.clear();
      _isDisabled = user['isDisabled'] == true;
      for (final key in _permissions.keys) {
        _permissions[key] = permissions[key] == true;
      }
    });
  }

  void _resetForm() {
    setState(() {
      _editing = null;
      _fullNameController.clear();
      _usernameController.clear();
      _passwordController.clear();
      _isDisabled = false;
      for (final key in _permissions.keys) {
        _permissions[key] = false;
      }
    });
  }

  Future<void> _save() async {
    if (!_canManageSubUsers) {
      return;
    }
    if (_usernameController.text.trim().isEmpty ||
        (_editing == null && _passwordController.text.trim().isEmpty)) {
      AppAlertService.showError(
        context,
        title: 'بيانات ناقصة',
        message:
            'اسم المستخدم وكلمة المرور مطلوبان عند إنشاء مستخدم تابع جديد.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final users = _editing == null
          ? await _api.createSubUser(
              fullName: _fullNameController.text,
              username: _usernameController.text,
              password: _passwordController.text,
              permissions: Map<String, bool>.from(_permissions),
            )
          : await _api.updateSubUser(
              subUserId: _editing!['id'].toString(),
              fullName: _fullNameController.text,
              password: _passwordController.text,
              permissions: Map<String, bool>.from(_permissions),
              isDisabled: _isDisabled,
            );
      if (!mounted) return;
      setState(() {
        _subUsers = users;
        _saving = false;
      });
      _resetForm();
      AppAlertService.showSuccess(
        context,
        title: 'تم الحفظ',
        message: 'تم تحديث المستخدمين التابعين بنجاح.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppAlertService.showError(
        context,
        title: 'تعذر الحفظ',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _transferBalance(
    Map<String, dynamic> user,
    String direction,
  ) async {
    if (!_canManageSubUsers) {
      return;
    }
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final title = direction == 'to_sub'
        ? 'تحويل رصيد إلى التابع'
        : 'سحب رصيد من التابع';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'المبلغ'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تنفيذ'),
          ),
        ],
      ),
    );

    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final notes = notesController.text;
    amountController.dispose();
    notesController.dispose();

    if (confirmed != true) return;

    if (amount <= 0) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: 'مبلغ غير صالح',
        message: 'أدخل مبلغًا أكبر من صفر.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final users = await _api.transferSubUserBalance(
        subUserId: user['id'].toString(),
        direction: direction,
        amount: amount,
        notes: notes,
      );
      if (!mounted) return;
      setState(() {
        _subUsers = users;
        _saving = false;
      });
      AppAlertService.showSuccess(
        context,
        title: 'تم التحويل',
        message: 'تم تنفيذ حركة الرصيد بنجاح.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppAlertService.showError(
        context,
        title: 'تعذر التحويل',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  int get _enabledPermissionsCount =>
      _permissions.entries.where((entry) => entry.value).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        drawer: const AppSidebar(),
        appBar: AppBar(title: const Text('المستخدمون التابعون')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_canViewSubUsers) {
      return Scaffold(
        drawer: const AppSidebar(),
        appBar: AppBar(title: const Text('المستخدمون التابعون')),
        body: ResponsiveScaffoldContainer(
          child: Center(
            child: ShwakelCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 44,
                    color: AppTheme.textTertiary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لا تملك صلاحية عرض المستخدمين التابعين',
                    style: AppTheme.h3,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      drawer: const AppSidebar(),
      appBar: AppBar(title: const Text('المستخدمون التابعون')),
      body: ResponsiveScaffoldContainer(
        child: ListView(
          padding: AppTheme.pagePadding(context, top: 18),
          children: [
            _buildHero(),
            const SizedBox(height: 18),
            _buildStatsRow(),
            const SizedBox(height: 18),
            if (_canManageSubUsers) ...[
              _buildForm(),
              const SizedBox(height: 18),
            ] else ...[
              ShwakelCard(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'هذه الشاشة في وضع العرض فقط. يمكنك مراجعة الحسابات التابعة دون إنشاء أو تعديل أو تحويل أرصدة.',
                  style: AppTheme.bodyAction,
                ),
              ),
              const SizedBox(height: 18),
            ],
            _buildUsersSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final isEditing = _editing != null;
    final subtitle = isEditing
        ? 'قم بتعديل بيانات التابع وصلاحياته وإدارة حالته من نفس الشاشة.'
        : 'أنشئ مستخدمين تابعين بصلاحيات دقيقة، ووزع العمل المالي والتشغيلي بوضوح.';

    return ShwakelCard(
      gradient: AppTheme.heroGradient,
      shadowLevel: ShwakelShadowLevel.premium,
      borderColor: Colors.white.withValues(alpha: 0.18),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Text(
              isEditing ? 'وضع التعديل' : 'إدارة الفريق',
              style: AppTheme.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isEditing
                ? 'تحديث التابع الحالي'
                : 'نظّم المستخدمين التابعين باحترافية',
            style: AppTheme.h1.copyWith(
              color: Colors.white,
              fontSize: 26,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: AppTheme.bodyText.copyWith(
              color: AppTheme.textMutedOnDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final activeUsers = _subUsers
        .where((user) => user['isDisabled'] != true)
        .length;
    final disabledUsers = _subUsers.length - activeUsers;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final children = [
          _buildStatCard(
            title: 'إجمالي التابعين',
            value: _subUsers.length.toString(),
            hint: 'الحسابات الفرعية المسجلة',
            icon: Icons.groups_rounded,
            accent: AppTheme.primary,
            background: AppTheme.surface,
          ),
          _buildStatCard(
            title: 'النشطون',
            value: activeUsers.toString(),
            hint: 'جاهزون للعمل حالياً',
            icon: Icons.verified_user_rounded,
            accent: AppTheme.success,
            background: AppTheme.successLight,
          ),
          _buildStatCard(
            title: 'المعطلون',
            value: disabledUsers.toString(),
            hint: 'بحاجة إلى إعادة تفعيل',
            icon: Icons.pause_circle_outline_rounded,
            accent: AppTheme.warning,
            background: AppTheme.warningLight,
          ),
        ];

        if (compact) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String hint,
    required IconData icon,
    required Color accent,
    required Color background,
  }) {
    return ShwakelCard(
      color: background,
      withBorder: true,
      borderColor: accent.withValues(alpha: 0.14),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTheme.caption.copyWith(color: accent)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTheme.h2.copyWith(
                    fontSize: 24,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(hint, style: AppTheme.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return ShwakelCard(
      shadowLevel: ShwakelShadowLevel.medium,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            title: _editing == null ? 'إضافة تابع جديد' : 'تعديل بيانات التابع',
            subtitle: _editing == null
                ? 'أدخل البيانات الأساسية وحدد الصلاحيات التي يحتاجها هذا الحساب.'
                : 'يمكنك تعديل الاسم أو كلمة المرور أو الصلاحيات أو تعطيل الحساب.',
            icon: _editing == null
                ? Icons.person_add_alt_1_rounded
                : Icons.edit_rounded,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildIdentityPanel()),
                    const SizedBox(width: 16),
                    Expanded(flex: 6, child: _buildPermissionsPanel()),
                  ],
                );
              }

              return Column(
                children: [
                  _buildIdentityPanel(),
                  const SizedBox(height: 16),
                  _buildPermissionsPanel(),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _buildActionsRow(),
        ],
      ),
    );
  }

  Widget _buildIdentityPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.cardHighlightGradient,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('البيانات الأساسية', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'هيكل واضح لاسم التابع وبيانات الدخول الخاصة به.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _fullNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'الاسم الكامل',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            enabled: _editing == null,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _editing == null
                  ? 'كلمة المرور'
                  : 'كلمة مرور جديدة - اختياري',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
            ),
          ),
          if (_editing != null) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _isDisabled ? AppTheme.warningLight : AppTheme.surface,
                borderRadius: AppTheme.radiusMd,
                border: Border.all(
                  color: (_isDisabled ? AppTheme.warning : AppTheme.border)
                      .withValues(alpha: 0.25),
                ),
              ),
              child: SwitchListTile(
                value: _isDisabled,
                onChanged: (value) => setState(() => _isDisabled = value),
                title: const Text('تعطيل الحساب'),
                subtitle: Text(
                  _isDisabled
                      ? 'الحساب موقوف مؤقتًا ولن يتمكن من تنفيذ العمليات.'
                      : 'الحساب نشط ويمكنه استخدام الصلاحيات الممنوحة.',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionsPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الصلاحيات التشغيلية', style: AppTheme.h3),
                    const SizedBox(height: 6),
                    Text(
                      'حدد ما يستطيع التابع الوصول إليه داخل التطبيق.',
                      style: AppTheme.caption,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_enabledPermissionsCount مفعل',
                  style: AppTheme.caption.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._permissionLabels.entries.map(
            (entry) => _permissionTile(entry.value, entry.key),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsRow() {
    final isPhone = MediaQuery.sizeOf(context).width < 700;

    if (isPhone) {
      return Column(
        children: [
          ShwakelButton(
            label: _saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات',
            icon: Icons.save_outlined,
            gradient: AppTheme.primaryGradient,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_editing != null) ...[
            const SizedBox(height: 10),
            ShwakelButton(
              label: 'إلغاء التعديل',
              icon: Icons.close_rounded,
              isSecondary: true,
              onPressed: _resetForm,
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: ShwakelButton(
            label: _saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات',
            icon: Icons.save_outlined,
            gradient: AppTheme.primaryGradient,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
        if (_editing != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ShwakelButton(
              label: 'إلغاء التعديل',
              icon: Icons.close_rounded,
              isSecondary: true,
              onPressed: _resetForm,
            ),
          ),
        ],
      ],
    );
  }

  Widget _permissionTile(String title, String key) {
    final enabled = _permissions[key] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: enabled
            ? AppTheme.primarySoft.withValues(alpha: 0.5)
            : Colors.white,
        borderRadius: AppTheme.radiusMd,
        border: Border.all(
          color: enabled
              ? AppTheme.primary.withValues(alpha: 0.18)
              : AppTheme.borderLight,
        ),
      ),
      child: SwitchListTile(
        value: enabled,
        onChanged: (value) {
          setState(() {
            _permissions[key] = value;
            if (key == 'canTransfer') {
              _permissions['canViewQuickTransfer'] = value;
            }
            if (key == 'canRedeemCards') {
              _permissions['canScanCards'] =
                  value || (_permissions['canScanCards'] ?? false);
            }
          });
        },
        title: Text(title, style: AppTheme.bodyBold.copyWith(fontSize: 15)),
        subtitle: Text(_permissionHint(key), style: AppTheme.caption),
      ),
    );
  }

  String _permissionHint(String key) {
    switch (key) {
      case 'canTransfer':
        return 'إرسال الرصيد بسرعة من الحساب الرئيسي إلى التابع.';
      case 'canWithdraw':
        return 'استلام الرصيد أو سحبه من حساب التابع إلى الرئيسي.';
      case 'canScanCards':
        return 'الوصول إلى شاشة فحص البطاقات وقراءة نتائجها.';
      case 'canRedeemCards':
        return 'اعتماد البطاقة وتنفيذ حركة السحب مباشرة.';
      case 'canOfflineCardScan':
        return 'السماح بالفحص والمزامنة في وضع أوف لاين عند توفره.';
      case 'canReviewCards':
        return 'استعراض البطاقات ونتائج المراجعة والمتابعة.';
      default:
        return 'صلاحية تشغيلية داخل التطبيق.';
    }
  }

  Widget _buildUsersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
          title: 'قائمة التابعين',
          subtitle: _subUsers.isEmpty
              ? 'لا يوجد مستخدمون تابعون حتى الآن.'
              : 'يمكنك مراجعة الصلاحيات، تعديل الحساب، أو تنفيذ حركة رصيد مباشرة.',
          icon: Icons.manage_accounts_rounded,
        ),
        const SizedBox(height: 14),
        if (_subUsers.isEmpty)
          _buildEmptyState()
        else
          ..._subUsers.map(_buildSubUserCard),
      ],
    );
  }

  Widget _buildEmptyState() {
    return ShwakelCard(
      color: AppTheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.group_add_rounded,
              color: AppTheme.primary,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text('لا يوجد مستخدمون تابعون حالياً', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'ابدأ بإنشاء أول مستخدم تابع لتوزيع المهام والصلاحيات داخل النظام.',
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSubUserCard(Map<String, dynamic> user) {
    final permissions = Map<String, dynamic>.from(
      user['permissions'] as Map? ?? const {},
    );
    final enabledLabels = <String>[
      if (permissions['canTransfer'] == true) 'إرسال سريع',
      if (permissions['canWithdraw'] == true) 'استلام سريع',
      if (permissions['canScanCards'] == true) 'فحص',
      if (permissions['canRedeemCards'] == true) 'اعتماد',
      if (permissions['canOfflineCardScan'] == true) 'أوف لاين',
      if (permissions['canReviewCards'] == true) 'مراجعة',
    ];
    final fullName = user['fullName']?.toString().trim();
    final displayName = (fullName?.isNotEmpty ?? false)
        ? fullName!
        : user['username'].toString();
    final isDisabled = user['isDisabled'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ShwakelCard(
        shadowLevel: ShwakelShadowLevel.medium,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 720;
                final statusChip = _buildStatusChip(isDisabled);
                final identity = Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: isDisabled
                              ? LinearGradient(
                                  colors: [
                                    AppTheme.warning.withValues(alpha: 0.9),
                                    AppTheme.highlight,
                                  ],
                                )
                              : AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: AppTheme.h3.copyWith(fontSize: 17),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${user['username']}',
                              style: AppTheme.caption.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: enabledLabels.isEmpty
                                  ? [
                                      _buildPermissionChip(
                                        label: 'بدون صلاحيات',
                                        background: AppTheme.surfaceVariant,
                                        foreground: AppTheme.textSecondary,
                                      ),
                                    ]
                                  : enabledLabels
                                        .map(
                                          (label) => _buildPermissionChip(
                                            label: label,
                                            background: AppTheme.primarySoft,
                                            foreground: AppTheme.primary,
                                          ),
                                        )
                                        .toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          const SizedBox(width: 12),
                          statusChip,
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: IconButton.filledTonal(
                          tooltip: 'تعديل',
                          onPressed: _canManageSubUsers
                              ? () => _edit(user)
                              : null,
                          icon: const Icon(Icons.edit_rounded),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        statusChip,
                        const SizedBox(height: 10),
                        IconButton.filledTonal(
                          tooltip: 'تعديل',
                          onPressed: _canManageSubUsers
                              ? () => _edit(user)
                              : null,
                          icon: const Icon(Icons.edit_rounded),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || !_canManageSubUsers
                        ? null
                        : () => _transferBalance(user, 'to_sub'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.radiusMd,
                      ),
                    ),
                    icon: const Icon(Icons.call_made_rounded),
                    label: const Text('إرسال رصيد'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || !_canManageSubUsers
                        ? null
                        : () => _transferBalance(user, 'from_sub'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide(
                        color: AppTheme.accent.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.radiusMd,
                      ),
                    ),
                    icon: const Icon(Icons.call_received_rounded),
                    label: const Text('استلام رصيد'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isDisabled) {
    final color = isDisabled ? AppTheme.warning : AppTheme.success;
    final background = isDisabled
        ? AppTheme.warningLight
        : AppTheme.successLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDisabled
                ? Icons.pause_circle_outline_rounded
                : Icons.check_circle_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            isDisabled ? 'معطل' : 'نشط',
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionChip({
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSectionHeading({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: AppTheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.h2.copyWith(fontSize: 20)),
              const SizedBox(height: 4),
              Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
