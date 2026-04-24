import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/admin/admin_location_card.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/rejection_reason_dialog.dart';
import '../widgets/responsive_scaffold_container.dart';
import '../widgets/shwakel_card.dart';

class AdminLocationsScreen extends StatefulWidget {
  const AdminLocationsScreen({super.key});

  @override
  State<AdminLocationsScreen> createState() => _AdminLocationsScreenState();
}

class _AdminLocationsScreenState extends State<AdminLocationsScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _locations = const [];
  bool _isLoading = true;
  bool _isAuthorized = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = await _authService.currentUser();
      final permissions = AppPermissions.fromUser(currentUser);
      if (!permissions.canManageLocations) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isAuthorized = false;
          _isLoading = false;
        });
        return;
      }
      final data = await _apiService.getAdminSupportedLocations();
      if (!mounted) {
        return;
      }
      setState(() {
        _isAuthorized = true;
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
        title: context.loc.tr('screens_admin_locations_screen.001'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _showLocationDialog({Map<String, dynamic>? location}) async {
    if (!_isAuthorized) {
      return;
    }
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
                title: l.tr('screens_admin_locations_screen.002'),
                message: l.tr('screens_admin_locations_screen.required_fields'),
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
                title: l.tr('screens_admin_locations_screen.003'),
                message: ErrorMessageService.sanitize(error),
              );
            }
          }

          return AlertDialog(
            title: Text(
              location == null
                  ? l.tr('screens_admin_locations_screen.004')
                  : l.tr('screens_admin_locations_screen.005'),
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_admin_locations_screen.006'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_admin_locations_screen.007'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_admin_locations_screen.008'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: InputDecoration(
                        labelText: l.tr('screens_admin_locations_screen.009'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            decoration: InputDecoration(
                              labelText: l.tr(
                                'screens_admin_locations_screen.010',
                              ),
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
                              labelText: l.tr(
                                'screens_admin_locations_screen.011',
                              ),
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
                        labelText: l.tr('screens_admin_locations_screen.012'),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      title: Text(l.tr('screens_admin_locations_screen.013')),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: Text(l.tr('screens_admin_locations_screen.014')),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : submit,
                child: Text(
                  isSaving
                      ? l.tr('screens_admin_locations_screen.015')
                      : l.tr('screens_admin_locations_screen.016'),
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
        title: l.tr('screens_admin_locations_screen.017'),
        message: ErrorMessageService.sanitize(error),
      );
    }
  }

  Future<void> _approveLocation(Map<String, dynamic> location) async {
    final l = context.loc;
    setState(() => _busyId = location['id']?.toString());
    try {
      final data = await _apiService.approveAdminSupportedLocation(
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
        title: l.tr('screens_admin_locations_screen.028'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  Future<void> _rejectLocation(Map<String, dynamic> location) async {
    final l = context.loc;
    final reason = await showRejectionReasonDialog(
      context,
      title: l.tr('shared.rejection_reason_label'),
      confirmText: l.tr('shared.confirm_rejection'),
    );
    if (reason == null) {
      return;
    }

    setState(() => _busyId = location['id']?.toString());
    try {
      final data = await _apiService.rejectAdminSupportedLocation(
        location['id'].toString(),
        reason: reason,
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
        title: l.tr('screens_admin_locations_screen.029'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
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
          title: Text(l.tr('screens_admin_locations_screen.003')),
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
                  l.tr('screens_admin_locations_screen.022'),
                  style: AppTheme.h3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l.tr('screens_admin_locations_screen.018')),
        actions: [
          IconButton(
            tooltip: l.tr('screens_admin_locations_screen.023'),
            onPressed: _showLocationDialog,
            icon: const Icon(Icons.add_location_alt_rounded),
          ),
          IconButton(
            tooltip: l.tr('screens_admin_locations_screen.024'),
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          child: ResponsiveScaffoldContainer(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.tr(
                    'screens_admin_locations_screen.025',
                    params: {'count': '${_locations.length}'},
                  ),
                  style: AppTheme.caption,
                ),
                const SizedBox(height: 14),
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
                        mainAxisExtent: 220,
                      ),
                      itemCount: _locations.length,
                      itemBuilder: (context, index) => AdminLocationCard(
                        location: _locations[index],
                        isSaving: _busyId == _locations[index]['id']?.toString(),
                        onEdit: () =>
                            _showLocationDialog(location: _locations[index]),
                        onDelete: () => _deleteLocation(_locations[index]),
                        onApprove:
                            _locations[index]['status'] == 'pending'
                            ? () => _approveLocation(_locations[index])
                            : null,
                        onReject:
                            _locations[index]['status'] == 'pending'
                            ? () => _rejectLocation(_locations[index])
                            : null,
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

  Future<void> _showHelpDialog() async {
    final l = context.loc;
    await AppAlertService.showInfo(
      context,
      title: l.tr('screens_admin_locations_screen.026'),
      message: l.tr('screens_admin_locations_screen.027'),
    );
  }
}
