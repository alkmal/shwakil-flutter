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
      if (!mounted) {
        return;
      }
      setState(() {
        _locations = data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isLoading = false);
      await AppAlertService.showError(
        context,
        title: context.loc.text('تعذر تحميل الفروع', 'Could not load branches'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _showLocationDialog({Map<String, dynamic>? location}) async {
    final l = context.loc;
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
                title: l.text('بيانات ناقصة', 'Missing data'),
                message: l.text(
                  'اسم الفرع والعنوان مطلوبان.',
                  'Branch name and address are required.',
                ),
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
              if (!dialogContext.mounted) {
                return;
              }
              Navigator.pop(dialogContext);
              if (!mounted) {
                return;
              }
              setState(() => _locations = data);
            } catch (error) {
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() => isSaving = false);
              await AppAlertService.showError(
                dialogContext,
                title: l.text('تعذر الحفظ', 'Could not save'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(
              location == null
                  ? l.text('إضافة فرع', 'Add branch')
                  : l.text('تعديل الفرع', 'Edit branch'),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: l.text('اسم الفرع', 'Branch name'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        labelText: l.text('العنوان', 'Address'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: l.text('الهاتف', 'Phone'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: InputDecoration(
                        labelText: l.text('النوع', 'Type'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            decoration: InputDecoration(
                              labelText: l.text('خط العرض', 'Latitude'),
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
                            decoration: InputDecoration(
                              labelText: l.text('خط الطول', 'Longitude'),
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
                      decoration: InputDecoration(
                        labelText: l.text('ترتيب الظهور', 'Display order'),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      title: Text(l.text('مفعل', 'Active')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(l.text('إلغاء', 'Cancel')),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(
                  isSaving
                      ? l.text('جارٍ الحفظ...', 'Saving...')
                      : l.text('حفظ', 'Save'),
                ),
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
    final l = context.loc;
    try {
      final data = await _apiService.deleteAdminSupportedLocation(
        location['id'].toString(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _locations = data);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await AppAlertService.showError(
        context,
        title: l.text('تعذر الحذف', 'Could not delete'),
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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l.text('الفروع والمواقع', 'Branches & Locations'))),
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
                        l.text('الفروع والمواقع', 'Branches & locations'),
                        style: AppTheme.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.text(
                          'إدارة المواقع شاشة مستقلة الآن، ولا تُجلب إلا عند فتحها.',
                          'Location management now lives in a dedicated screen and loads only when opened.',
                        ),
                        style: AppTheme.bodyAction.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                AdminSectionHeader(
                  title: l.text('الفروع المدعومة', 'Supported branches'),
                  subtitle: l.text(
                    'أضف أو عدل المواقع من شاشة مخصصة وسريعة.',
                    'Add or edit locations from a dedicated fast screen.',
                  ),
                  icon: Icons.map_rounded,
                  trailing: ShwakelButton(
                    label: l.text('إضافة فرع', 'Add branch'),
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
