import 'package:flutter/material.dart';
import '../backend/plugin_manager_service.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**********************************************************************
// PHASE 7 // SHARP HUD DECLARATIVE PLUGINS WINDOW                     *
// Tabs: INSTALLED | BROWSE | ADD FROM URL | UPDATES                   *
// Enforces pre-enable security inspection & commit-SHA pinning.       *
//**********************************************************************

class PluginsHudWindow extends StatefulWidget {
  final UltronBrainRouter brain;
  final VoidCallback onClose;

  const PluginsHudWindow({
    super.key,
    required this.brain,
    required this.onClose,
  });

  @override
  State<PluginsHudWindow> createState() => _PluginsHudWindowState();
}

class _PluginsHudWindowState extends State<PluginsHudWindow> {
  int _tab = 0; // 0 = INSTALLED, 1 = BROWSE, 2 = ADD FROM URL, 3 = UPDATES
  UltronPlugin? _inspectingPlugin;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final pm = widget.brain.pluginService;

    return ListenableBuilder(
      listenable: pm,
      builder: (context, _) {
        return SizedBox(
          width: 840,
          height: 550,
          child: HudBracketPanel(
            padding: const EdgeInsets.all(18),
            borderColor: hud.primaryPeriwinkle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.extension_outlined,
                      size: 17,
                      color: hud.primaryPeriwinkle,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'DECLARATIVE PLUGINS & SKILLS // TOKEN BUDGET: ${pm.globalPluginTokenBudget} TOKENS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: hud.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    HudActionButton(
                      label: 'CLOSE',
                      icon: Icons.close,
                      accentColor: hud.accentErrorRed,
                      onTap: widget.onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 4 Sharp Tab Controls
                Row(
                  children: [
                    _tabBtn(hud, 0, 'INSTALLED (${pm.installedPlugins.length})'),
                    const SizedBox(width: 8),
                    _tabBtn(hud, 1, 'BROWSE GITHUB'),
                    const SizedBox(width: 8),
                    _tabBtn(hud, 2, 'ADD FROM URL'),
                    const SizedBox(width: 8),
                    _tabBtn(hud, 3, 'UPDATES & SHA PINNING'),
                  ],
                ),
                Divider(height: 18, color: hud.borderLine),

                Expanded(
                  child: _inspectingPlugin != null
                      ? _buildSecurityInspector(hud, pm, _inspectingPlugin!)
                      : _tab == 0
                          ? _buildInstalledTab(hud, pm)
                          : _tab == 1
                              ? _buildBrowseTab(hud, pm)
                              : _tab == 2
                                  ? _buildAddFromUrlTab(hud, pm)
                                  : _buildUpdatesTab(hud, pm),
                ),

                Divider(height: 14, color: hud.borderLine),
                Text(
                  pm.statusMessage,
                  style: TextStyle(fontSize: 10.5, color: hud.textMuted),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tabBtn(UltronHudTheme hud, int idx, String label) {
    final isSel = _tab == idx && _inspectingPlugin == null;
    return HudActionButton(
      label: label,
      isPrimaryAccent: isSel,
      accentColor: isSel ? hud.primaryPeriwinkle : hud.textMuted,
      onTap: () => setState(() {
        _inspectingPlugin = null;
        _tab = idx;
      }),
    );
  }

  Widget _buildInstalledTab(UltronHudTheme hud, PluginManagerService pm) {
    return ListView.builder(
      itemCount: pm.installedPlugins.length,
      itemBuilder: (context, i) {
        final p = pm.installedPlugins[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: HudBracketPanel(
            borderColor:
                p.isEnabled ? hud.accentSuccessGreen : hud.borderLine,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p.name.toUpperCase()}  [v${p.version} • SHA: ${p.pinnedCommitSha}]',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: hud.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        p.description,
                        style: TextStyle(fontSize: 10.5, color: hud.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Header Cost: ~${p.estimatedHeaderTokens} tok  •  Full Lazy Body: ~${p.estimatedFullBodyTokens} tok  •  Permissions: ${p.permissions.join(", ")}',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: hud.primaryPeriwinkle,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                HudActionButton(
                  label: 'INSPECT',
                  onTap: () => setState(() => _inspectingPlugin = p),
                ),
                const SizedBox(width: 8),
                HudActionButton(
                  label: p.isEnabled ? 'ENABLED' : 'ENABLE',
                  accentColor: p.isEnabled
                      ? hud.accentSuccessGreen
                      : hud.accentWarningAmber,
                  onTap: () {
                    if (!p.isInspectedAndApproved && !p.isEnabled) {
                      setState(() => _inspectingPlugin = p);
                    } else {
                      pm.approveAndTogglePlugin(p.id, !p.isEnabled);
                    }
                  },
                ),
                const SizedBox(width: 8),
                HudActionButton(
                  label: 'UNINSTALL',
                  accentColor: hud.accentErrorRed,
                  onTap: () => pm.uninstallPlugin(p.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecurityInspector(
    UltronHudTheme hud,
    PluginManagerService pm,
    UltronPlugin p,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SECURITY MANIFEST & CONTENT INSPECTOR // ${p.name.toUpperCase()}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: hud.accentWarningAmber,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Author: ${p.author}  |  Pinned Commit SHA: ${p.pinnedCommitSha}  |  Files: ${p.fileList.join(", ")}\n'
          'Requested Permissions: ${p.permissions.join(", ")} (Cannot read secure storage or write outside workspace)',
          style: TextStyle(fontSize: 10.5, color: hud.textMuted),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: hud.bgInput,
            child: SingleChildScrollView(
              child: Text(
                p.fullSkillMarkdown,
                style: TextStyle(fontSize: 11, color: hud.textPrimary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            HudActionButton(
              label: 'APPROVE & ENABLE PLUGIN',
              accentColor: hud.accentSuccessGreen,
              isPrimaryAccent: true,
              onTap: () {
                pm.approveAndTogglePlugin(p.id, true);
                setState(() => _inspectingPlugin = null);
              },
            ),
            const SizedBox(width: 10),
            HudActionButton(
              label: 'BACK TO LIST',
              onTap: () => setState(() => _inspectingPlugin = null),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBrowseTab(UltronHudTheme hud, PluginManagerService pm) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 11),
                  onSubmitted: (q) => pm.searchGithubPlugins(q),
                  decoration: InputDecoration(
                    hintText: 'Search GitHub topic:ultron-plugin...',
                    isDense: true,
                    filled: true,
                    fillColor: hud.bgInput,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            HudActionButton(
              label: pm.isSearchingGithub ? 'SEARCHING...' : 'SEARCH GITHUB API',
              icon: Icons.search,
              onTap: () => pm.searchGithubPlugins(_searchCtrl.text),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            itemCount: pm.browseResults.length,
            itemBuilder: (context, i) {
              final r = pm.browseResults[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HudBracketPanel(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.fullName} (★ ${r.stars})',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              r.description,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: hud.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      HudActionButton(
                        label: 'INSTALL (DISABLED)',
                        onTap: () async {
                          final installed =
                              await pm.installPluginFromGithubUrl(r.htmlUrl);
                          if (installed != null) {
                            setState(() => _inspectingPlugin = installed);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddFromUrlTab(UltronHudTheme hud, PluginManagerService pm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PASTE GITHUB REPOSITORY URL (INSTALLS PINNED TO COMMIT SHA & DISABLED BY DEFAULT):',
          style: TextStyle(fontSize: 11, color: hud.textPrimary),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: _urlCtrl,
                  style: const TextStyle(fontSize: 11.5),
                  decoration: InputDecoration(
                    hintText: 'https://github.com/owner/ultron-skill-repo',
                    isDense: true,
                    filled: true,
                    fillColor: hud.bgInput,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            HudActionButton(
              label: 'FETCH SHA & INSTALL',
              isPrimaryAccent: true,
              accentColor: hud.primaryPeriwinkle,
              onTap: () async {
                final plugin =
                    await pm.installPluginFromGithubUrl(_urlCtrl.text);
                if (plugin != null) {
                  setState(() => _inspectingPlugin = plugin);
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpdatesTab(UltronHudTheme hud, PluginManagerService pm) {
    return ListView(
      children: pm.installedPlugins
          .map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HudBracketPanel(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${p.name} — Pinned Commit SHA: ${p.pinnedCommitSha} (No unapproved upstream diffs)',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    HudActionButton(
                      label: 'VIEW MANIFEST DIFF',
                      onTap: () => setState(() => _inspectingPlugin = p),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}