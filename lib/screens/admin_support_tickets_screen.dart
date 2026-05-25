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
          title: context.loc.text(
            'تعذر تحميل التذاكر',
            'Could not load tickets',
          ),
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
        title: context.loc.text('تعذر فتح التذكرة', 'Could not open ticket'),
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
        title: context.loc.text('تعذر إرسال الرد', 'Could not send reply'),
        message: ErrorMessageService.sanitize(error),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final l = context.loc;
    _newUserId.clear();
    _newName.clear();
    _newWhatsapp.clear();
    _newTitle.clear();
    _newDetails.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.text('فتح تذكرة من الإدارة', 'Open ticket from admin')),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                    labelText: l.text('اسم غير المسجل', 'Unregistered name'),
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
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
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.text('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () async {
              if (_newTitle.text.trim().length < 3 ||
                  _newDetails.text.trim().length < 4 ||
                  (_newUserId.text.trim().isEmpty &&
                      _newWhatsapp.text.trim().length < 8)) {
                AppAlertService.showError(
                  context,
                  title: l.text('تعذر فتح التذكرة', 'Could not open ticket'),
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l.text('تغيير حالة التذكرة', 'Change ticket status')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _statuses.any((item) => item['value'] == status)
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l.text('إلغاء', 'Cancel')),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _changeStatus(status, actorKind);
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(l.text('تغيير الحالة', 'Change status')),
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
      drawer: const AppSidebar(),
      body: !_authorized
          ? Center(
              child: Text(
                context.loc.text(
                  'لا تملك صلاحية متابعة التذاكر.',
                  'You do not have permission to manage tickets.',
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => ResponsiveScaffoldContainer(
                maxWidth: 1180,
                padding: const EdgeInsets.all(AppTheme.spacingMd),
                child: SizedBox(
                  height: constraints.maxHeight - AppTheme.spacingLg,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final compact = box.maxWidth < 800;
                      final list = _ticketList(compact: compact);
                      final chat = _selected == null ? _empty() : _chat();
                      if (compact) {
                        return Column(
                          children: [
                            SizedBox(height: 240, child: list),
                            const SizedBox(height: 12),
                            Expanded(child: chat),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Widget _ticketList({required bool compact}) => ShwakelCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                    claimed
                        ? context.loc.text('قيد المتابعة', 'In progress')
                        : context.loc.text(
                            'بانتظار الفتح',
                            'Waiting to be opened',
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => claimed
                      ? setState(() {
                          _selected = ticket;
                        })
                      : _claim(ticket),
                );
              },
            ),
          ),
      ],
    ),
  );

  Widget _empty() => ShwakelCard(
    padding: const EdgeInsets.all(28),
    height: double.infinity,
    child: Center(
      child: Text(
        context.loc.text(
          'افتح تذكرة من القائمة لبدء المتابعة.',
          'Open a ticket from the list to start following up.',
        ),
      ),
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
    final hasTimeline =
        statusEvents.isNotEmpty ||
        messages.isNotEmpty ||
        attachments.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _adminChatHeader(l),
        const SizedBox(height: 10),
        Expanded(
          child: ShwakelCard(
            padding: EdgeInsets.zero,
            color: AppTheme.surfaceVariant.withValues(alpha: 0.55),
            shadowLevel: ShwakelShadowLevel.none,
            child: hasTimeline
                ? ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount:
                        statusEvents.length +
                        messages.length +
                        (attachments.isNotEmpty ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index < statusEvents.length) {
                        return statusEvents[index];
                      }
                      final messageIndex = index - statusEvents.length;
                      if (messageIndex < messages.length) {
                        return _adminMessageBubble(messages[messageIndex]);
                      }
                      return _adminAttachmentsPanel(attachments);
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
    return ShwakelCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primarySoft,
            child: const Icon(
              Icons.support_agent_rounded,
              color: AppTheme.primary,
            ),
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
              Expanded(
                child: TextField(
                  controller: _message,
                  onChanged: (_) => setState(() {}),
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
          ],
        ),
      ),
    );
  }

  Widget _adminAttachmentsPanel(List<Map<String, dynamic>> attachments) {
    final l = context.loc;
    return ShwakelCard(
      padding: const EdgeInsets.all(14),
      shadowLevel: ShwakelShadowLevel.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.text('المرفقات', 'Attachments'), style: AppTheme.bodyBold),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: attachments.map(_attachmentTile).toList(),
          ),
        ],
      ),
    );
  }

  List<Widget> _statusEvents() {
    final l = context.loc;
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
              l.text(
                'تغيير الحالة إلى ${event['toStatusLabel']} بواسطة ${event['staffName']?.toString().isNotEmpty == true ? event['staffName'] : event['actorDisplayName']}${event['note']?.toString().isNotEmpty == true ? '\n${event['note']}' : ''}',
                'Status changed to ${event['toStatusLabel']} by ${event['staffName']?.toString().isNotEmpty == true ? event['staffName'] : event['actorDisplayName']}${event['note']?.toString().isNotEmpty == true ? '\n${event['note']}' : ''}',
              ),
              style: AppTheme.caption,
            ),
          ),
        )
        .toList();
  }

  Widget _attachmentTile(Map<String, dynamic> file) {
    final l = context.loc;
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
