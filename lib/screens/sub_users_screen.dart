import 'package:flutter/material.dart';

import '../services/index.dart';
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
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  List<Map<String, dynamic>> _subUsers = const [];
  Map<String, dynamic>? _editing;
  bool _loading = true;
  bool _saving = false;
  bool _isDisabled = false;
  final Map<String, bool> _permissions = {
    'canViewQuickTransfer': false,
    'canTransfer': false,
    'canScanCards': false,
    'canOfflineCardScan': false,
    'canRedeemCards': false,
    'canWithdraw': false,
    'canReviewCards': false,
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
      final users = await _api.getSubUsers();
      if (mounted) {
        setState(() {
          _subUsers = users;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppAlertService.showError(
        context,
        title: 'تعذر تحميل التابعين',
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
    if (_usernameController.text.trim().isEmpty ||
        (_editing == null && _passwordController.text.trim().isEmpty)) {
      AppAlertService.showError(
        context,
        title: 'بيانات ناقصة',
        message: 'اسم المستخدم وكلمة المرور مطلوبان عند إنشاء تابع جديد.',
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

    if (confirmed != true) {
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppSidebar(),
      appBar: AppBar(title: const Text('المستخدمون التابعون')),
      body: ResponsiveScaffoldContainer(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildForm(),
                  const SizedBox(height: 16),
                  ..._subUsers.map(_buildSubUserCard),
                ],
              ),
      ),
    );
  }

  Widget _buildForm() {
    return ShwakelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editing == null ? 'إضافة تابع جديد' : 'تعديل تابع',
            style: AppTheme.h3,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _fullNameController,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            enabled: _editing == null,
            decoration: const InputDecoration(labelText: 'اسم المستخدم'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _editing == null
                  ? 'كلمة المرور'
                  : 'كلمة مرور جديدة (اختياري)',
            ),
          ),
          const SizedBox(height: 12),
          _permissionSwitch('الإرسال السريع', 'canTransfer'),
          _permissionSwitch('الاستلام السريع', 'canWithdraw'),
          _permissionSwitch('فحص البطاقات', 'canScanCards'),
          _permissionSwitch('اعتماد البطاقات وسحب رصيدها', 'canRedeemCards'),
          _permissionSwitch(
            'قراءة ومزامنة البطاقات أوفلاين',
            'canOfflineCardScan',
          ),
          if (_editing != null)
            SwitchListTile(
              value: _isDisabled,
              onChanged: (value) => setState(() => _isDisabled = value),
              title: const Text('تعطيل الحساب'),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ShwakelButton(
                  label: _saving ? 'جار الحفظ...' : 'حفظ',
                  onPressed: _saving ? null : _save,
                ),
              ),
              if (_editing != null) ...[
                const SizedBox(width: 10),
                TextButton(onPressed: _resetForm, child: const Text('إلغاء')),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _permissionSwitch(String title, String key) {
    return SwitchListTile(
      value: _permissions[key] ?? false,
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
      title: Text(title),
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
      if (permissions['canOfflineCardScan'] == true) 'أوفلاين',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ShwakelCard(
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline_rounded),
              ),
              title: Text(
                user['fullName']?.toString().trim().isNotEmpty == true
                    ? user['fullName'].toString()
                    : user['username'].toString(),
              ),
              subtitle: Text(
                '@${user['username']} • ${enabledLabels.isEmpty ? 'بدون صلاحيات' : enabledLabels.join('، ')}',
              ),
              trailing: IconButton(
                tooltip: 'تعديل',
                onPressed: () => _edit(user),
                icon: const Icon(Icons.edit_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _transferBalance(user, 'to_sub'),
                    icon: const Icon(Icons.call_made_rounded),
                    label: const Text('إرسال'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _transferBalance(user, 'from_sub'),
                    icon: const Icon(Icons.call_received_rounded),
                    label: const Text('استلام'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
