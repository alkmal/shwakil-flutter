import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_location_card.dart';
import '../widgets/admin/admin_section_header.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AdminLocationsScreen extends StatefulWidget {
  const AdminLocationsScreen({super.key});

  @override
  State<AdminLocationsScreen> createState() => _AdminLocationsScreenState();
}

class _AdminLocationsScreenState extends State<AdminLocationsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _locations = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getAdminSupportedLocations();
      if (!mounted) return;
      setState(() {
        _locations = data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: 'تعذر تحميل الفروع',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _showLocationDialog({Map<String, dynamic>? location}) async {
    final titleController = TextEditingController(
      text: location?['title']?.toString() ?? '',
    );
    final addressController = TextEditingController(
      text: location?['address']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: location?['phone']?.toString() ?? '',
    );
    final typeController = TextEditingController(
      text: location?['type']?.toString() ?? 'branch',
    );
    final latController = TextEditingController(
      text: (location?['latitude'] ?? 31.5).toString(),
    );
    final lngController = TextEditingController(
      text: (location?['longitude'] ?? 34.47).toString(),
    );
    final sortOrderController = TextEditingController(
      text: (location?['sortOrder'] ?? 0).toString(),
    );
    var isActive = location?['isActive'] != false;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            if (titleController.text.trim().isEmpty ||
                addressController.text.trim().isEmpty) {
              await AppAlertService.showError(
                dialogContext,
                title: 'بيانات ناقصة',
                message: 'اسم الفرع والعنوان مطلوبان.',
              );
              return;
            }
            setDialogState(() => isSaving = true);
            try {
              final data = await _apiService.saveAdminSupportedLocation(
                locationId: location?['id']?.toString(),
                title: titleController.text,
                address: addressController.text,
                phone: phoneController.text,
                type: typeController.text.trim().isEmpty
                    ? 'branch'
                    : typeController.text.trim(),
                latitude: double.tryParse(latController.text) ?? 31.5,
                longitude: double.tryParse(lngController.text) ?? 34.47,
                isActive: isActive,
                sortOrder: int.tryParse(sortOrderController.text) ?? 0,
              );
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              setState(() => _locations = data);
            } catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: 'تعذر الحفظ',
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(location == null ? 'إضافة فرع' : 'تعديل الفرع'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'اسم الفرع'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'العنوان'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'الهاتف'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'النوع'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            decoration: const InputDecoration(
                              labelText: 'خط العرض',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: lngController,
                            decoration: const InputDecoration(
                              labelText: 'خط الطول',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sortOrderController,
                      decoration: const InputDecoration(
                        labelText: 'ترتيب الظهور',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      title: const Text('مفعل'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(isSaving ? 'جارٍ الحفظ...' : 'حفظ'),
              ),
            ],
          );
        },
      ),
    );

    titleController.dispose();
    addressController.dispose();
    phoneController.dispose();
    typeController.dispose();
    latController.dispose();
    lngController.dispose();
    sortOrderController.dispose();
  }

  Future<void> _deleteLocation(Map<String, dynamic> location) async {
    try {
      final data = await _apiService.deleteAdminSupportedLocation(
        location['id'].toString(),
      );
      if (!mounted) return;
      setState(() => _locations = data);
    } catch (error) {
      if (!mounted) return;
      await AppAlertService.showError(
        context,
        title: 'تعذر الحذف',
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('الفروع والمواقع')),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
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
                        'الفروع والمواقع',
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'إدارة المواقع شاشة مستقلة الآن، ولا تُجلب إلا عند فتحها.',
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AdminSectionHeader(
                  title: 'الفروع المدعومة',
                  subtitle: 'أضف أو عدل المواقع من شاشة مخصصة وسريعة.',
                  icon: Icons.map_rounded,
                  trailing: ShwakelButton(
                    label: 'إضافة فرع',
                    icon: Icons.add_location_alt_rounded,
                    onPressed: _showLocationDialog,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 1100
                        ? 3
                        : constraints.maxWidth > 720
                        ? 2
                        : 1;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        mainAxisExtent: 160,
                      ),
                      itemCount: _locations.length,
                      itemBuilder: (context, index) => AdminLocationCard(
                        location: _locations[index],
                        onEdit: () =>
                            _showLocationDialog(location: _locations[index]),
                        onDelete: () => _deleteLocation(_locations[index]),
                        onMap: () {},
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
