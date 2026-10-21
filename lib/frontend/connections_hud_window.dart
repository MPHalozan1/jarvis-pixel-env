import 'package:flutter/material.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**********************************************************************
// LOCAL OLLAMA ENGINE & GITHUB GIT CONTROL HUD WINDOW                 *
// - Configures local Ollama (http://127.0.0.1:11434) & Qwen 14B model *
// - GitHub PAT / Device Flow login + Direct Git Pull / Commit / Push  *
//**********************************************************************

class ConnectionsHudWindow extends StatefulWidget {
  final UltronBrainRouter brain;
  final VoidCallback onClose;

  const ConnectionsHudWindow({
    super.key,
    required this.brain,
    required this.onClose,
  });

  @override
  State<ConnectionsHudWindow> createState() => _ConnectionsHudWindowState();
}

class _ConnectionsHudWindowState extends State<ConnectionsHudWindow> {
  late final TextEditingController _ollamaUrlCtrl;
  final TextEditingController _ghTokenCtrl = TextEditingController();
  final TextEditingController _ghClientIdCtrl = TextEditingController();
  final TextEditingController _commitMsgCtrl = TextEditingController(
    text: 'feat: update via Ultron Qwen2.5-Coder-14B',
  );

  @override
  void initState() {
    super.initState();
    _ollamaUrlCtrl = TextEditingController(text: widget.brain.ollamaBaseUrl);
  }

  @override
  void dispose() {
    _ollamaUrlCtrl.dispose();
    _ghTokenCtrl.dispose();
    _ghClientIdCtrl.dispose();
    _commitMsgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final brain = widget.brain;

    return SizedBox(
      width: 840,
      height: 560,
      child: HudBracketPanel(
        padding: const EdgeInsets.all(18),
        borderColor: hud.primaryPeriwinkle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory_sharp, size: 17, color: hud.primaryPeriwinkle),
                const SizedBox(width: 8),
                Text(
                  'LOCAL OLLAMA ENGINE (QWEN2.5-CODER:14B) & GITHUB GIT CONTROL',
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
            Divider(height: 20, color: hud.borderLine),

            Expanded(
              child: ListView(
                children: [
                  // CARD 1: LOCAL OLLAMA ENGINE
                  _buildSectionCard(
                    hud: hud,
                    title: '01 // LOCAL OLLAMA ENGINE (INTEL ARC B570)',
                    isConnected: brain.isOllamaOnline,
                    statusLabel: brain.isOllamaOnline
                        ? 'ONLINE (${brain.activeLocalModel})'
                        : 'OFFLINE',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _ollamaUrlCtrl,
                                  style: const TextStyle(fontSize: 11),
                                  decoration: InputDecoration(
                                    labelText: 'Ollama Local Endpoint',
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
                              label: 'PING & DETECT MODELS',
                              icon: Icons.refresh,
                              isPrimaryAccent: true,
                              accentColor: hud.primaryPeriwinkle,
                              onTap: () {
                                brain.ollamaBaseUrl =
                                    _ollamaUrlCtrl.text.trim();
                                brain.checkLocalOllamaHealth();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: brain.installedOllamaModels.map((m) {
                            final isSel = m == brain.activeLocalModel;
                            return HudActionButton(
                              label: m,
                              icon: isSel
                                  ? Icons.check_circle_outline
                                  : Icons.smart_toy_outlined,
                              isPrimaryAccent: isSel,
                              accentColor: isSel
                                  ? hud.accentSuccessGreen
                                  : hud.primaryPeriwinkle,
                              onTap: () => brain.selectLocalOllamaModel(m),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // CARD 2: GIT PULL / COMMIT / PUSH AUTOMATION
                  _buildSectionCard(
                    hud: hud,
                    title:
                        '02 // WORKSPACE GIT AUTOMATION (BRANCH: ${brain.currentGitBranch.toUpperCase()})',
                    isConnected: true,
                    statusLabel: 'WORKSPACE: ${brain.workspaceRootPath.split('/').last}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _commitMsgCtrl,
                                  style: const TextStyle(fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText: 'Git commit message...',
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
                              label: 'GIT PULL',
                              icon: Icons.download_sharp,
                              onTap: brain.gitPull,
                            ),
                            const SizedBox(width: 6),
                            HudActionButton(
                              label: 'GIT COMMIT',
                              icon: Icons.check_sharp,
                              accentColor: hud.accentSuccessGreen,
                              onTap: () => brain.gitCommitAndPush(
                                commitMessage: _commitMsgCtrl.text,
                                pushAfter: false,
                              ),
                            ),
                            const SizedBox(width: 6),
                            HudActionButton(
                              label: 'COMMIT & PUSH',
                              icon: Icons.cloud_upload_sharp,
                              isPrimaryAccent: true,
                              accentColor: hud.primaryPeriwinkle,
                              onTap: () => brain.gitCommitAndPush(
                                commitMessage: _commitMsgCtrl.text,
                                pushAfter: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: hud.bgInput,
                          child: Text(
                            'LAST GIT OUTPUT: ${brain.lastGitCommandOutput}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: hud.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // CARD 3: GITHUB SIGN-IN (PAT OR OAUTH DEVICE FLOW)
                  _buildSectionCard(
                    hud: hud,
                    title:
                        '03 // GITHUB AUTHENTICATION (RATE LIMIT: ${brain.githubRateLimitRemaining}/${brain.githubRateLimitTotal})',
                    isConnected: brain.isGithubConnected,
                    statusLabel: brain.isGithubConnected
                        ? 'SIGNED IN (@${brain.githubUsername})'
                        : 'PUBLIC / CLI MODE',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _ghTokenCtrl,
                                  obscureText: true,
                                  style: const TextStyle(fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText:
                                        'GitHub Personal Access Token (ghp_... / github_pat_...)',
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
                              label: 'SIGN IN WITH PAT',
                              icon: Icons.key_sharp,
                              onTap: () => brain
                                  .connectGithubWithToken(_ghTokenCtrl.text),
                            ),
                            const SizedBox(width: 8),
                            HudActionButton(
                              label: 'OPEN GITHUB.COM',
                              icon: Icons.open_in_new,
                              onTap: () =>
                                  brain.openWebUrl(brain.githubWebUrl),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _ghClientIdCtrl,
                                  style: const TextStyle(fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Or GitHub OAuth Client ID for github.com/login/device',
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
                              label: 'DEVICE FLOW SIGN-IN',
                              icon: Icons.devices_sharp,
                              onTap: () => brain.startGithubDeviceFlow(
                                _ghClientIdCtrl.text,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required UltronHudTheme hud,
    required String title,
    required bool isConnected,
    required String statusLabel,
    required Widget child,
  }) {
    final statusCol =
        isConnected ? hud.accentSuccessGreen : hud.accentWarningAmber;
    return HudBracketPanel(
      borderColor: isConnected ? hud.primaryPeriwinkle : hud.borderLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: hud.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: statusCol),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: statusCol,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}