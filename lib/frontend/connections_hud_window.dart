import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**********************************************************************
// PHASE 4 // SHARP HUD CONNECTIONS & USAGE LIMITS WINDOW              *
// Three Cards:                                                        *
// 1. GEMINI: Web Gemini Self-Prompt Bridge + Gemini API Key Verifier  *
// 2. GITHUB: OAuth Device Flow + PAT Fallback + Real /rate_limit      *
// 3. JULES: Official Jules v1alpha API + Web Session Launcher         *
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
  final TextEditingController _geminiKeyCtrl = TextEditingController();
  final TextEditingController _ghTokenCtrl = TextEditingController();
  final TextEditingController _ghClientIdCtrl = TextEditingController();
  final TextEditingController _ghUserCtrl = TextEditingController();
  final TextEditingController _julesKeyCtrl = TextEditingController();
  late final TextEditingController _dailyLimitCtrl;
  late final TextEditingController _weeklyLimitCtrl;

  @override
  void initState() {
    super.initState();
    _ghUserCtrl.text = widget.brain.githubUsername;
    _dailyLimitCtrl = TextEditingController(
      text: '${widget.brain.memoryService.dailyRequestLimit}',
    );
    _weeklyLimitCtrl = TextEditingController(
      text: '${widget.brain.memoryService.weeklyRequestLimit}',
    );
  }

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
    _ghTokenCtrl.dispose();
    _ghClientIdCtrl.dispose();
    _ghUserCtrl.dispose();
    _julesKeyCtrl.dispose();
    _dailyLimitCtrl.dispose();
    _weeklyLimitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final brain = widget.brain;

    return SizedBox(
      width: 860,
      height: 580,
      child: HudBracketPanel(
        padding: const EdgeInsets.all(18),
        borderColor: hud.primaryPeriwinkle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.hub_outlined, size: 17, color: hud.primaryPeriwinkle),
                const SizedBox(width: 8),
                Text(
                  'CONNECTIONS // GEMINI WEB BRIDGE, GITHUB & JULES API',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: hud.textPrimary,
                  ),
                ),
                const Spacer(),
                HudActionButton(
                  label: 'CLOSE [ESC]',
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
                  // CARD 1: GEMINI (WEB BRIDGE + API KEY)
                  _buildServiceCard(
                    hud: hud,
                    title: '01 // GEMINI (WEB SELF-PROMPT BRIDGE & REST API)',
                    isConnected: brain.isAnyGeminiConnected,
                    statusLabel: brain.isGeminiWebBridgeOnline
                        ? 'CONNECTED (WEB BRIDGE)'
                        : (brain.isGeminiApiConnected
                            ? 'CONNECTED (${brain.verifiedApiModels.length} API MODELS)'
                            : 'NOT CONNECTED'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Web Workflow: Opens Nov klepet on 3.5 Flash-Lite [Nizka] -> Asks best model (3.5 Flash-Lite, 3.8 Flash, 3.1 Pro, 4 Argon) & Raven razmišljanja (Nizka/Srednja/Visoka) -> Switches & pastes self-written prompt.',
                          style: TextStyle(fontSize: 10.5, color: hud.textMuted),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            HudActionButton(
                              label: 'CONNECT WEB GEMINI (NOV KLEPET BRIDGE)',
                              icon: Icons.open_in_browser,
                              isPrimaryAccent: true,
                              accentColor: hud.primaryPeriwinkle,
                              onTap: brain.launchWebGeminiBridgeAndBrowser,
                            ),
                            const SizedBox(width: 8),
                            if (brain.lastSelfWrittenPrompt.isNotEmpty)
                              HudActionButton(
                                label: 'COPY LAST SELF-PROMPT',
                                icon: Icons.copy,
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: brain.lastSelfWrittenPrompt,
                                    ),
                                  );
                                },
                              ),
                            const Spacer(),
                            if (brain.isAnyGeminiConnected)
                              HudActionButton(
                                label: 'DISCONNECT',
                                accentColor: hud.accentErrorRed,
                                onTap: brain.disconnectGemini,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: _geminiKeyCtrl,
                                  obscureText: true,
                                  style: const TextStyle(fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText:
                                        'Optional: Paste Google AI Studio API Key (Stored in flutter_secure_storage)',
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
                              label: 'VERIFY API KEY & MODELS',
                              icon: Icons.verified_outlined,
                              onTap: () =>
                                  brain.connectGeminiApiKey(_geminiKeyCtrl.text),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // CARD 2: GITHUB (OAUTH DEVICE FLOW + PAT + REAL RATE LIMIT)
                  _buildServiceCard(
                    hud: hud,
                    title:
                        '02 // GITHUB (DEVICE FLOW, PAT & REAL /rate_limit: ${brain.githubRateLimitRemaining}/${brain.githubRateLimitTotal})',
                    isConnected: brain.isGithubConnected,
                    statusLabel: brain.isGithubConnected
                        ? 'CONNECTED (@${brain.githubUsername} • ${brain.githubRepos.length} REPOS)'
                        : 'NOT CONNECTED',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                              label: 'CONNECT PAT',
                              icon: Icons.key,
                              onTap: () =>
                                  brain.connectGithubWithToken(_ghTokenCtrl.text),
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
                                        'Or OAuth Client ID for github.com/login/device flow',
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
                              label: 'START DEVICE FLOW',
                              icon: Icons.devices,
                              onTap: () => brain
                                  .startGithubDeviceFlow(_ghClientIdCtrl.text),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // CARD 3: JULES (OFFICIAL v1alpha API + WEB SESSION)
                  _buildServiceCard(
                    hud: hud,
                    title: '03 // GOOGLE JULES (v1alpha API & WEB SESSION)',
                    isConnected: brain.isJulesConnected,
                    statusLabel: brain.isJulesConnected
                        ? 'CONNECTED (${brain.julesSessions.length} SESSIONS)'
                        : 'NOT CONNECTED',
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 32,
                            child: TextField(
                              controller: _julesKeyCtrl,
                              obscureText: true,
                              style: const TextStyle(fontSize: 11),
                              decoration: InputDecoration(
                                hintText:
                                    'Jules API Key (GET https://jules.googleapis.com/v1alpha/sessions)',
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
                          label: 'CONNECT JULES API',
                          onTap: () => brain.connectJulesApi(_julesKeyCtrl.text),
                        ),
                        const SizedBox(width: 8),
                        HudActionButton(
                          label: 'OPEN JULES WEB',
                          icon: Icons.open_in_new,
                          onTap: () => brain.openWebUrl(brain.julesWebUrl),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // EDITABLE USAGE LIMITS
                  HudBracketPanel(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Text(
                          'LOCAL USAGE LIMITS (EDITABLE):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: hud.primaryPeriwinkle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          height: 30,
                          child: TextField(
                            controller: _dailyLimitCtrl,
                            style: const TextStyle(fontSize: 11),
                            decoration: const InputDecoration(
                              labelText: 'Daily Limit',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          height: 30,
                          child: TextField(
                            controller: _weeklyLimitCtrl,
                            style: const TextStyle(fontSize: 11),
                            decoration: const InputDecoration(
                              labelText: 'Weekly Limit',
                              isDense: true,
                            ),
                          ),
                        ),
                        const Spacer(),
                        HudActionButton(
                          label: 'SAVE LIMITS',
                          onTap: () {
                            brain.memoryService.updateEditableLimits(
                              newDailyLimit: int.tryParse(_dailyLimitCtrl.text),
                              newWeeklyLimit:
                                  int.tryParse(_weeklyLimitCtrl.text),
                            );
                          },
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

  Widget _buildServiceCard({
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
                  fontSize: 11.5,
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