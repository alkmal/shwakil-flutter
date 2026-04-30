import 'package:flutter/material.dart';

import '../services/index.dart';
import '../utils/app_permissions.dart';
import '../utils/app_theme.dart';
import 'shwakel_logo.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _user = AuthService.peekCurrentUser();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await _authService.currentUser();
    if (!mounted) {
      return;
    }
    final previousRaw = _user?.toString();
    final nextRaw = user?.toString();
    if (previousRaw == nextRaw) {
      return;
    }
    setState(() => _user = user);
  }

  Future<void> _showOfflineBlockedMessage() {
    return AppAlertService.showInfo(
      context,
      title: context.loc.tr('widgets_app_sidebar.035'),
      message: context.loc.tr('widgets_app_sidebar.036'),
    );
  }

  Future<void> _openRoute(String routeName) async {
    final normalizedRoute =
        OfflineSessionService.isOfflineMode && routeName == '/scan-card'
        ? '/scan-card-offline'
        : routeName;
    if (!OfflineSessionService.canOpenRoute(normalizedRoute)) {
      await _showOfflineBlockedMessage();
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.pop(context);
    Navigator.pushNamed(context, normalizedRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.loc;
    final username =
        _user?['username']?.toString() ?? l.tr('widgets_app_sidebar.001');
    final fullName = _user?['fullName']?.toString().trim() ?? '';
    final verificationStatus =
        _user?['transferVerificationStatus']?.toString() ?? 'unverified';
    final permissions = AppPermissions.fromUser(_user);

    final canViewContact = permissions.canViewContact;
    final canViewLocations = permissions.canViewLocations;
    final canViewNotifications =
        permissions.canViewTransactions || permissions.canViewBalance;
    final canViewUsagePolicy = permissions.canViewUsagePolicy;
    final canViewSubUsers = permissions.canViewSubUsers;
    final canViewAccountSettings = permissions.canViewAccountSettings;
    final canRequestVerification = permissions.canRequestVerification;
    final hasAdminWorkspaceAccess = permissions.hasAdminWorkspaceAccess;
    final isOfflineMode = OfflineSessionService.isOfflineMode;
    return Drawer(
      width: MediaQuery.of(context).size.width >= 480 ? 360 : null,
      backgroundColor: AppTheme.sidebarSurface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.secondary, AppTheme.primary],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const ShwakelLogo(size: 48, framed: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName.isEmpty ? username : fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.h2.copyWith(
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@$username',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyText.copyWith(
                                color: AppTheme.textMutedOnDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _verificationBadge(verificationStatus),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                children: [
                  _buildMenuSection(
                    label: isOfflineMode
                        ? l.tr('widgets_app_sidebar.037')
                        : l.tr('widgets_app_sidebar.002'),
                    children: [
                      _buildItem(
                        context,
                        icon: Icons.home_rounded,
                        title: l.tr('widgets_app_sidebar.003'),
                        routeName: '/home',
                      ),
                      if (!isOfflineMode && canViewNotifications)
                        _buildItem(
                          context,
                          icon: Icons.notifications_active_rounded,
                          title: l.tr('widgets_app_sidebar.044'),
                          routeName: '/notifications',
                        ),
                    ],
                  ),
                  if (!isOfflineMode) ...[
                    _buildMenuSection(
                      label: l.tr('widgets_app_sidebar.009'),
                      children: [
                        if (canViewAccountSettings)
                          _buildItem(
                            context,
                            icon: Icons.person_rounded,
                            title: l.tr('widgets_app_sidebar.010'),
                            routeName: '/account-settings',
                          ),
                        if (verificationStatus != 'approved' &&
                            canRequestVerification)
                          _buildItem(
                            context,
                            icon: Icons.verified_user_rounded,
                            title: l.tr('widgets_app_sidebar.012'),
                            routeName: '/account-verification',
                          ),
                        if (canViewSubUsers)
                          _buildItem(
                            context,
                            icon: Icons.supervised_user_circle_rounded,
                            title: l.tr('widgets_app_sidebar.039'),
                            routeName: '/sub-users',
                          ),
                      ],
                    ),
                    if (hasAdminWorkspaceAccess) ...[
                      _buildMenuSection(
                        label: l.tr('widgets_app_sidebar.014'),
                        children: [
                          _buildItem(
                            context,
                            icon: Icons.dashboard_customize_rounded,
                            title: l.tr('widgets_app_sidebar.015'),
                            routeName: '/admin-dashboard',
                          ),
                        ],
                      ),
                    ],
                    _buildMenuSection(
                      label: l.tr('widgets_app_sidebar.020'),
                      children: [
                        if (canViewUsagePolicy)
                          _buildItem(
                            context,
                            icon: Icons.policy_rounded,
                            title: l.tr('widgets_app_sidebar.021'),
                            routeName: '/usage-policy',
                          ),
                        if (canViewContact)
                          _buildItem(
                            context,
                            icon: Icons.support_agent_rounded,
                            title: l.tr('widgets_app_sidebar.022'),
                            routeName: '/contact-us',
                          ),
                        if (canViewLocations)
                          _buildItem(
                            context,
                            icon: Icons.storefront_rounded,
                            title: l.tr('widgets_app_sidebar.023'),
                            routeName: '/supported-locations',
                          ),
                      ],
                    ),
                  ],
                  _buildMenuSection(
                    label: l.tr('widgets_app_sidebar.024'),
                    children: [_buildLanguageItem(context)],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _verificationBadge(String status) {
    final l = context.loc;
    var label = l.tr('widgets_app_sidebar.027');
    var color = Colors.white24;
    if (status == 'approved') {
      label = l.tr('widgets_app_sidebar.028');
      color = AppTheme.success.withValues(alpha: 0.28);
    } else if (status == 'pending') {
      label = l.tr('widgets_app_sidebar.029');
      color = AppTheme.warning.withValues(alpha: 0.28);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMenuSection({
    required String label,
    required List<Widget> children,
  }) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(label),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Column(children: _withItemSeparators(children)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _withItemSeparators(List<Widget> children) {
    final separated = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        separated.add(const Divider(height: 1, indent: 58, endIndent: 12));
      }
      separated.add(children[index]);
    }
    return separated;
  }

  Widget _buildLanguageItem(BuildContext context) {
    final l = context.loc;
    return ListTile(
      minTileHeight: 50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: const Icon(
        Icons.language_rounded,
        color: AppTheme.textSecondary,
      ),
      title: Text(
        l.tr('widgets_app_sidebar.025'),
        style: AppTheme.bodyText.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(l.tr('widgets_app_sidebar.034'), style: AppTheme.caption),
      trailing: const Icon(
        Icons.translate_rounded,
        size: 20,
        color: AppTheme.textTertiary,
      ),
      onTap: () async {
        await AppLocaleService.instance.toggleLocale();
        if (context.mounted) {
          Navigator.pop(context);
        }
      },
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String routeName,
  }) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final normalizedRoute =
        OfflineSessionService.isOfflineMode && routeName == '/scan-card'
        ? '/scan-card-offline'
        : routeName;
    final isSelected =
        currentRoute == routeName || currentRoute == normalizedRoute;
    final isArabic = context.loc.isArabic;
    final isBlockedOffline = !OfflineSessionService.canOpenRoute(
      normalizedRoute,
    );

    return ListTile(
      minTileHeight: 50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(
        icon,
        color: isBlockedOffline
            ? AppTheme.textTertiary
            : (isSelected ? AppTheme.primary : AppTheme.textSecondary),
      ),
      title: Text(
        title,
        style: AppTheme.bodyText.copyWith(
          color: isBlockedOffline
              ? AppTheme.textTertiary
              : (isSelected ? AppTheme.primary : AppTheme.textPrimary),
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isBlockedOffline
              ? AppTheme.surfaceMuted.withValues(alpha: 0.7)
              : (isSelected
                    ? AppTheme.primary.withValues(alpha: 0.14)
                    : AppTheme.surfaceMuted),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          isArabic
              ? Icons.arrow_forward_ios_rounded
              : Icons.arrow_back_ios_new_rounded,
          size: 14,
          color: isBlockedOffline
              ? AppTheme.textTertiary
              : (isSelected ? AppTheme.primary : AppTheme.textTertiary),
        ),
      ),
      selected: isSelected,
      selectedTileColor: AppTheme.tabSurface,
      onTap: () {
        if (isSelected) {
          Navigator.pop(context);
          return;
        }
        _openRoute(routeName);
      },
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: AppTheme.textTertiary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
