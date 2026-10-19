import 'dart:math';
import 'package:flutter/material.dart';
import '../backend/connections_manager.dart';

//**********************************************************************
// SLEEK CONTROL-DECK MANAGEMENT WINDOW (ZERO ANALYZER WARNINGS)       *
// Styled after the Dark-Navy / Neon-Pink / Electric-Cyan UI reference:*
// - Top Notification Pill ("Notification: Operation complete!")       *
// - Breadcrumb Category Navigation (01 > 02 > 03 > 04)                *
// - Glowing Pink & Cyan "Login" / "Choose" / "Details" Pill Buttons   *
// - Adjustment Sliders with White-Ring Thumbs & Segmented Meters      *
//**********************************************************************

class ConnectionsManagementWindow extends StatefulWidget {
  final ConnectionsManager connections;
  final bool isDarkMode;
  final VoidCallback onClose;
  final int initialTab;

  const ConnectionsManagementWindow({
    super.key,
    required this.connections,
    required this.isDarkMode,
    required this.onClose,
    this.initialTab = 0,
  });

  @override
  State<ConnectionsManagementWindow> createState() =>
      _ConnectionsManagementWindowState();
}

class _ConnectionsManagementWindowState
    extends State<ConnectionsManagementWindow>
    with SingleTickerProviderStateMixin {
  static const Color _navyBg = Color(0xFF171B2D);
  static const Color _cardBg = Color(0xFF1F253D);
  static const Color _cardBorder = Color(0xFF343D5E);
  static const Color _neonPink = Color(0xFFF43F5E);
  static const Color _neonCyan = Color(0xFF00D2FF);

  late int _activeTab;
  late final AnimationController _spinnerController;

  // Persistent controllers so typing never resets
  final Map<String, TextEditingController> _urlControllers = {};
  final Map<String, TextEditingController> _addModelControllers = {};
  late final TextEditingController _ghUrlController;
  late final TextEditingController _ghUserController;
  late final TextEditingController _ghTokenController;
  final TextEditingController _newRuleController = TextEditingController();
  final String _newRuleCategory = 'Code Style';

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _spinnerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    for (final p in widget.connections.providers) {
      _urlControllers[p.id] = TextEditingController(text: p.websiteUrl);
      _addModelControllers[p.id] = TextEditingController();
    }
    _ghUrlController =
        TextEditingController(text: widget.connections.githubUrl);
    _ghUserController =
        TextEditingController(text: widget.connections.githubUsername);
    _ghTokenController =
        TextEditingController(text: widget.connections.githubToken);
  }

  @override
  void dispose() {
    _spinnerController.dispose();
    for (final c in _urlControllers.values) {
      c.dispose();
    }
    for (final c in _addModelControllers.values) {
      c.dispose();
    }
    _ghUrlController.dispose();
    _ghUserController.dispose();
    _ghTokenController.dispose();
    _newRuleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.connections,
      builder: (context, child) {
        final conn = widget.connections;

        return Container(
          width: 880,
          height: 590,
          decoration: BoxDecoration(
            color: _navyBg.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cardBorder, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 36,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              // 1. TOP NOTIFICATION BANNER + BREADCRUMB NAVIGATION
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Sleek Notification Banner
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF212742), Color(0xFF191E33)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _cardBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _neonPink,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: _neonPink,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  conn.lastNotificationTitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    conn.statusMessage,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Close Button
                        InkWell(
                          onTap: widget.onClose,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _neonPink.withValues(alpha: 0.7),
                              ),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: _neonPink,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Category 01 > Category 02 > Category 03 > Category 04 Breadcrumbs
                    Row(
                      children: [
                        _buildBreadcrumbTab(
                          0,
                          '01',
                          'AI Websites Sign-In',
                          _neonCyan,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: _neonPink,
                          ),
                        ),
                        _buildBreadcrumbTab(
                          1,
                          '02',
                          'Model Hierarchy',
                          _neonPink,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: _neonPink,
                          ),
                        ),
                        _buildBreadcrumbTab(
                          2,
                          '03',
                          'GitHub Cloner',
                          _neonCyan,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: _neonPink,
                          ),
                        ),
                        _buildBreadcrumbTab(
                          3,
                          '04',
                          'Sliders & Learning (${conn.learnedRules.length})',
                          _neonPink,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(color: _cardBorder, height: 1),

              // 2. MAIN CONTENT AREA
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _activeTab == 0
                      ? _buildTab1Websites(conn)
                      : _activeTab == 1
                          ? _buildTab2ModelHierarchy(conn)
                          : _activeTab == 2
                              ? _buildTab3GithubCloner(conn)
                              : _buildTab4SlidersAndLearning(conn),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumbTab(
    int index,
    String badgeNum,
    String title,
    Color accentColor,
  ) {
    final isSel = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSel
              ? accentColor.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSel ? accentColor : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSel ? accentColor : const Color(0xFF28304D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badgeNum,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isSel ? Colors.black : Colors.white70,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                color: isSel ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //********************************************************************
  // TAB 1: SLEEK WEBSITE LOGIN CARDS (GEMINI, JULES, GITHUB)          *
  //********************************************************************
  Widget _buildTab1Websites(ConnectionsManager conn) {
    return ListView.builder(
      itemCount: conn.providers.length,
      itemBuilder: (context, i) {
        final p = conn.providers[i];
        final urlCtrl = _urlControllers[p.id]!;
        final addModelCtrl = _addModelControllers[p.id]!;
        final isPink = i % 2 == 1;
        final accent = isPink ? _neonPink : _neonCyan;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.isSignedIn ? accent : Colors.transparent,
                      border: Border.all(color: accent, width: 2),
                      boxShadow: p.isSignedIn
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          p.websiteUrl,
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Animated Radial Spinner when Signing In
                  if (p.isSigningIn)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: AnimatedBuilder(
                          animation: _spinnerController,
                          builder: (context, child) => CustomPaint(
                            painter: NeonRadialSpinnerPainter(
                              progress: _spinnerController.value,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Sleek "Login" Button
                  InkWell(
                    onTap: () => conn.signInToWebsite(
                      p.id,
                      customWebsiteUrl: urlCtrl.text,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: _navyBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accent, width: 1.4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline, size: 17, color: accent),
                          const SizedBox(width: 8),
                          Text(
                            p.isSignedIn ? 'Open Session' : 'Login',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Glowing Pill Button
                  InkWell(
                    onTap: () => conn.signInToWebsite(
                      p.id,
                      customWebsiteUrl: urlCtrl.text,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isPink
                              ? [const Color(0xFFEC4899), const Color(0xFFE11D48)]
                              : [const Color(0xFF00D2FF), const Color(0xFF0284C7)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        p.isSignedIn ? 'Connected' : 'Verify',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: urlCtrl,
                      style: const TextStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        labelText: 'Official Website Link',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF151929),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: addModelCtrl,
                      style: const TextStyle(fontSize: 12.5),
                      onSubmitted: (v) {
                        conn.addCustomModelToWebsite(p.id, v);
                        addModelCtrl.clear();
                      },
                      decoration: InputDecoration(
                        labelText: 'Add Model Name (Press Enter)',
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF151929),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  //********************************************************************
  // TAB 2: MODEL HIERARCHY MAPPER (USES initialValue WITH ValueKey)   *
  //********************************************************************
  Widget _buildTab2ModelHierarchy(ConnectionsManager conn) {
    final entries = conn.roleAssignments.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Argon High (Final)  •  3.1 Pro Mid (Srednja Audit)  •  3.8 Flash Mid (Coders)  •  3.8 Flash High (Critiques)  •  Jules (Overflow)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: conn.applyGeminiWebPreset,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFFE11D48)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Reset Default Hierarchy',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final role = entries[i];
              final currentProv = conn.getProviderById(role.providerId);
              final activeModel = currentProv.availableModels
                      .contains(role.selectedModel)
                  ? role.selectedModel
                  : currentProv.availableModels.first;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _cardBorder),
                ),
                child: Row(
                  children: [
                    // Role Title
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            role.roleTitle,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Agent: ${role.characterName}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Website Provider Dropdown
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('prov_${role.slot.name}_${role.providerId}'),
                        initialValue: role.providerId,
                        isExpanded: true,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'AI Website',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF151929),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: conn.providers
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  p.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            conn.updateRoleAssignment(
                              role.slot,
                              newProviderId: val,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Assigned Model Dropdown
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('mod_${role.slot.name}_$activeModel'),
                        initialValue: activeModel,
                        isExpanded: true,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: 'Assigned Model',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF151929),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: currentProv.availableModels
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  m,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            conn.updateRoleAssignment(
                              role.slot,
                              newModel: val,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  //********************************************************************
  // TAB 3: GITHUB SIGN-IN (https://github.com/) & DESKTOP CLONER      *
  //********************************************************************
  Widget _buildTab3GithubCloner(ConnectionsManager conn) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _ghUrlController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'GitHub Website',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF151929),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _ghUserController,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'GitHub Username',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF151929),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _ghTokenController,
                  obscureText: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Optional PAT Token',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF151929),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Login to https://github.com/ Button
              InkWell(
                onTap: conn.signInToGithubOnWeb,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151929),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _neonCyan),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.person_outline, size: 16, color: _neonCyan),
                      SizedBox(width: 6),
                      Text(
                        'Login Web',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Fetch Repos Pill Button
              InkWell(
                onTap: conn.isFetchingRepos
                    ? null
                    : () => conn.connectAndFetchGithubRepos(
                          username: _ghUserController.text,
                          token: _ghTokenController.text,
                          customGitWebsite: _ghUrlController.text,
                        ),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D2FF), Color(0xFF0284C7)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    conn.isFetchingRepos ? 'Syncing...' : 'Fetch Repos',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.builder(
            itemCount: conn.repositories.length,
            itemBuilder: (context, i) {
              final repo = conn.repositories[i];
              final isActive =
                  conn.activeProjectRepo?.fullName == repo.fullName;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? _neonCyan : _cardBorder,
                    width: isActive ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            repo.fullName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            repo.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          if (repo.localDesktopPath != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Desktop Folder: ${repo.localDesktopPath}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _neonCyan,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: conn.isCloningRepo
                          ? null
                          : () => conn.cloneAndSelectRepoOnDesktop(repo),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isActive
                                ? [const Color(0xFFEC4899), const Color(0xFFE11D48)]
                                : [const Color(0xFF00D2FF), const Color(0xFF0284C7)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? 'Assigned' : 'Choose & Clone',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  //********************************************************************
  // TAB 4: ADJUSTMENT SLIDERS & ADAPTIVE LEARNING                     *
  //********************************************************************
  Widget _buildTab4SlidersAndLearning(ConnectionsManager conn) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Adjustment Sliders Card
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Adjustment Sliders',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                _buildNeonSliderRow(
                  label: '3.8 Flash High Critique Strictness',
                  value: conn.critiqueStrictness,
                  min: 0.4,
                  max: 1.0,
                  activeColor: _neonPink,
                  leftTag: '4.0',
                  rightTag: (conn.critiqueStrictness * 10).toStringAsFixed(1),
                  onChanged: (v) => conn.updateSliders(strictness: v),
                ),
                const SizedBox(height: 12),
                _buildNeonSliderRow(
                  label: 'Jules Session Quota Trigger',
                  value: conn.tokenQuotaThreshold,
                  min: 0.5,
                  max: 1.0,
                  activeColor: _neonCyan,
                  leftTag: '50%',
                  rightTag: '${(conn.tokenQuotaThreshold * 100).round()}%',
                  onChanged: (v) => conn.updateSliders(quotaThreshold: v),
                ),
                const SizedBox(height: 12),
                _buildNeonSliderRow(
                  label: 'Pixel Agent Walk Speed',
                  value: conn.agentWalkSpeedMultiplier,
                  min: 0.5,
                  max: 2.0,
                  activeColor: const Color(0xFFA855F7),
                  leftTag: '0.5x',
                  rightTag: '${conn.agentWalkSpeedMultiplier.toStringAsFixed(1)}x',
                  onChanged: (v) => conn.updateSliders(speedMultiplier: v),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => conn.updateSliders(
                          strictness: 0.85,
                          quotaThreshold: 0.90,
                          speedMultiplier: 1.0,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEC4899), Color(0xFFE11D48)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Details / Reset',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(
                          () => conn.autoLearnEnabled = !conn.autoLearnEnabled,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF151929),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _cardBorder),
                          ),
                          child: Text(
                            conn.autoLearnEnabled
                                ? 'Auto-Learn: ON'
                                : 'Auto-Learn: OFF',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Right Column: Learned Rules List
        Expanded(
          flex: 6,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newRuleController,
                        style: const TextStyle(fontSize: 12),
                        onSubmitted: (v) {
                          conn.recordLearnedPattern(
                            category: _newRuleCategory,
                            ruleText: v,
                            learnedFrom: 'Director Manual Input',
                          );
                          _newRuleController.clear();
                        },
                        decoration: InputDecoration(
                          hintText: 'Teach new rule to 3.8 Flash & 3.1 Pro...',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF151929),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () {
                        conn.recordLearnedPattern(
                          category: _newRuleCategory,
                          ruleText: _newRuleController.text,
                          learnedFrom: 'Director Manual Input',
                        );
                        _newRuleController.clear();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00D2FF), Color(0xFF0284C7)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Add Rule',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: conn.learnedRules.length,
                    itemBuilder: (context, i) {
                      final r = conn.learnedRules[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151929),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.ruleText,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${r.category} • ${r.learnedFrom} • ${(r.confidence * 100).round()}% confidence',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontStyle: FontStyle.italic,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => conn.deleteLearnedRule(r.id),
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 17,
                                color: _neonPink,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNeonSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color activeColor,
    required String leftTag,
    required String rightTag,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1)),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            activeTrackColor: activeColor,
            inactiveTrackColor: const Color(0xFF121626),
            thumbColor: activeColor,
            overlayColor: activeColor.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              leftTag,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            ),
            Text(
              rightTag,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: activeColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

//**********************************************************************
// NEON RADIAL SPINNER PAINTER                                         *
//**********************************************************************
class NeonRadialSpinnerPainter extends CustomPainter {
  final double progress;
  final Color color;

  NeonRadialSpinnerPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const ticks = 12;

    for (int i = 0; i < ticks; i++) {
      final angle = (i / ticks) * 2 * pi;
      final activeIndex = (progress * ticks).floor() % ticks;
      final dist = (i - activeIndex + ticks) % ticks;
      final alpha = (1.0 - (dist / ticks)).clamp(0.15, 1.0);

      final p1 = Offset(
        center.dx + cos(angle) * (radius * 0.48),
        center.dy + sin(angle) * (radius * 0.48),
      );
      final p2 = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );

      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NeonRadialSpinnerPainter oldDelegate) => true;
}