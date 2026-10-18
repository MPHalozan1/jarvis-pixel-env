import 'package:flutter/material.dart';
import '../backend/connections_manager.dart';

//**********************************************************************
// CONNECTIONS, MODEL ROLE MAPPER & GITHUB DESKTOP CLONER WINDOW       *
// Interactive 3-Tab Management Window:                                *
// Tab 1: Provider Sign-In (Paste URL/Token, Sign In Locally)          *
// Tab 2: Role & Model Assignment (Rename agents & pick any model)     *
// Tab 3: GitHub Repo Browser (Select repo -> Clone to ~/Desktop)      *
//**********************************************************************

class ConnectionsManagementWindow extends StatefulWidget {
  final ConnectionsManager connections;
  final bool isDarkMode;
  final VoidCallback onClose;

  const ConnectionsManagementWindow({
    super.key,
    required this.connections,
    required this.isDarkMode,
    required this.onClose,
  });

  @override
  State<ConnectionsManagementWindow> createState() =>
      _ConnectionsManagementWindowState();
}

class _ConnectionsManagementWindowState
    extends State<ConnectionsManagementWindow> {
  int _activeTab = 0; // 0 = Providers Sign-In, 1 = Role/Model Mapper, 2 = GitHub Repos
  late final TextEditingController _ghUserController;
  late final TextEditingController _ghTokenController;
  late final TextEditingController _ghUrlController;

  @override
  void initState() {
    super.initState();
    _ghUserController =
        TextEditingController(text: widget.connections.githubUsername);
    _ghTokenController =
        TextEditingController(text: widget.connections.githubToken);
    _ghUrlController =
        TextEditingController(text: widget.connections.githubUrl);
  }

  @override
  void dispose() {
    _ghUserController.dispose();
    _ghTokenController.dispose();
    _ghUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final bg = isDark ? const Color(0xFF10131C) : Colors.white;
    final border = isDark ? const Color(0xFF283046) : const Color(0xFFCBD5E1);

    return ListenableBuilder(
      listenable: widget.connections,
      builder: (context, _) {
        final conn = widget.connections;

        return Container(
          width: 780,
          height: 540,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 28,
              ),
            ],
          ),
          child: Column(
            children: [
              // Window Header & Navigation Tabs
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0B0D14)
                      : const Color(0xFFF1F5F9),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(11)),
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hub, size: 18, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    const Text(
                      'CONNECTIONS, MODEL MAPPER & GITHUB CLONER',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    _buildTabButton(0, '1. Provider Sign-In', Icons.login),
                    const SizedBox(width: 6),
                    _buildTabButton(1, '2. Role & Model Map', Icons.people_alt),
                    const SizedBox(width: 6),
                    _buildTabButton(2, '3. GitHub -> Desktop', Icons.folder_copy),
                    const SizedBox(width: 10),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),

              // Main Tab Content Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _activeTab == 0
                      ? _buildProvidersSignInTab(conn, isDark, border)
                      : (_activeTab == 1
                          ? _buildRoleAndModelMapperTab(conn, isDark, border)
                          : _buildGithubClonerTab(conn, isDark, border)),
                ),
              ),

              // Status Footer
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        conn.statusMessage,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5),
                      ),
                    ),
                    Text(
                      'Desktop Dir: ${conn.desktopProjectsRoot}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSel = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel
              ? const Color(0xFF2563EB).withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSel ? const Color(0xFF38BDF8) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: const Color(0xFF38BDF8)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  //********************************************************************
  // TAB 1: UNIVERSAL PROVIDER SIGN-IN                                 *
  //********************************************************************
  Widget _buildProvidersSignInTab(
    ConnectionsManager conn,
    bool isDark,
    Color border,
  ) {
    return ListView.builder(
      itemCount: conn.providers.length,
      itemBuilder: (context, i) {
        final p = conn.providers[i];
        final urlCtrl = TextEditingController(text: p.loginUrl);
        final keyCtrl = TextEditingController(text: p.apiKeyOrSession);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161A28) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(color: p.brandColor, width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: (p.isSignedIn
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFF59E0B))
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p.isSignedIn ? 'SIGNED IN LOCALLY' : 'NOT SIGNED IN',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: p.isSignedIn
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (p.isSignedIn)
                    TextButton(
                      onPressed: () => conn.signOutProvider(p.id),
                      child: const Text(
                        'Sign Out',
                        style: TextStyle(fontSize: 10.5, color: Colors.redAccent),
                      ),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.brandColor,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 30),
                    ),
                    onPressed: () => conn.signInToProvider(
                      p.id,
                      customUrl: urlCtrl.text,
                      tokenInput: keyCtrl.text,
                    ),
                    icon: const Icon(Icons.login, size: 14),
                    label: Text(
                      p.isSignedIn ? 'Re-Authenticate' : 'Sign In Locally',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: urlCtrl,
                      style: const TextStyle(fontSize: 11),
                      decoration: const InputDecoration(
                        labelText: 'Connection / Sign-In URL',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: keyCtrl,
                      obscureText: true,
                      style: const TextStyle(fontSize: 11),
                      decoration: InputDecoration(
                        labelText:
                            'Optional API Key / Session (${p.cliCommand})',
                        isDense: true,
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
  // TAB 2: ROLE & MODEL MAPPER (RENAME & SWAP ANY AGENT'S MODEL)      *
  //********************************************************************
  Widget _buildRoleAndModelMapperTab(
    ConnectionsManager conn,
    bool isDark,
    Color border,
  ) {
    final entries = conn.roleAssignments.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1-Click Quick Preset Bar for Coding Agents
        Row(
          children: [
            const Text(
              'Quick Swap 4 Coding/Critic Desks:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => conn.swapAllCodingAgentsTo('codex_cli'),
              icon: const Icon(Icons.terminal, size: 14),
              label: const Text('Use OpenAI Codex', style: TextStyle(fontSize: 10.5)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => conn.swapAllCodingAgentsTo('claude_code_cli'),
              icon: const Icon(Icons.bolt, size: 14),
              label: const Text('Use Claude Code CLI', style: TextStyle(fontSize: 10.5)),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => conn.swapAllCodingAgentsTo('custom_provider'),
              icon: const Icon(Icons.memory, size: 14),
              label: const Text('Use Local Ollama', style: TextStyle(fontSize: 10.5)),
            ),
          ],
        ),
        const Divider(height: 18),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final role = entries[i];
              final currentProv = conn.getProviderById(role.providerId);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF161A28)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 185,
                      child: Text(
                        role.roleTitle,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Custom Character Name Field
                    SizedBox(
                      width: 140,
                      child: TextFormField(
                        initialValue: role.characterName,
                        style: const TextStyle(fontSize: 11),
                        decoration: const InputDecoration(
                          labelText: 'Agent Name',
                          isDense: true,
                        ),
                        onFieldSubmitted: (v) => conn.updateRoleAssignment(
                          role.slot,
                          newName: v,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Provider Dropdown
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: role.providerId,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Connection Provider',
                          isDense: true,
                        ),
                        items: conn.providers
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  p.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5),
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
                    const SizedBox(width: 12),
                    // Model Dropdown for Chosen Provider
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: currentProv.availableModels
                                .contains(role.selectedModel)
                            ? role.selectedModel
                            : currentProv.availableModels.first,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Model',
                          isDense: true,
                        ),
                        items: currentProv.availableModels
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  m,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5),
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
  // TAB 3: GITHUB REPO BROWSER & ONE-CLICK DESKTOP FOLDER CLONER      *
  //********************************************************************
  Widget _buildGithubClonerTab(
    ConnectionsManager conn,
    bool isDark,
    Color border,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GitHub Sign-In & Fetch Row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ghUrlController,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  labelText: 'Git Website URL',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ghUserController,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  labelText: 'GitHub Username / Org',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ghTokenController,
                obscureText: true,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  labelText: 'Personal Access Token (Optional)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
              ),
              onPressed: conn.isFetchingRepos
                  ? null
                  : () => conn.connectAndFetchGithubRepos(
                        username: _ghUserController.text,
                        token: _ghTokenController.text,
                        customGitWebsite: _ghUrlController.text,
                      ),
              icon: const Icon(Icons.cloud_download, size: 15),
              label: Text(
                conn.isFetchingRepos ? 'Loading...' : 'Sign In & Fetch Repos',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Repository List
        Expanded(
          child: ListView.builder(
            itemCount: conn.repositories.length,
            itemBuilder: (context, i) {
              final repo = conn.repositories[i];
              final isActive = conn.activeProjectRepo?.fullName == repo.fullName;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                      : (isDark
                          ? const Color(0xFF161A28)
                          : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive ? const Color(0xFF22C55E) : border,
                    width: isActive ? 1.6 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      repo.isClonedToDesktop
                          ? Icons.folder_special
                          : Icons.book_outlined,
                      color: repo.isClonedToDesktop
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${repo.fullName} (${repo.defaultBranch})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            repo.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey,
                            ),
                          ),
                          if (repo.localDesktopPath != null)
                            Text(
                              'Desktop Folder: ${repo.localDesktopPath}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF38BDF8),
                        foregroundColor: Colors.black,
                      ),
                      onPressed: conn.isCloningRepo
                          ? null
                          : () => conn.cloneAndSelectRepoOnDesktop(repo),
                      icon: Icon(
                        isActive ? Icons.check_circle : Icons.download_for_offline,
                        size: 15,
                      ),
                      label: Text(
                        isActive
                            ? 'Assigned on Desktop'
                            : (repo.isClonedToDesktop
                                ? 'Assign Agents'
                                : 'Clone to Desktop & Assign'),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
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
}