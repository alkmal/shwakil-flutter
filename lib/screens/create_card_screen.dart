import 'package:flutter/material.dart';
import '../models/index.dart';
import '../services/index.dart';
import '../utils/app_theme.dart';
import '../utils/currency_formatter.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class CreateCardScreen extends StatefulWidget {
  const CreateCardScreen({super.key});

  @override
  State<CreateCardScreen> createState() => _CreateCardScreenState();
}

class _CreateCardScreenState extends State<CreateCardScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final PDFService _pdfService = PDFService();
  final TextEditingController _amountC = TextEditingController();
  final TextEditingController _qtyC = TextEditingController(text: '1');
  final TextEditingController _titleC = TextEditingController(text: 'شواكل');
  final TextEditingController _stampC = TextEditingController(
    text: 'صالح للتداول',
  );

  bool _isLoading = false;
  bool _isLoadingUser = true;
  bool _showLogo = true;
  bool _showStamp = true;
  bool _useAccountLogo = true;
  String _cardType = 'standard';
  String _visibilityScope = 'general';
  Map<String, dynamic>? _user;
  List<VirtualCard> _recent = [];
  List<Map<String, dynamic>> _selectedUsers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountC.dispose();
    _qtyC.dispose();
    _titleC.dispose();
    _stampC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final user = await _authService.currentUser();
      if (!mounted) {
        return;
      }
      setState(() {
        _user = user;
        final accountName =
            user?['fullName']?.toString().trim().isNotEmpty == true
            ? user!['fullName'].toString().trim()
            : 'شواكل';
        if (_titleC.text.trim().isEmpty || _titleC.text.trim() == 'شواكل') {
          _titleC.text = accountName;
        }
        _useAccountLogo =
            user?['printLogoUrl']?.toString().trim().isNotEmpty == true;
        _isLoadingUser = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  Map<String, dynamic> get _permissions =>
      Map<String, dynamic>.from(_user?['permissions'] as Map? ?? const {});

  bool get _canIssuePrivateCards =>
      _permissions['canIssuePrivateCards'] == true;

  bool get _hasAccountLogo =>
      _user?['printLogoUrl']?.toString().trim().isNotEmpty == true;

  List<DropdownMenuItem<String>> get _cardTypeItems => const [
    DropdownMenuItem(value: 'standard', child: Text('بطاقة رصيد مالية')),
    DropdownMenuItem(
      value: 'single_use',
      child: Text('بطاقة استخدام لمرة واحدة'),
    ),
  ];

  Future<void> _create() async {
    final amount = double.tryParse(_amountC.text) ?? 0;
    final quantity = int.tryParse(_qtyC.text) ?? 0;
    final isStandard = _cardType == 'standard';
    final isPrivate = _visibilityScope == 'restricted';

    if (quantity <= 0 || (isStandard && amount <= 0)) {
      await AppAlertService.showError(
        context,
        title: 'بيانات غير مكتملة',
        message: 'يرجى إدخال بيانات إصدار صحيحة قبل المتابعة.',
      );
      return;
    }

    if (isPrivate && _selectedUsers.isEmpty) {
      await AppAlertService.showError(
        context,
        title: 'البطاقة الخاصة',
        message: 'اختر مستخدمًا واحدًا على الأقل لإنشاء بطاقة خاصة.',
      );
      return;
    }

    final typeLabel = _cardType == 'single_use'
        ? 'استخدام لمرة واحدة'
        : 'رصيد مالي';
    final visibilityLabel = isPrivate ? 'خاصة' : 'عامة';
    final valueLabel = isStandard
        ? CurrencyFormatter.ils(amount)
        : 'بدون قيمة مالية';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد إصدار البطاقات'),
        content: Text(
          'سيتم إصدار $quantity بطاقة.\n'
          'النوع: $typeLabel\n'
          'الإتاحة: $visibilityLabel\n'
          'القيمة: $valueLabel\n'
          '${isPrivate ? 'عدد المستفيدين المحددين: ${_selectedUsers.length}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ShwakelButton(
            label: 'إصدار الآن',
            onPressed: () => Navigator.pop(dialogContext, true),
            width: 140,
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final cards = await _apiService.issueCards(
        value: amount,
        quantity: quantity,
        cardType: _cardType,
        visibilityScope: _visibilityScope,
        allowedUserIds: _selectedUsers
            .map((user) => user['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _recent = cards;
        _isLoading = false;
      });
      await _load();
      if (mounted) {
        _showSuccess(cards);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: 'تعذر الإصدار',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _printCards(List<VirtualCard> cards) async {
    final printedBy = _user?['fullName']?.toString().trim().isNotEmpty == true
        ? _user!['fullName'].toString().trim()
        : _user?['username']?.toString();

    final settings = CardDesignSettings(
      showLogo: _showLogo,
      showStamp: _showStamp,
      logoText: _titleC.text.trim().isEmpty ? 'شواكل' : _titleC.text.trim(),
      stampText: _stampC.text.trim().isEmpty
          ? 'صالح للتداول'
          : _stampC.text.trim(),
    );
    settings.logoUrl = (_showLogo && _useAccountLogo)
        ? (_user?['printLogoUrl'])?.toString()
        : null;
    _pdfService.setDesignSettings(settings);
    await _pdfService.printCards(cards, printedBy: printedBy);
  }

  void _showSuccess(List<VirtualCard> cards) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تم الإصدار بنجاح'),
        content: Text(
          'تم إنشاء ${cards.length} بطاقة بنجاح. هل تريد إرسالها إلى الطابعة الآن؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('لاحقًا'),
          ),
          ShwakelButton(
            label: 'بدء الطباعة',
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _printCards(cards);
            },
            width: 150,
          ),
        ],
      ),
    );
  }

  Future<void> _pickPrivateUsers() async {
    final results = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        final searchController = TextEditingController();
        final selected = List<Map<String, dynamic>>.from(_selectedUsers);
        List<Map<String, dynamic>> results = [];
        bool loading = false;

        Future<void> searchUsers(
          StateSetter setModalState,
          String query,
        ) async {
          setModalState(() => loading = true);
          try {
            results = await _apiService.searchUsers(query);
          } catch (_) {
            results = [];
          } finally {
            setModalState(() => loading = false);
          }
        }

        bool isSelected(Map<String, dynamic> user) {
          final id = user['id']?.toString();
          return selected.any((item) => item['id']?.toString() == id);
        }

        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: const Text('اختيار مستفيدي البطاقة الخاصة'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'ابحث باسم المستخدم أو الرقم',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: loading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                    onChanged: (value) => searchUsers(setModalState, value),
                  ),
                  const SizedBox(height: 16),
                  if (selected.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selected.map((user) {
                        return Chip(
                          label: Text('@${user['username'] ?? user['id']}'),
                          onDeleted: () {
                            setModalState(() {
                              selected.removeWhere(
                                (item) =>
                                    item['id']?.toString() ==
                                    user['id']?.toString(),
                              );
                            });
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: results.map((user) {
                        final selectedNow = isSelected(user);
                        return CheckboxListTile(
                          value: selectedNow,
                          title: Text(user['username']?.toString() ?? 'مستخدم'),
                          subtitle: Text('المعرف: ${user['id'] ?? '-'}'),
                          onChanged: (value) {
                            setModalState(() {
                              if (value == true && !selectedNow) {
                                selected.add(user);
                              } else if (value == false) {
                                selected.removeWhere(
                                  (item) =>
                                      item['id']?.toString() ==
                                      user['id']?.toString(),
                                );
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              ShwakelButton(
                label: 'اعتماد',
                width: 120,
                onPressed: () => Navigator.pop(dialogContext, selected),
              ),
            ],
          ),
        );
      },
    );

    if (results == null || !mounted) {
      return;
    }

    setState(() => _selectedUsers = results);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('إصدار بطاقات جديدة')),
      drawer: const AppSidebar(),
      body: SingleChildScrollView(
        child: ResponsiveScaffoldContainer(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //   ShwakelPageHeader(
              //     eyebrow: 'إنشاء وطباعة',
              //     title: 'صمّم الدفعة الجديدة قبل إصدارها',
              //     subtitle:
              //         'أعدنا ترتيب الشاشة لتجمع بيانات الإصدار وتخصيص الطباعة في عرض حديث وواضح، مع نصوص أخف وأنسب للشاشات.',
              //     badges: [
              //       ShwakelInfoBadge(
              //         icon: Icons.account_balance_wallet_rounded,
              //         label: 'الرصيد ${CurrencyFormatter.ils(_printBal)}',
              //       ),
              //       const ShwakelInfoBadge(
              //         icon: Icons.auto_awesome_rounded,
              //         label: 'تصميم طباعة مخصص',
              //         color: AppTheme.secondary,
              //       ),
              //     ],
              //   ),
              //   const SizedBox(height: 20),
              _buildHero(),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 980;
                  if (!isWide) {
                    return Column(
                      children: [
                        _buildForm(),
                        const SizedBox(height: 20),
                        _buildDesignSettings(),
                        const SizedBox(height: 20),
                        _buildRecent(),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildForm()),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            _buildDesignSettings(),
                            const SizedBox(height: 20),
                            _buildRecent(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      gradient: AppTheme.primaryGradient,
      withBorder: false,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: AppTheme.radiusMd,
            ),
            child: const Icon(
              Icons.add_card_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إصدار بطاقات رقمية بتنسيق احترافي',
                  style: AppTheme.h2.copyWith(
                    color: Colors.white,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'اضبط القيمة والكمية ونوع البطاقة ثم خصص العنوان والختم والشعار قبل إرسال الدفعة إلى الطابعة.',
                  style: AppTheme.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('بيانات الإصدار', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'اختر النوع والكمية والقيمة ثم حدد نطاق ظهور البطاقة.',
            style: AppTheme.bodyAction.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (_cardTypeItems.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _cardType,
              decoration: const InputDecoration(
                labelText: 'نوع البطاقة',
                prefixIcon: Icon(Icons.category_rounded),
              ),
              items: _cardTypeItems,
              onChanged: (value) =>
                  setState(() => _cardType = value ?? 'standard'),
            ),
            const SizedBox(height: 16),
          ],
          if (_cardType == 'standard')
            TextField(
              controller: _amountC,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'قيمة البطاقة (₪)',
                prefixIcon: Icon(Icons.money_rounded),
              ),
            ),
          if (_cardType == 'single_use')
            ShwakelCard(
              padding: const EdgeInsets.all(16),
              color: AppTheme.secondary.withValues(alpha: 0.06),
              borderColor: AppTheme.secondary.withValues(alpha: 0.15),
              child: Text(
                'بطاقة الاستخدام لمرة واحدة لا تحتاج إلى قيمة مالية، وسيظهر نوعها بوضوح داخل الطباعة.',
                style: AppTheme.bodyText.copyWith(fontSize: 14),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'عدد البطاقات',
              prefixIcon: Icon(Icons.pin_rounded),
            ),
          ),
          if (_canIssuePrivateCards) ...[
            const SizedBox(height: 24),
            Text('إتاحة البطاقة', style: AppTheme.bodyBold),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'general',
                  icon: Icon(Icons.public_rounded),
                  label: Text('عامة'),
                ),
                ButtonSegment<String>(
                  value: 'restricted',
                  icon: Icon(Icons.lock_rounded),
                  label: Text('خاصة'),
                ),
              ],
              selected: {_visibilityScope},
              onSelectionChanged: (selection) {
                setState(() {
                  _visibilityScope = selection.first;
                  if (_visibilityScope != 'restricted') {
                    _selectedUsers = [];
                  }
                });
              },
            ),
          ],
          if (_canIssuePrivateCards && _visibilityScope == 'restricted') ...[
            const SizedBox(height: 20),
            ShwakelCard(
              padding: const EdgeInsets.all(20),
              color: AppTheme.warning.withValues(alpha: 0.05),
              borderColor: AppTheme.warning.withValues(alpha: 0.15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مستفيدو البطاقة الخاصة', style: AppTheme.bodyBold),
                  const SizedBox(height: 8),
                  Text(
                    'لن تظهر هذه البطاقات إلا للمستخدمين الذين تحددهم هنا.',
                    style: AppTheme.caption.copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedUsers.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedUsers.map((user) {
                        return Chip(
                          label: Text('@${user['username'] ?? user['id']}'),
                          onDeleted: () {
                            setState(() {
                              _selectedUsers.removeWhere(
                                (item) =>
                                    item['id']?.toString() ==
                                    user['id']?.toString(),
                              );
                            });
                          },
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 12),
                  ShwakelButton(
                    label: _selectedUsers.isEmpty
                        ? 'اختيار المستخدمين'
                        : 'تعديل المستخدمين',
                    icon: Icons.group_add_rounded,
                    isSecondary: true,
                    onPressed: _pickPrivateUsers,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          ShwakelButton(
            label: 'توليد وإصدار الدفعة',
            icon: Icons.verified_user_rounded,
            onPressed: _create,
            isLoading: _isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildDesignSettings() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تخصيص الطباعة', style: AppTheme.h3),
          const SizedBox(height: 8),
          Text(
            'أعد تفعيل العنوان والختم والشعار المخصص قبل الطباعة، مع تصغير النصوص لتبدو أنظف على البطاقات.',
            style: AppTheme.bodyAction.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleC,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'عنوان البطاقة',
              prefixIcon: Icon(Icons.title_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _stampC,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'نص الختم',
              prefixIcon: Icon(Icons.approval_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _showLogo,
            title: const Text('إظهار الشعار'),
            subtitle: Text(
              _hasAccountLogo
                  ? 'سيتم استخدام شعار الحساب المرفوع إذا كان مفعّلًا'
                  : 'سيتم استخدام شعار التطبيق الافتراضي',
              style: AppTheme.caption.copyWith(fontSize: 12),
            ),
            onChanged: (value) => setState(() => _showLogo = value),
          ),
          if (_hasAccountLogo)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _useAccountLogo,
              title: const Text('استخدام شعار الحساب'),
              subtitle: Text(
                'يمكنك تغيير الشعار من إعدادات الحساب عند الحاجة',
                style: AppTheme.caption.copyWith(fontSize: 12),
              ),
              onChanged: _showLogo
                  ? (value) => setState(() => _useAccountLogo = value)
                  : null,
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _showStamp,
            title: const Text('إظهار الختم'),
            subtitle: Text(
              'يعرض بخط أخف وحجم أصغر ليبقى التصميم متوازنًا',
              style: AppTheme.caption.copyWith(fontSize: 12),
            ),
            onChanged: (value) => setState(() => _showStamp = value),
          ),
          const SizedBox(height: 14),
          _buildDesignPreview(),
        ],
      ),
    );
  }

  Widget _buildDesignPreview() {
    final title = _titleC.text.trim().isEmpty ? 'شواكل' : _titleC.text.trim();
    final stamp = _stampC.text.trim().isEmpty
        ? 'صالح للتداول'
        : _stampC.text.trim();
    final amount = double.tryParse(_amountC.text) ?? 0;
    final valueLabel = _cardType == 'single_use'
        ? 'استخدام لمرة واحدة'
        : CurrencyFormatter.ils(amount);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBF2), Color(0xFFF2FFFC)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: AppTheme.radiusLg,
        border: Border.all(color: AppTheme.border),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.bodyBold.copyWith(
                        fontSize: 16,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  if (_showLogo)
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Icon(
                        _useAccountLogo
                            ? Icons.image_rounded
                            : Icons.shield_rounded,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _cardType == 'single_use'
                    ? 'بطاقة دخول أو استلام'
                    : 'بطاقة رقمية للاستخدام الداخلي',
                style: AppTheme.caption.copyWith(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                valueLabel,
                style: AppTheme.h2.copyWith(
                  fontSize: 20,
                  color: AppTheme.secondary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  '|| ||| || |||| |||',
                  style: AppTheme.caption.copyWith(
                    fontSize: 14,
                    letterSpacing: 2,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _visibilityScope == 'restricted'
                          ? 'بطاقة خاصة'
                          : 'بطاقة عامة',
                      style: AppTheme.caption.copyWith(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'نص أصغر وأنظف',
                    style: AppTheme.caption.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          if (_showStamp)
            Positioned(
              left: 0,
              top: 66,
              child: Transform.rotate(
                angle: -0.22,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.55),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    stamp,
                    style: AppTheme.caption.copyWith(
                      fontSize: 10,
                      color: AppTheme.error.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecent() {
    return ShwakelCard(
      padding: const EdgeInsets.all(24),
      color: AppTheme.secondary.withValues(alpha: 0.05),
      child: Column(
        children: [
          const Icon(
            Icons.history_rounded,
            color: AppTheme.secondary,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text('الإصدار الأخير', style: AppTheme.h3.copyWith(fontSize: 18)),
          const SizedBox(height: 20),
          _buildRecentRow('عدد البطاقات', '${_recent.length} بطاقة'),
          const SizedBox(height: 8),
          _buildRecentRow(
            'نوع الإتاحة',
            _recent.isNotEmpty
                ? (_recent.first.isPrivate ? 'خاصة' : 'عامة')
                : '-',
          ),
          const SizedBox(height: 8),
          _buildRecentRow(
            'قيمة الواحدة',
            _recent.isNotEmpty
                ? CurrencyFormatter.ils(_recent.first.value)
                : CurrencyFormatter.ils(0),
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 20),
            ShwakelButton(
              label: 'إعادة طباعة الدفعة',
              icon: Icons.print_rounded,
              isSecondary: true,
              onPressed: () => _printCards(_recent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTheme.bodyAction.copyWith(fontSize: 14)),
        Text(value, style: AppTheme.bodyBold.copyWith(fontSize: 14)),
      ],
    );
  }
}
