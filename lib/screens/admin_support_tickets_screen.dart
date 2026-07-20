import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/admin/admin_load_error_card.dart';
import '../widgets/shwakel_button.dart';
import '../widgets/shwakel_card.dart';

class AdminSupportTicketsScreen extends StatefulWidget {
  const AdminSupportTicketsScreen({super.key});

  @override
  State<AdminSupportTicketsScreen> createState() =>
      _AdminSupportTicketsScreenState();
}

class _AdminSupportTicketsScreenState extends State<AdminSupportTicketsScreen> {
  final ApiService _api = ApiService();
  final AuthService _auth = AuthService();
  final TextEditingController _message = TextEditingController();
  final TextEditingController _newUserId = TextEditingController();
  final TextEditingController _newName = TextEditingController();
  final TextEditingController _newWhatsapp = TextEditingController();
  final TextEditingController _newTitle = TextEditingController();
  final TextEditingController _newDetails = TextEditingController();
  final TextEditingController _statusCustom = TextEditingController();
  final TextEditingController _statusNote = TextEditingController();
  final TextEditingController _editTitle = TextEditingController();
  final TextEditingController _followerUserId = TextEditingController();
  List<Map<String, dynamic>> _tickets = const [];
  List<Map<String, dynamic>> _statuses = const [];
  Map<String, dynamic>? _selected;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  bool _loading = true;
  bool _authorized = false;
  String? _loadError;
  bool _busy = false;
  bool _ticketLoading = false;
  bool _chatRouteOpen = false;
  StateSetter? _chatRouteSetState;
  String _replyAs = 'support';
  String _newCountryCode = PhoneNumberService.countries.first.dialCode;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _notificationSubscription = RealtimeNotificationService.notificationsStream
        .listen(_handleTicketNotification);
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    _newUserId.dispose();
    _newName.dispose();
    _newWhatsapp.dispose();
    _newTitle.dispose();
    _newDetails.dispose();
    _statusCustom.dispose();
    _statusNote.dispose();
    _editTitle.dispose();
    _followerUserId.dispose();
    _notificationSubscription?.cancel();
    _stopChatAutoRefresh();
    super.dispose();
  }

  void _handleTicketNotification(Map<String, dynamic> payload) {
    if (!mounted || !_authorized || _busy) {
      return;
    }
    final type = payload['type']?.toString().trim().toLowerCase() ?? '';
    final sourceType =
        payload['sourceType']?.toString().trim().toLowerCase() ?? '';
    final ticketId =
        payload['ticketId']?.toString().trim() ??
        payload['sourceId']?.toString().split(':').first.trim() ??
        '';
    final isSupportTicket =
        type.startsWith('support_ticket') ||
        sourceType == 'support_ticket' ||
        ticketId.isNotEmpty;
    if (!isSupportTicket) {
      return;
    }

    final selectedId = _selected?['id']?.toString() ?? '';
    if (selectedId.isNotEmpty && ticketId == selectedId) {
      unawaited(_refreshSelected());
      return;
    }
    unawaited(_load());
  }

  Future<void> _refreshSelected() async {
    final selectedId = _selected?['id']?.toString() ?? '';
    if (selectedId.isEmpty) return;
    try {
      final results = await Future.wait<dynamic>([
        _api.getAdminSupportTickets(),
        _api.getAdminSupportTicket(ticketId: selectedId),
      ]);
      if (!mounted) return;
      setState(() {
        _tickets = List<Map<String, dynamic>>.from(results[0] as List);
        _selected = Map<String, dynamic>.from(
          (results[1] as Map)['ticket'] as Map,
        );
      });
      _refreshChatRoute();
    } catch (_) {}
  }

  Future<void> _openTicket(Map<String, dynamic> ticket) async {
    final id = ticket['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      _selected = Map<String, dynamic>.from(ticket);
      _ticketLoading = true;
    });
    unawaited(_openChatRoute());
    try {
      final body = await _api.getAdminSupportTicket(ticketId: id);
      if (!mounted) return;
      setState(() {
        _selected = Map<String, dynamic>.from(body['ticket'] as Map);
        _ticketLoading = false;
      });
      _refreshChatRoute();
      unawaited(_load());
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: context.loc.text('تعذر فتح التذكرة', 'Could not open ticket'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _ticketLoading = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _load() async {
    try {
      if (mounted) {
        setState(() {
          _loadError = null;
          _loading = _tickets.isEmpty;
        });
      }
      final user = await _auth.currentUser();
      final permissions = AppPermissions.fromUser(user);
      if (!permissions.isAdminRole &&
          !permissions.isSupportRole &&
          !permissions.canManageUsers) {
        if (mounted) {
          setState(() {
            _authorized = false;
            _loadError = null;
            _loading = false;
          });
        }
        return;
      }
      final results = await Future.wait<dynamic>([
        _api.getAdminSupportTickets(),
        _api.getAdminSupportTicketStatuses(),
      ]);
      final tickets = List<Map<String, dynamic>>.from(results[0] as List);
      final statuses = List<Map<String, dynamic>>.from(results[1] as List);
      if (!mounted) return;
      setState(() {
        _authorized = true;
        _loadError = null;
        _loading = false;
        _tickets = tickets;
        _statuses = statuses;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = ErrorMessageService.sanitize(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _claim(Map<String, dynamic> ticket) async {
    setState(() => _busy = true);
    try {
      final body = await _api.claimSupportTicket(ticket['id'].toString());
      if (!mounted) return;
      setState(
        () => _selected = Map<String, dynamic>.from(body['ticket'] as Map),
      );
      await _openTicket(_selected!);
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: context.loc.text('تعذر فتح التذكرة', 'Could not open ticket'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _send() async {
    if (_selected == null || _message.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.sendAdminSupportTicketMessage(
        ticketId: _selected!['id'].toString(),
        body: _message.text,
        replyAs: _replyAs,
      );
      _message.clear();
      final body = await _api.getAdminSupportTicket(
        ticketId: _selected!['id'].toString(),
      );
      if (mounted) {
        setState(
          () => _selected = Map<String, dynamic>.from(body['ticket'] as Map),
        );
        _refreshChatRoute();
      }
      unawaited(_load());
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: context.loc.text('تعذر إرسال الرد', 'Could not send reply'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _upload() async {
    final selected = _selected;
    if (selected == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file?.bytes == null) return;
    setState(() => _busy = true);
    _refreshChatRoute();
    try {
      await _api.uploadSupportTicketAttachment(
        ticketId: selected['id'].toString(),
        fileName: file!.name,
        bytes: file.bytes!,
        admin: true,
      );
      final body = await _api.getAdminSupportTicket(
        ticketId: selected['id'].toString(),
      );
      if (!mounted) return;
      setState(
        () => _selected = Map<String, dynamic>.from(body['ticket'] as Map),
      );
      _refreshChatRoute();
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: context.loc.text(
          'تعذر رفع المرفق',
          'Could not upload attachment',
        ),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _openChatRoute() async {
    if (!mounted || _selected == null || _chatRouteOpen) {
      _refreshChatRoute();
      return;
    }
    _chatRouteOpen = true;
    _startChatAutoRefresh();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, setRouteState) {
            _chatRouteSetState = setRouteState;
            return Scaffold(
              backgroundColor: AppTheme.background,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: _chat(),
                ),
              ),
            );
          },
        ),
      ),
    );
    _stopChatAutoRefresh();
    _chatRouteOpen = false;
    _chatRouteSetState = null;
    if (mounted) {
      setState(() => _selected = null);
    }
  }

  void _refreshChatRoute() {
    _chatRouteSetState?.call(() {});
  }

  void _startChatAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || !_chatRouteOpen || _selected == null || _busy) {
        return;
      }
      unawaited(_refreshSelected());
    });
  }

  void _stopChatAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<void> _openCreateDialog() async {
    final l = context.loc;
    _newUserId.clear();
    _newName.clear();
    _newWhatsapp.clear();
    _newTitle.clear();
    _newDetails.clear();
    _newCountryCode = PhoneNumberService.countries.first.dialCode;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (dialogContext) => Scaffold(
          appBar: AppBar(
            title: Text(
              l.text('فتح تذكرة من الإدارة', 'Open ticket from admin'),
            ),
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    TextField(
                      controller: _newUserId,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l.text(
                          'رقم المستخدم المسجل (اختياري)',
                          'Registered user ID (optional)',
                        ),
                        prefixIcon: const Icon(Icons.person_search_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newName,
                      decoration: InputDecoration(
                        labelText: l.text(
                          'اسم غير المسجل',
                          'Unregistered name',
                        ),
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _AdminCountrySelector(
                      initialCode: _newCountryCode,
                      onChanged: (countryCode) {
                        _newCountryCode = countryCode;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newWhatsapp,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: l.text(
                          'واتساب غير المسجل',
                          'Unregistered WhatsApp',
                        ),
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newTitle,
                      decoration: InputDecoration(
                        labelText: l.text('عنوان التذكرة', 'Ticket title'),
                        prefixIcon: const Icon(Icons.subject_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newDetails,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: l.text('تفاصيل التذكرة', 'Ticket details'),
                        prefixIcon: const Icon(Icons.notes_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text(l.text('إلغاء', 'Cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              if (_newTitle.text.trim().length < 3 ||
                                  _newDetails.text.trim().length < 4 ||
                                  (_newUserId.text.trim().isEmpty &&
                                      _newWhatsapp.text.trim().length < 8)) {
                                AppAlertService.showError(
                                  context,
                                  title: l.text(
                                    'تعذر فتح التذكرة',
                                    'Could not open ticket',
                                  ),
                                  message: l.text(
                                    'أدخل مستخدماً أو رقم واتساب مع عنوان وتفاصيل واضحة.',
                                    'Enter a user or WhatsApp number with a clear title and details.',
                                  ),
                                );
                                return;
                              }
                              Navigator.of(dialogContext).pop();
                              await _createAdminTicket();
                            },
                            icon: const Icon(Icons.add_comment_rounded),
                            label: Text(l.text('فتح التذكرة', 'Open ticket')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
          resizeToAvoidBottomInset: true,
        ),
      ),
    );
  }

  Future<void> _createAdminTicket() async {
    setState(() => _busy = true);
    try {
      await _api.createAdminSupportTicket(
        userId: _newUserId.text,
        name: _newName.text,
        whatsapp: _newWhatsapp.text,
        countryCode: _newCountryCode,
        title: _newTitle.text,
        details: _newDetails.text,
      );
      await _load();
      if (!mounted) return;
      AppAlertService.showSuccess(
        context,
        title: context.loc.text('تم فتح التذكرة', 'Ticket opened'),
        message: context.loc.text(
          'تم إرسال بيانات التذكرة إلى رقم واتساب للمتابعة من داخل التطبيق.',
          'Ticket details were sent to the WhatsApp number for in-app follow-up.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: context.loc.text('تعذر فتح التذكرة', 'Could not open ticket'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openStatusDialog() async {
    final selected = _selected;
    if (selected == null) return;
    final l = context.loc;
    var status = selected['status']?.toString() ?? 'open';
    var actorKind = _replyAs;
    _statusCustom.clear();
    _statusNote.clear();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => Scaffold(
            appBar: AppBar(
              title: Text(l.text('تغيير حالة التذكرة', 'Change ticket status')),
            ),
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue:
                            _statuses.any((item) => item['value'] == status)
                            ? status
                            : 'open',
                        decoration: InputDecoration(
                          labelText: l.text('الحالة', 'Status'),
                          prefixIcon: const Icon(Icons.flag_rounded),
                        ),
                        items: _statuses
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item['value']?.toString() ?? '',
                                child: Text(item['label']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => status = value);
                          }
                        },
                      ),
                      if (status == 'custom') ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _statusCustom,
                          decoration: InputDecoration(
                            labelText: l.text(
                              'اسم الحالة الخاصة',
                              'Custom status name',
                            ),
                            prefixIcon: const Icon(Icons.edit_note_rounded),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'support',
                            label: Text(l.text('الدعم', 'Support')),
                          ),
                          ButtonSegment(
                            value: 'admin',
                            label: Text(l.text('الإدارة', 'Admin')),
                          ),
                        ],
                        selected: {actorKind},
                        onSelectionChanged: (value) =>
                            setDialogState(() => actorKind = value.first),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _statusNote,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: l.text('تعليق التغيير', 'Change note'),
                          prefixIcon: const Icon(Icons.comment_outlined),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: Text(l.text('إلغاء', 'Cancel')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () async {
                                Navigator.of(dialogContext).pop();
                                await _changeStatus(status, actorKind);
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: Text(
                                l.text('تغيير الحالة', 'Change status'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            resizeToAvoidBottomInset: true,
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatus(String status, String actorKind) async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _busy = true);
    try {
      final body = await _api.changeAdminSupportTicketStatus(
        ticketId: selected['id'].toString(),
        status: status,
        customStatusLabel: _statusCustom.text,
        note: _statusNote.text,
        actorKind: actorKind,
      );
      await _load();
      if (!mounted) return;
      setState(
        () => _selected = Map<String, dynamic>.from(body['ticket'] as Map),
      );
      _refreshChatRoute();
      AppAlertService.showSuccess(
        context,
        title: context.loc.text('تم تغيير الحالة', 'Status changed'),
        message: context.loc.text(
          'تم تحديث التذكرة.',
          'The ticket was updated.',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: context.loc.text('تعذر تغيير الحالة', 'Could not change status'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _openEditTitleDialog() async {
    final selected = _selected;
    if (selected == null) return;
    final l = context.loc;
    _editTitle.text = selected['title']?.toString() ?? '';
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (dialogContext) => Scaffold(
          appBar: AppBar(
            title: Text(
              l.text('تعديل عنوان المحادثة', 'Edit conversation title'),
            ),
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    TextField(
                      controller: _editTitle,
                      decoration: InputDecoration(
                        labelText: l.text('العنوان', 'Title'),
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(l.text('إلغاء', 'Cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            icon: const Icon(Icons.save_rounded),
                            label: Text(l.text('حفظ', 'Save')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
          resizeToAvoidBottomInset: true,
        ),
      ),
    );
    if (confirmed != true || _editTitle.text.trim().length < 3) return;
    setState(() => _busy = true);
    try {
      final body = await _api.updateAdminSupportTicketTitle(
        ticketId: selected['id'].toString(),
        title: _editTitle.text,
      );
      if (!mounted) return;
      setState(
        () => _selected = Map<String, dynamic>.from(body['ticket'] as Map),
      );
      await _load();
      _refreshChatRoute();
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: l.text('تعذر تعديل العنوان', 'Could not edit title'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Future<void> _openFollowerDialog() async {
    final selected = _selected;
    if (selected == null) return;
    final l = context.loc;
    _followerUserId.clear();
    final searchController = TextEditingController();
    var results = <Map<String, dynamic>>[];
    Map<String, dynamic>? selectedUser;
    var searching = false;
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> search(String query) async {
              setDialogState(() => searching = true);
              try {
                final found = await _api.searchUsers(query.trim());
                if (!dialogContext.mounted) return;
                setDialogState(() => results = found);
              } catch (_) {
                if (!dialogContext.mounted) return;
                setDialogState(() => results = []);
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => searching = false);
                }
              }
            }

            return Scaffold(
              appBar: AppBar(
                title: Text(
                  l.text('إضافة متابع للمحادثة', 'Add conversation follower'),
                ),
              ),
              body: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            labelText: l.text(
                              'ابحث بالاسم أو المستخدم أو الهاتف',
                              'Search by name, username, or phone',
                            ),
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: searching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          onChanged: search,
                        ),
                        if (selectedUser != null) ...[
                          const SizedBox(height: 14),
                          _followerUserTile(
                            selectedUser!,
                            selected: true,
                            onTap: () =>
                                setDialogState(() => selectedUser = null),
                          ),
                        ],
                        const SizedBox(height: 14),
                        ...results.map(
                          (user) => _followerUserTile(
                            user,
                            selected:
                                user['id']?.toString() ==
                                selectedUser?['id']?.toString(),
                            onTap: () => setDialogState(() {
                              selectedUser = user;
                              _followerUserId.text =
                                  user['id']?.toString() ?? '';
                            }),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: Text(l.text('إلغاء', 'Cancel')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: selectedUser == null
                                    ? null
                                    : () => Navigator.pop(dialogContext, true),
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                ),
                                label: Text(l.text('إضافة', 'Add')),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
              resizeToAvoidBottomInset: true,
            );
          },
        ),
      ),
    );
    searchController.dispose();
    if (confirmed != true || _followerUserId.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final body = await _api.addAdminSupportTicketFollower(
        ticketId: selected['id'].toString(),
        userId: _followerUserId.text,
      );
      if (!mounted) return;
      setState(
        () => _selected = Map<String, dynamic>.from(body['ticket'] as Map),
      );
      await _load();
      _refreshChatRoute();
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: l.text('تعذر إضافة المتابع', 'Could not add follower'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refreshChatRoute();
      }
    }
  }

  Widget _followerUserTile(
    Map<String, dynamic> user, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final name = user['fullName']?.toString().trim().isNotEmpty == true
        ? user['fullName'].toString().trim()
        : user['username']?.toString() ?? '';
    final details = [
      user['username']?.toString() ?? '',
      user['whatsapp']?.toString() ?? '',
      '#${user['id'] ?? ''}',
    ].where((item) => item.trim().isNotEmpty).join(' | ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? AppTheme.primarySoft : AppTheme.surface,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: selected
              ? AppTheme.primary
              : AppTheme.surfaceVariant,
          child: Icon(
            selected ? Icons.check_rounded : Icons.person_outline_rounded,
            color: selected ? Colors.white : AppTheme.primary,
          ),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null && !_authorized) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(context.loc.text('تذاكر التواصل', 'Support tickets')),
        ),
        drawer: AppSidebar.drawerFor(context),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AdminLoadErrorCard(message: _loadError!, onRetry: _load),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.loc.text('تذاكر التواصل', 'Support tickets')),
        actions: [
          IconButton(
            tooltip: context.loc.text('فتح تذكرة', 'Open ticket'),
            onPressed: _busy ? null : _openCreateDialog,
            icon: const Icon(Icons.add_comment_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: AppSidebar.drawerFor(context),
      body: !_authorized
          ? Center(
              child: Text(
                context.loc.text(
                  'لا تملك صلاحية متابعة التذاكر.',
                  'You do not have permission to manage tickets.',
                ),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: _ticketList(compact: false),
              ),
            ),
    );
  }

  Widget _ticketList({required bool compact}) => ShwakelCard(
    padding: const EdgeInsets.all(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadError != null) ...[
          AdminLoadErrorCard(message: _loadError!, onRetry: _load),
          const SizedBox(height: 10),
        ],
        Text(
          context.loc.text('التذاكر المفتوحة', 'Open tickets'),
          style: AppTheme.h3,
        ),
        const SizedBox(height: 10),
        ShwakelButton(
          label: context.loc.text('فتح تذكرة جديدة', 'Open new ticket'),
          onPressed: _busy ? null : _openCreateDialog,
          icon: Icons.add_comment_rounded,
        ),
        const SizedBox(height: 10),
        if (_tickets.isEmpty)
          Text(
            context.loc.text(
              'لا توجد تذاكر حالياً.',
              'There are no tickets right now.',
            ),
          ),
        if (_tickets.isNotEmpty)
          Expanded(
            child: ListView.separated(
              itemCount: _tickets.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final ticket = _tickets[index];
                final claimed = ticket['claimed'] == true;
                final contact = ticket['contactWhatsapp']?.toString() ?? '';
                final createdBy = ticket['createdByUserId']?.toString() ?? '';
                return ListTile(
                  dense: compact,
                  selected: ticket['id'] == _selected?['id'],
                  leading: CircleAvatar(
                    backgroundColor: claimed
                        ? AppTheme.primarySoft
                        : AppTheme.warningLight,
                    child: Icon(
                      claimed ? Icons.chat_rounded : Icons.lock_open_rounded,
                      color: claimed ? AppTheme.primary : AppTheme.warning,
                    ),
                  ),
                  title: Text(
                    ticket['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      contact,
                      if (createdBy.isNotEmpty) 'منشئ المتابعة #$createdBy',
                      claimed
                          ? context.loc.text('قيد المتابعة', 'In progress')
                          : context.loc.text('بانتظار الفتح', 'Waiting'),
                    ].where((item) => item.trim().isNotEmpty).join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: contact.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.loc.text('نسخ الرقم', 'Copy number'),
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () async {
                            final loc = context.loc;
                            await Clipboard.setData(
                              ClipboardData(text: contact),
                            );
                            if (!context.mounted) return;
                            AppAlertService.showSuccess(
                              context,
                              title: loc.text('تم النسخ', 'Copied'),
                              message: contact,
                            );
                          },
                        ),
                  onTap: () => claimed ? _openTicket(ticket) : _claim(ticket),
                );
              },
            ),
          ),
      ],
    ),
  );

  Widget _chat() {
    final l = context.loc;
    final messages = List<Map<String, dynamic>>.from(
      (_selected?['messages'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final attachments = List<Map<String, dynamic>>.from(
      (_selected?['attachments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final statusEvents = _statusEvents();
    final timeline = _adminChatTimeline(messages, statusEvents, attachments);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _adminChatHeader(l),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: _ticketLoading && timeline.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l.text('يتم تحميل المحادثة...', 'Loading chat...'),
                          style: AppTheme.caption,
                        ),
                      ],
                    ),
                  )
                : timeline.isNotEmpty
                ? ListView.separated(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: timeline.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = timeline[index];
                      return switch (item['_timelineKind']) {
                        'status' => _adminStatusEventTile(item),
                        'attachment' => _adminAttachmentBubble(item),
                        _ => _adminMessageBubble(item),
                      };
                    },
                  )
                : Center(
                    child: Text(
                      l.text(
                        'لا توجد رسائل في هذه التذكرة بعد.',
                        'There are no messages in this ticket yet.',
                      ),
                      style: AppTheme.caption,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        _adminChatComposer(l),
      ],
    );
  }

  Widget _adminChatHeader(AppLocalizer l) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: l.text('رجوع', 'Back'),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          const CircleAvatar(
            backgroundColor: AppTheme.primarySoft,
            child: Icon(Icons.support_agent_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selected?['title']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyBold,
                ),
                const SizedBox(height: 2),
                Text(
                  '#${_selected?['id']} - ${_selected?['statusLabel'] ?? _selected?['status']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: l.text('تعديل العنوان', 'Edit title'),
            onPressed: _busy ? null : _openEditTitleDialog,
            icon: const Icon(Icons.edit_note_rounded),
          ),
          IconButton(
            tooltip: l.text('إضافة متابع', 'Add follower'),
            onPressed: _busy ? null : _openFollowerDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          IconButton(
            tooltip: l.text('تغيير الحالة', 'Change status'),
            onPressed: _busy ? null : _openStatusDialog,
            icon: const Icon(Icons.flag_rounded),
          ),
          IconButton(
            tooltip: l.text('تحديث', 'Refresh'),
            onPressed: _busy ? null : _refreshSelected,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _adminChatComposer(AppLocalizer l) {
    return ShwakelCard(
      padding: const EdgeInsets.all(10),
      shadowLevel: ShwakelShadowLevel.medium,
      child: Column(
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'support',
                label: Text(l.text('الدعم', 'Support')),
              ),
              ButtonSegment(
                value: 'admin',
                label: Text(l.text('الإدارة', 'Admin')),
              ),
            ],
            selected: {_replyAs},
            onSelectionChanged: (value) =>
                setState(() => _replyAs = value.first),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton.filledTonal(
                tooltip: l.text('إرفاق ملف', 'Attach file'),
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _message,
                  onChanged: (_) {
                    setState(() {});
                    _refreshChatRoute();
                  },
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: l.text('اكتب ردك...', 'Write your reply...'),
                    filled: true,
                    fillColor: AppTheme.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: l.text('إرسال الرد', 'Send reply'),
                onPressed:
                    _busy || _selected == null || _message.text.trim().isEmpty
                    ? null
                    : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adminMessageBubble(Map<String, dynamic> message) {
    final l = context.loc;
    final senderKind = message['senderKind']?.toString().toLowerCase() ?? '';
    final mine = senderKind != 'customer';
    final attachments = List<Map<String, dynamic>>.from(
      (message['attachments'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width >= 900 ? 560 : 300,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primary : AppTheme.surface,
          border: Border.all(color: mine ? AppTheme.primary : AppTheme.border),
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(18),
            topEnd: const Radius.circular(18),
            bottomStart: Radius.circular(mine ? 18 : 6),
            bottomEnd: Radius.circular(mine ? 6 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine
                  ? (message['displayName']?.toString() ??
                        l.text('الدعم', 'Support'))
                  : (message['displayName']?.toString() ??
                        l.text('العميل', 'Customer')),
              style: AppTheme.caption.copyWith(
                color: mine ? Colors.white70 : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            SelectableText(
              message['body']?.toString() ?? '',
              style: AppTheme.bodyText.copyWith(
                color: mine ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final attachment in attachments) ...[
                _attachmentTile(attachment, compact: true),
                const SizedBox(height: 6),
              ],
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _messageStatusIcon(message),
                  size: 14,
                  color: mine ? Colors.white70 : AppTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _messageStatusLabel(message, mine),
                  style: AppTheme.caption.copyWith(
                    color: mine ? Colors.white70 : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _messageStatusIcon(Map<String, dynamic> message) {
    if ((message['readAt']?.toString().trim() ?? '').isNotEmpty) {
      return Icons.done_all_rounded;
    }
    if ((message['deliveredAt']?.toString().trim() ?? '').isNotEmpty) {
      return Icons.done_all_rounded;
    }
    return Icons.done_rounded;
  }

  String _messageStatusLabel(Map<String, dynamic> message, bool mine) {
    final l = context.loc;
    if (!mine) {
      return message['createdAt']?.toString() ?? '';
    }
    if ((message['readAt']?.toString().trim() ?? '').isNotEmpty) {
      return l.text('تمت القراءة', 'Read');
    }
    if ((message['deliveredAt']?.toString().trim() ?? '').isNotEmpty) {
      return l.text('وصلت', 'Delivered');
    }
    return l.text('تم الإرسال', 'Sent');
  }

  List<Map<String, dynamic>> _statusEvents() {
    final events = List<Map<String, dynamic>>.from(
      (_selected?['statusEvents'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    return events;
  }

  Widget _adminStatusEventTile(Map<String, dynamic> event) {
    final l = context.loc;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.14)),
      ),
      child: SelectableText(
        l.text(
          'تغيير الحالة إلى ${event['toStatusLabel']} بواسطة ${event['staffName']?.toString().isNotEmpty == true ? event['staffName'] : event['actorDisplayName']}${event['note']?.toString().isNotEmpty == true ? '\n${event['note']}' : ''}',
          'Status changed to ${event['toStatusLabel']} by ${event['staffName']?.toString().isNotEmpty == true ? event['staffName'] : event['actorDisplayName']}${event['note']?.toString().isNotEmpty == true ? '\n${event['note']}' : ''}',
        ),
        style: AppTheme.caption,
      ),
    );
  }

  List<Map<String, dynamic>> _adminChatTimeline(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> statusEvents,
    List<Map<String, dynamic>> attachments,
  ) {
    final timeline = <Map<String, dynamic>>[
      ...messages.map((item) => {...item, '_timelineKind': 'message'}),
      ...statusEvents.map((item) => {...item, '_timelineKind': 'status'}),
      ...attachments.map((item) => {...item, '_timelineKind': 'attachment'}),
    ];
    timeline.sort(
      (left, right) => (right['createdAt']?.toString() ?? '').compareTo(
        left['createdAt']?.toString() ?? '',
      ),
    );
    return timeline;
  }

  Widget _adminAttachmentBubble(Map<String, dynamic> file) {
    final mine = file['uploaderKind']?.toString() != 'customer';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width >= 900 ? 620 : 330,
        ),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primarySoft : AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: _attachmentTile(file, compact: true),
      ),
    );
  }

  Widget _attachmentTile(Map<String, dynamic> file, {bool compact = false}) {
    final l = context.loc;
    final image = _isImageAttachment(file);
    final size = _formatBytes(file['sizeBytes']);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: compact ? 0 : 220,
        maxWidth: compact ? double.infinity : 320,
      ),
      child: Material(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _openAttachment(file),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  image ? Icons.image_outlined : Icons.description_outlined,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file['name']?.toString() ??
                            l.text('مرفق', 'Attachment'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyBold,
                      ),
                      Text(
                        image
                            ? l.text(
                                'عرض الصورة مباشرة - $size',
                                'View image directly - $size',
                              )
                            : l.text(
                                'فتح أو تحميل - $size',
                                'Open or download - $size',
                              ),
                        style: AppTheme.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(image ? Icons.visibility_rounded : Icons.download_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAttachment(Map<String, dynamic> file) async {
    final id = _selected?['id']?.toString() ?? '';
    final attachmentId = file['id']?.toString() ?? '';
    if (id.isEmpty || attachmentId.isEmpty) {
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await _api.downloadSupportTicketAttachment(
        ticketId: id,
        attachmentId: attachmentId,
      );
      if (!mounted) return;
      if (_isImageAttachment(file)) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        );
        return;
      }
      await _saveAttachment(file, bytes);
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: context.loc.text('تعذر فتح المرفق', 'Could not open attachment'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveAttachment(
    Map<String, dynamic> file,
    Uint8List bytes,
  ) async {
    final extension = _extensionFor(file);
    final name = _safeFileName(
      file['name']?.toString() ?? 'support-file',
    ).replaceFirst(RegExp('\\.$extension\$'), '');
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: extension,
      mimeType: _fileSaverMime(file),
    );
    if (!mounted) return;
    AppAlertService.showSuccess(
      context,
      title: context.loc.text('المرفق جاهز', 'Attachment ready'),
      message: context.loc.text(
        'تم تجهيز الملف للفتح أو التحميل من جهازك.',
        'The file is ready to open or download from your device.',
      ),
    );
  }

  bool _isImageAttachment(Map<String, dynamic> file) {
    final mime = file['mimeType']?.toString().toLowerCase() ?? '';
    return mime.startsWith('image/');
  }

  String _extensionFor(Map<String, dynamic> file) {
    final name = file['name']?.toString().toLowerCase() ?? '';
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1).replaceAll(RegExp('[^a-z0-9]'), '');
    }
    final mime = file['mimeType']?.toString().toLowerCase() ?? '';
    if (mime.contains('pdf')) return 'pdf';
    if (mime.contains('png')) return 'png';
    if (mime.contains('webp')) return 'webp';
    if (mime.contains('jpeg')) return 'jpg';
    return 'txt';
  }

  MimeType _fileSaverMime(Map<String, dynamic> file) {
    final mime = file['mimeType']?.toString().toLowerCase() ?? '';
    if (mime.contains('pdf')) return MimeType.pdf;
    if (mime.contains('png')) return MimeType.png;
    if (mime.contains('jpeg')) return MimeType.jpeg;
    return MimeType.other;
  }

  String _safeFileName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'support-file' : cleaned;
  }

  String _formatBytes(dynamic value) {
    final bytes = int.tryParse(value?.toString() ?? '') ?? 0;
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _AdminCountrySelector extends StatefulWidget {
  const _AdminCountrySelector({
    required this.initialCode,
    required this.onChanged,
  });

  final String initialCode;
  final ValueChanged<String> onChanged;

  @override
  State<_AdminCountrySelector> createState() => _AdminCountrySelectorState();
}

class _AdminCountrySelectorState extends State<_AdminCountrySelector> {
  late String _selectedCountryCode = widget.initialCode;

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final selected = PhoneNumberService.countries.firstWhere(
      (country) => country.dialCode == _selectedCountryCode,
      orElse: () => PhoneNumberService.countries.first,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _pickCountry,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l.text('الدولة', 'Country'),
          prefixIcon: const Icon(Icons.public_rounded, size: 20),
          suffixIcon: const Icon(Icons.search_rounded),
        ),
        child: Text(
          '${selected.name} (+${selected.dialCode})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.bodyBold,
        ),
      ),
    );
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => const _AdminCountryPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedCountryCode = picked.dialCode);
    widget.onChanged(picked.dialCode);
  }
}

class _AdminCountryPickerSheet extends StatefulWidget {
  const _AdminCountryPickerSheet();

  @override
  State<_AdminCountryPickerSheet> createState() =>
      _AdminCountryPickerSheetState();
}

class _AdminCountryPickerSheetState extends State<_AdminCountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CountryOption> get _filteredCountries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return PhoneNumberService.countries;
    final digits = query.replaceAll(RegExp(r'\D'), '');
    return PhoneNumberService.countries.where((country) {
      final name = country.name.toLowerCase();
      return name.contains(query) ||
          country.flag.toLowerCase().contains(query) ||
          (digits.isNotEmpty && country.dialCode.contains(digits));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final countries = _filteredCountries;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.text('اختر الدولة', 'Choose Country'), style: AppTheme.h3),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.text(
                  'ابحث باسم الدولة أو كود الاتصال',
                  'Search by country name or calling code',
                ),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: countries.isEmpty
                  ? Center(
                      child: Text(
                        l.text(
                          'لا توجد دولة بهذا البحث',
                          'No country matches this search',
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: countries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final country = countries[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              country.flag,
                              style: AppTheme.caption.copyWith(fontSize: 11),
                            ),
                          ),
                          title: Text(country.name),
                          subtitle: Text('+${country.dialCode}'),
                          onTap: () => Navigator.pop(context, country),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
