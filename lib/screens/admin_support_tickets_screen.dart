import 'dart:async';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/app_top_actions.dart';
import '../widgets/responsive_scaffold_container.dart';
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
  List<Map<String, dynamic>> _tickets = const [];
  List<Map<String, dynamic>> _statuses = const [];
  Map<String, dynamic>? _selected;
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  bool _loading = true;
  bool _authorized = false;
  bool _busy = false;
  String _replyAs = 'support';

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
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _handleTicketNotification(Map<String, dynamic> payload) {
    if (!mounted || !_authorized || _busy) {
      return;
    }
    final type = payload['type']?.toString().trim().toLowerCase() ?? '';
    final sourceType =
        payload['sourceType']?.toString().trim().toLowerCase() ?? '';
    final ticketId = payload['ticketId']?.toString().trim() ??
        payload['sourceId']?.toString().split(':').first.trim() ??
        '';
    final isSupportTicket = type.startsWith('support_ticket') ||
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
      final tickets = await _api.getAdminSupportTickets();
      if (!mounted) return;
      final refreshed = tickets
          .where((ticket) => ticket['id']?.toString() == selectedId)
          .firstOrNull;
      setState(() {
        _tickets = tickets;
        if (refreshed != null) {
          _selected = refreshed;
        }
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final user = await _auth.currentUser();
    final permissions = AppPermissions.fromUser(user);
    if (!permissions.isAdminRole &&
        !permissions.isSupportRole &&
        !permissions.canManageUsers) {
      if (mounted) {
        setState(() {
          _authorized = false;
          _loading = false;
        });
      }
      return;
    }
    try {
      final results = await Future.wait<dynamic>([
        _api.getAdminSupportTickets(),
        _api.getAdminSupportTicketStatuses(),
      ]);
      final tickets = List<Map<String, dynamic>>.from(results[0] as List);
      final statuses = List<Map<String, dynamic>>.from(results[1] as List);
      if (!mounted) return;
      setState(() {
        _authorized = true;
        _loading = false;
        _tickets = tickets;
        _statuses = statuses;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        AppAlertService.showError(
          context,
          title: 'تعذر تحميل التذاكر',
          message: ErrorMessageService.sanitize(error),
        );
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
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر فتح التذكرة',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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
      await _load();
      final refreshed = _tickets
          .where((ticket) => ticket['id'] == _selected!['id'])
          .firstOrNull;
      if (mounted && refreshed != null) {
        setState(() => _selected = refreshed);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppAlertService.showError(
        context,
        title: 'تعذر إرسال الرد',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openCreateDialog() async {
    _newUserId.clear();
    _newName.clear();
    _newWhatsapp.clear();
    _newTitle.clear();
    _newDetails.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فتح تذكرة من الإدارة'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _newUserId,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رقم المستخدم المسجل (اختياري)',
                    prefixIcon: Icon(Icons.person_search_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newName,
                  decoration: const InputDecoration(
                    labelText: 'اسم غير المسجل',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newWhatsapp,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'واتساب غير المسجل',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newTitle,
                  decoration: const InputDecoration(
                    labelText: 'عنوان التذكرة',
                    prefixIcon: Icon(Icons.subject_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newDetails,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل التذكرة',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (_newTitle.text.trim().length < 3 ||
                  _newDetails.text.trim().length < 4 ||
                  (_newUserId.text.trim().isEmpty &&
                      _newWhatsapp.text.trim().length < 8)) {
                AppAlertService.showError(
                  context,
                  title: 'تعذر فتح التذكرة',
                  message:
                      'أدخل مستخدماً أو رقم واتساب مع عنوان وتفاصيل واضحة.',
                );
                return;
              }
              Navigator.of(dialogContext).pop();
              await _createAdminTicket();
            },
            icon: const Icon(Icons.add_comment_rounded),
            label: const Text('فتح التذكرة'),
          ),
        ],
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
        title: _newTitle.text,
        details: _newDetails.text,
      );
      await _load();
      if (!mounted) return;
      AppAlertService.showSuccess(
        context,
        title: 'تم فتح التذكرة',
        message:
            'تم إرسال بيانات التذكرة إلى رقم واتساب للمتابعة من داخل التطبيق.',
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: 'تعذر فتح التذكرة',
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
    var status = selected['status']?.toString() ?? 'open';
    var actorKind = _replyAs;
    _statusCustom.clear();
    _statusNote.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تغيير حالة التذكرة'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _statuses.any((item) => item['value'] == status)
                      ? status
                      : 'open',
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    prefixIcon: Icon(Icons.flag_rounded),
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
                    decoration: const InputDecoration(
                      labelText: 'اسم الحالة الخاصة',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'support', label: Text('الدعم')),
                    ButtonSegment(value: 'admin', label: Text('الإدارة')),
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
                  decoration: const InputDecoration(
                    labelText: 'تعليق التغيير',
                    prefixIcon: Icon(Icons.comment_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _changeStatus(status, actorKind);
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('تغيير الحالة'),
            ),
          ],
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
      AppAlertService.showSuccess(
        context,
        title: 'تم تغيير الحالة',
        message: 'تم تحديث حالة التذكرة وإرسال إشعار للمتابعة داخل التطبيق.',
      );
    } catch (error) {
      if (!mounted) return;
      AppAlertService.showError(
        context,
        title: 'تعذر تغيير الحالة',
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('تذاكر التواصل'),
        actions: [
          IconButton(
            tooltip: 'فتح تذكرة',
            onPressed: _busy ? null : _openCreateDialog,
            icon: const Icon(Icons.add_comment_rounded),
          ),
          const AppNotificationAction(),
          const QuickLogoutAction(),
        ],
      ),
      drawer: const AppSidebar(),
      body: !_authorized
          ? const Center(child: Text('لا تملك صلاحية متابعة التذاكر.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ResponsiveScaffoldContainer(
                  maxWidth: 1180,
                  padding: const EdgeInsets.all(AppTheme.spacingLg),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final list = _ticketList();
                      final chat = _selected == null ? _empty() : _chat();
                      if (box.maxWidth < 800) {
                        return Column(
                          children: [list, const SizedBox(height: 14), chat],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 360, child: list),
                          const SizedBox(width: 14),
                          Expanded(child: chat),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }

  Widget _ticketList() => ShwakelCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('التذاكر المفتوحة', style: AppTheme.h3),
        const SizedBox(height: 10),
        ShwakelButton(
          label: 'فتح تذكرة جديدة',
          onPressed: _busy ? null : _openCreateDialog,
          icon: Icons.add_comment_rounded,
        ),
        const SizedBox(height: 10),
        if (_tickets.isEmpty) const Text('لا توجد تذاكر حالياً.'),
        ..._tickets.map(
          (ticket) => ListTile(
            selected: ticket['id'] == _selected?['id'],
            title: Text(
              ticket['title']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              ticket['claimed'] == true ? 'قيد المتابعة' : 'بانتظار الفتح',
            ),
            trailing: ticket['claimed'] == true
                ? const Icon(Icons.chat_rounded)
                : const Icon(Icons.lock_open_rounded),
            onTap: () => ticket['claimed'] == true
                ? setState(() {
                    _selected = ticket;
                  })
                : _claim(ticket),
          ),
        ),
      ],
    ),
  );

  Widget _empty() => ShwakelCard(
    padding: const EdgeInsets.all(28),
    child: const Center(child: Text('افتح تذكرة من القائمة لبدء المتابعة.')),
  );

  Widget _chat() {
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
    return ShwakelCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_selected?['title']?.toString() ?? '', style: AppTheme.h3),
          Text(
            'التذكرة ${_selected?['id']} - ${_selected?['statusLabel'] ?? _selected?['status']}',
            style: AppTheme.caption,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _busy ? null : _openStatusDialog,
              icon: const Icon(Icons.flag_rounded),
              label: const Text('تغيير الحالة'),
            ),
          ),
          const Divider(height: 24),
          ..._statusEvents(),
          ...messages.map(
            (message) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message['displayName']?.toString() ?? '',
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(message['body']?.toString() ?? ''),
                ],
              ),
            ),
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('المرفقات', style: AppTheme.bodyBold),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: attachments.map(_attachmentTile).toList(),
            ),
            const Divider(height: 24),
          ],
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'support', label: Text('الدعم')),
              ButtonSegment(value: 'admin', label: Text('الإدارة')),
            ],
            selected: {_replyAs},
            onSelectionChanged: (value) =>
                setState(() => _replyAs = value.first),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _message,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'الرد',
              prefixIcon: Icon(Icons.reply_rounded),
            ),
          ),
          const SizedBox(height: 10),
          ShwakelButton(
            label: 'إرسال الرد',
            onPressed: _busy ? null : _send,
            isLoading: _busy,
            icon: Icons.send_rounded,
          ),
        ],
      ),
    );
  }

  List<Widget> _statusEvents() {
    final events = List<Map<String, dynamic>>.from(
      (_selected?['statusEvents'] as List? ?? const []).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    return events
        .map(
          (event) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.14),
              ),
            ),
            child: SelectableText(
              'تغيير الحالة إلى ${event['toStatusLabel']} بواسطة ${event['staffName']?.toString().isNotEmpty == true ? event['staffName'] : event['actorDisplayName']}${event['note']?.toString().isNotEmpty == true ? '\n${event['note']}' : ''}',
              style: AppTheme.caption,
            ),
          ),
        )
        .toList();
  }

  Widget _attachmentTile(Map<String, dynamic> file) {
    final image = _isImageAttachment(file);
    final size = _formatBytes(file['sizeBytes']);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
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
                        file['name']?.toString() ?? 'مرفق',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyBold,
                      ),
                      Text(
                        image ? 'عرض الصورة مباشرة - $size' : 'فتح أو تحميل - $size',
                        style: AppTheme.caption,
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
        title: 'تعذر فتح المرفق',
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
    final name = _safeFileName(file['name']?.toString() ?? 'support-file')
        .replaceFirst(RegExp('\\.$extension\$'), '');
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: extension,
      mimeType: _fileSaverMime(file),
    );
    if (!mounted) return;
    AppAlertService.showSuccess(
      context,
      title: 'المرفق جاهز',
      message: 'تم تجهيز الملف للفتح أو التحميل من جهازك.',
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
