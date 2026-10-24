import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/memory_learning_usage_service.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**************
// Osrednje nastavitveno in povezovalno okno ULTRON: *
// 1. Lokalni LLM skener, nastavitve GPU slojev (num_gpu) in kontekstnega okna (num_ctx) *
// 2. Pregled in urejanje naučenih pravil (Learn Vault) *
// 3. Moderno GitHub prijavno okno (1-Klik Sistem/CLI, Device Flow koda, PAT) + Repo Manager *
//**************
class ConnectionsHudWindow extends StatefulWidget {
  final UltronBrainRouter brain;
  final VoidCallback onClose;
  final int initialTab;
  final ValueChanged<String>? onToast;

  const ConnectionsHudWindow({
    super.key,
    required this.brain,
    required this.onClose,
    this.initialTab = 0,
    this.onToast,
  });

  @override
  State<ConnectionsHudWindow> createState() => _ConnectionsHudWindowState();
}

class _ConnectionsHudWindowState extends State<ConnectionsHudWindow> {
  late int _tabIndex;
  int _ghAuthModeIndex = 0; // 0 = 1-Klik Sistem & Žeton, 1 = Device Flow Brskalnik
  bool _obscureToken = true;
  String _repoSearchQuery = '';
  int _repoVisibilityFilter = 0; // 0 = Vsi, 1 = Zasebni, 2 = Javni

  late final TextEditingController _ollamaUrlCtrl;
  late final TextEditingController _ghTokenCtrl;
  late final TextEditingController _ghClientIdCtrl;
  late final TextEditingController _repoSearchCtrl;
  late final TextEditingController _ruleTitleCtrl;
  late final TextEditingController _ruleBodyCtrl;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
    _ollamaUrlCtrl = TextEditingController(text: widget.brain.ollamaBaseUrl);
    _ghTokenCtrl = TextEditingController(text: widget.brain.githubToken);
    _ghClientIdCtrl =
        TextEditingController(text: widget.brain.githubOAuthClientId);
    _repoSearchCtrl = TextEditingController();
    _ruleTitleCtrl = TextEditingController();
    _ruleBodyCtrl = TextEditingController();
    widget.brain.refreshLocalGitStatus();
  }

  @override
  void dispose() {
    _ollamaUrlCtrl.dispose();
    _ghTokenCtrl.dispose();
    _ghClientIdCtrl.dispose();
    _repoSearchCtrl.dispose();
    _ruleTitleCtrl.dispose();
    _ruleBodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return ListenableBuilder(
      listenable: Listenable.merge([widget.brain, widget.brain.memoryService]),
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740, maxHeight: 620),
            child: HudBracketPanel(
              padding: const EdgeInsets.all(18),
              fillColor: hud.bgPanel.alphaPct(0.98),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hub_outlined,
                          size: 18, color: hud.primaryPeriwinkle),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'ULTRON · Modeli, Learn Vault & GitHub',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: hud.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close_rounded,
                            size: 18, color: hud.textMuted),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      HudActionButton(
                        label: 'Lokalni LLM-ji',
                        icon: Icons.memory_rounded,
                        badgeText: '${widget.brain.discoveredModels.length}',
                        isPrimaryAccent: _tabIndex == 0,
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      HudActionButton(
                        label: 'Learn Vault',
                        icon: Icons.psychology_alt,
                        badgeText:
                            '${widget.brain.memoryService.learnedEntries.length}',
                        isPrimaryAccent: _tabIndex == 1,
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                      const SizedBox(width: 8),
                      HudActionButton(
                        label: 'GitHub',
                        icon: widget.brain.isGithubConnected
                            ? Icons.verified_user_outlined
                            : Icons.account_circle_outlined,
                        accentColor: widget.brain.isGithubConnected
                            ? hud.accentSuccessGreen
                            : hud.primaryPeriwinkle,
                        badgeText: widget.brain.isGithubConnected
                            ? '@${widget.brain.githubUsername}'
                            : null,
                        isPrimaryAccent: _tabIndex == 2,
                        onTap: () => setState(() => _tabIndex = 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: hud.borderLine.alphaPct(0.8)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutCubic,
                      child: _tabIndex == 0
                          ? _buildLocalLlmTab(hud)
                          : _tabIndex == 1
                              ? _buildLearnVaultTab(hud)
                              : _buildGithubTab(hud),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  //**************
  // Zavihek 0: Skener lokalnih LLM-jev ter nastavitve VRAM slojev in konteksta *
  //**************
  Widget _buildLocalLlmTab(UltronHudTheme hud) {
    final models = widget.brain.discoveredModels;
    const ctxPresets = [2048, 4096, 6144, 8192, 16384];

    return ListView(
      key: const ValueKey('llm_tab'),
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.brain.isOllamaOnline
                    ? hud.accentSuccessGreen
                    : hud.accentErrorRed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.brain.isOllamaOnline
                    ? 'Ollama strežnik aktiven (${models.length} zaznanih modelov na PC-ju)'
                    : 'Ollama strežnik ni dosegljiv',
                style: TextStyle(fontSize: 12.5, color: hud.textPrimary),
              ),
            ),
            if (!widget.brain.isOllamaOnline)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: HudActionButton(
                  label: 'Zaženi Ollama strežnik',
                  icon: Icons.auto_awesome,
                  compact: true,
                  accentColor: hud.accentSuccessGreen,
                  isPrimaryAccent: true,
                  onTap: () => widget.brain.startLocalOllamaServer(),
                ),
              ),
            HudActionButton(
              label: widget.brain.isScanningModels
                  ? 'Skeniram...'
                  : 'Skeniraj PC',
              icon: Icons.refresh_rounded,
              compact: true,
              onTap: widget.brain.isScanningModels
                  ? null
                  : () => widget.brain
                      .checkLocalOllamaHealth(newBaseUrl: _ollamaUrlCtrl.text),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _ollamaUrlCtrl,
                  style: TextStyle(fontSize: 12, color: hud.textPrimary),
                  onSubmitted: (val) =>
                      widget.brain.checkLocalOllamaHealth(newBaseUrl: val),
                  decoration: InputDecoration(
                    labelText: 'Ollama API naslov',
                    labelStyle: TextStyle(fontSize: 11, color: hud.textMuted),
                    filled: true,
                    fillColor: hud.bgInput.alphaPct(0.75),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.brain.detectedDiskModelsFolder != null) ...[
              const SizedBox(width: 8),
              HudActionButton(
                label: 'Poveži Disk modele',
                compact: true,
                onTap: () => widget.brain.startLocalOllamaServer(
                  customModelsPath: widget.brain.detectedDiskModelsFolder,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hud.bgInput.alphaPct(0.45),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: hud.borderLine.alphaPct(0.7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'GPU VRAM sloji (num_gpu): ${widget.brain.customNumGpuLayers == 0 ? "Samodejno / Modelfile" : widget.brain.customNumGpuLayers}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: hud.textPrimary,
                    ),
                  ),
                  Text(
                    'Max kontekst: ${widget.brain.contextWindowTokens} tok',
                    style: TextStyle(fontSize: 11.5, color: hud.textMuted),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 2.5),
                child: Slider(
                  value: widget.brain.customNumGpuLayers.toDouble(),
                  min: 0,
                  max: 50,
                  divisions: 50,
                  onChanged: (v) =>
                      widget.brain.updateGpuSettings(numGpu: v.round()),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Velikost konteksta (VRAM varovalka):',
                    style: TextStyle(fontSize: 11, color: hud.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: ctxPresets.map((ctxVal) {
                        final active =
                            widget.brain.contextWindowTokens == ctxVal;
                        return HudActionButton(
                          label: '$ctxVal',
                          compact: true,
                          isPrimaryAccent: active,
                          onTap: () =>
                              widget.brain.updateGpuSettings(numCtx: ctxVal),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Zaznani lokalni modeli na tem računalniku:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: hud.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        if (models.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Noben lokalni model še ni bil zaznan. Klikni "Skeniraj PC".',
              style: TextStyle(fontSize: 12, color: hud.textMuted),
            ),
          )
        else
          ...models.map((m) {
            final selected = m.name == widget.brain.activeLocalModel;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: selected
                    ? hud.primaryPeriwinkle.alphaPct(0.15)
                    : hud.bgInput.alphaPct(0.45),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? hud.primaryPeriwinkle.alphaPct(0.75)
                      : hud.borderLine.alphaPct(0.7),
                ),
              ),
              child: ListTile(
                dense: true,
                onTap: () => widget.brain.selectLocalOllamaModel(m.name),
                leading: Icon(
                  selected ? Icons.check_rounded : Icons.memory_rounded,
                  size: 18,
                  color: selected ? hud.primaryPeriwinkle : hud.textMuted,
                ),
                title: Text(
                  m.name,
                  style: TextStyle(
                    fontSize: 12.8,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: hud.textPrimary,
                  ),
                ),
                subtitle: Text(
                  m.displaySubtitle,
                  style: TextStyle(fontSize: 11, color: hud.textMuted),
                ),
                trailing: selected
                    ? Text(
                        'AKTIVEN',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: hud.primaryPeriwinkle,
                        ),
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }

  //**************
  // Zavihek 1: Pregled in dodajanje naučenih pravil (Learn Vault) *
  //**************
  Widget _buildLearnVaultTab(UltronHudTheme hud) {
    final mem = widget.brain.memoryService;

    return Column(
      key: const ValueKey('learn_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                mem.lastLearnSummary,
                style: TextStyle(fontSize: 12, color: hud.textMuted),
              ),
            ),
            Row(
              children: [
                Text('Auto-Learn',
                    style: TextStyle(fontSize: 11.5, color: hud.textMuted)),
                Switch(
                  value: mem.autoLearnEnabled,
                  onChanged: mem.setAutoLearn,
                ),
              ],
            ),
            const SizedBox(width: 6),
            HudActionButton(
              label: mem.isLearningNow ? 'Učim se...' : 'Zaženi Learn zdaj',
              icon: Icons.psychology_alt,
              isPrimaryAccent: true,
              accentColor: hud.accentSuccessGreen,
              onTap: mem.isLearningNow
                  ? null
                  : () => widget.brain.triggerLearnPass(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 150,
              height: 32,
              child: TextField(
                controller: _ruleTitleCtrl,
                style: TextStyle(fontSize: 11.5, color: hud.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Naslov pravila...',
                  hintStyle: TextStyle(fontSize: 11, color: hud.textMuted),
                  filled: true,
                  fillColor: hud.bgInput.alphaPct(0.75),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(5),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _ruleBodyCtrl,
                  style: TextStyle(fontSize: 11.5, color: hud.textPrimary),
                  onSubmitted: (_) => _submitManualRule(),
                  decoration: InputDecoration(
                    hintText:
                        'Nauči ULTRON trajno pravilo (npr. slog komentarjev)...',
                    hintStyle: TextStyle(fontSize: 11, color: hud.textMuted),
                    filled: true,
                    fillColor: hud.bgInput.alphaPct(0.75),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(5),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            HudActionButton(
              label: 'Dodaj',
              icon: Icons.add_rounded,
              compact: true,
              onTap: _submitManualRule,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: mem.learnedEntries.isEmpty
              ? Center(
                  child: Text(
                    'Še ni naučenih pravil. Klikni "Zaženi Learn zdaj" za analizo trenutne kode in klepeta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: hud.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: mem.learnedEntries.length,
                  itemBuilder: (context, idx) {
                    final LearningEntry e = mem.learnedEntries[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: hud.bgInput.alphaPct(0.45),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: e.pinned
                              ? hud.primaryPeriwinkle.alphaPct(0.55)
                              : hud.borderLine.alphaPct(0.65),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${e.title} · ${e.category}',
                                  style: TextStyle(
                                    fontSize: 11.8,
                                    fontWeight: FontWeight.w600,
                                    color: hud.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  e.rule,
                                  style: TextStyle(
                                      fontSize: 11.5, color: hud.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip:
                                e.pinned ? 'Odpni' : 'Pripni v vrh konteksta',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              e.pinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              size: 15,
                              color: e.pinned
                                  ? hud.primaryPeriwinkle
                                  : hud.textMuted,
                            ),
                            onPressed: () => mem.togglePinEntry(e.id),
                          ),
                          IconButton(
                            tooltip: 'Izbriši pravilo',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 15, color: hud.textMuted),
                            onPressed: () => mem.deleteEntry(e.id),
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

  void _submitManualRule() {
    if (_ruleBodyCtrl.text.trim().isEmpty) return;
    widget.brain.memoryService.addManualRule(
      title: _ruleTitleCtrl.text,
      rule: _ruleBodyCtrl.text,
    );
    _ruleTitleCtrl.clear();
    _ruleBodyCtrl.clear();
  }

  //**************
  // Zavihek 2: Prenovljeno GitHub prijavno okno in upravitelj repozitorijev *
  //**************
  Widget _buildGithubTab(UltronHudTheme hud) {
    if (!widget.brain.isGithubConnected) {
      return _buildGithubSignInPortal(hud);
    }
    return _buildGithubConnectedWorkspace(hud);
  }

  Widget _buildGithubSignInPortal(UltronHudTheme hud) {
    final b = widget.brain;

    return ListView(
      key: const ValueKey('gh_signin_portal'),
      children: [
        // Zgornja predstavitvena kartica ULTRON x GitHub
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                hud.primaryPeriwinkle.alphaPct(0.14),
                hud.secondaryVioletBloom.alphaPct(0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(hud.cutRadius),
            border: Border.all(color: hud.primaryPeriwinkle.alphaPct(0.40)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hud.bgDeep.alphaPct(0.85),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: hud.primaryPeriwinkle.alphaPct(0.55)),
                ),
                child: Icon(
                  Icons.hub_rounded,
                  size: 23,
                  color: hud.primaryPeriwinkle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prijava v GitHub · ULTRON Sync',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: hud.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Poveži svoj račun za takojšen dostop do javnih in zasebnih repozitorijev, 1-klik kloniranje v ULTRON in sinhronizacijo projektov.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: hud.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Preklopnik med načinoma prijave
        Row(
          children: [
            Expanded(
              child: HudActionButton(
                label: '1-Klik Sistem & Hitri Žeton',
                icon: Icons.login_rounded,
                isPrimaryAccent: _ghAuthModeIndex == 0,
                onTap: () => setState(() => _ghAuthModeIndex = 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: HudActionButton(
                label: 'Device Flow Koda (Brskalnik)',
                icon: Icons.qr_code_rounded,
                isPrimaryAccent: _ghAuthModeIndex == 1,
                onTap: () => setState(() => _ghAuthModeIndex = 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Status ali morebitno opozorilo med prijavljanjem
        if (b.githubAuthStatus.isNotEmpty || b.githubAuthError.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: b.githubAuthError.isNotEmpty
                  ? hud.accentErrorRed.alphaPct(0.12)
                  : hud.primaryPeriwinkle.alphaPct(0.12),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: b.githubAuthError.isNotEmpty
                    ? hud.accentErrorRed.alphaPct(0.50)
                    : hud.primaryPeriwinkle.alphaPct(0.45),
              ),
            ),
            child: Row(
              children: [
                if (b.isGithubAuthenticating) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: hud.primaryPeriwinkle,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  Icon(
                    b.githubAuthError.isNotEmpty
                        ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: b.githubAuthError.isNotEmpty
                        ? hud.accentErrorRed
                        : hud.primaryPeriwinkle,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    b.githubAuthError.isNotEmpty
                        ? b.githubAuthError
                        : b.githubAuthStatus,
                    style: TextStyle(
                      fontSize: 11.8,
                      color: hud.textPrimary,
                    ),
                  ),
                ),
                if (b.isGithubAuthenticating)
                  HudActionButton(
                    label: 'Prekliči',
                    compact: true,
                    accentColor: hud.accentErrorRed,
                    onTap: b.cancelGithubAuthFlow,
                  ),
              ],
            ),
          ),

        // Vsebina izbranega načina prijave
        if (_ghAuthModeIndex == 0)
          _buildSystemAndPatAuthCard(hud, b)
        else
          _buildDeviceFlowAuthCard(hud, b),

        // Če je trenutna lokalna mapa že Git repozitorij, prikažemo status tudi brez prijave
        if (b.localGitBranch.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildLocalGitStrip(hud, b),
        ],
      ],
    );
  }

  Widget _buildSystemAndPatAuthCard(
    UltronHudTheme hud,
    UltronBrainRouter b,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hud.bgInput.alphaPct(0.48),
        borderRadius: BorderRadius.circular(hud.cutRadius),
        border: Border.all(color: hud.borderLine.alphaPct(0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Možnost A · Samodejna prijava iz računalnika (Priporočeno)',
            style: TextStyle(
              fontSize: 12.2,
              fontWeight: FontWeight.w700,
              color: hud.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Samodejno uporabi obstoječo GitHub prijavo iz VS Code / Git Credential Managerja ali GitHub CLI (gh) oz. odpre varno prijavo v brskalniku.',
            style: TextStyle(fontSize: 11.2, color: hud.textMuted),
          ),
          const SizedBox(height: 10),
          HudActionButton(
            label: b.isGithubAuthenticating
                ? 'Povezujem z GitHubom...'
                : '1-Klik Prijava prek Sistema / Brskalnika',
            icon: Icons.bolt_rounded,
            isPrimaryAccent: true,
            accentColor: hud.accentSuccessGreen,
            onTap: b.isGithubAuthenticating
                ? null
                : () async {
                    final ok = await b.connectGithubFromSystemCredentials();
                    if (ok) {
                      widget.onToast?.call(
                          'GitHub povezan (@${b.githubUsername})');
                    }
                  },
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: hud.borderLine.alphaPct(0.75)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Možnost B · Hitri osebni žeton (Personal Access Token)',
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: hud.textPrimary,
                  ),
                ),
              ),
              HudActionButton(
                label: 'Odpri ustvarjalnik žetona',
                icon: Icons.open_in_new_rounded,
                compact: true,
                onTap: b.openGithubQuickTokenCreator,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _ghTokenCtrl,
                    obscureText: _obscureToken,
                    onSubmitted: (val) => b.connectGithubWithToken(val),
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      color: hud.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'ghp_... ali github_pat_...',
                      hintStyle:
                          TextStyle(fontSize: 11.5, color: hud.textMuted),
                      filled: true,
                      fillColor: hud.bgDeep.alphaPct(0.75),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      suffixIcon: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 15,
                          color: hud.textMuted,
                        ),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            BorderSide(color: hud.borderLine.alphaPct(0.8)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            BorderSide(color: hud.borderLine.alphaPct(0.8)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'Prilepi & Poveži',
                icon: Icons.content_paste_rounded,
                onTap: b.isGithubAuthenticating
                    ? null
                    : () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        final pasted = data?.text?.trim() ?? '';
                        if (pasted.isNotEmpty) {
                          _ghTokenCtrl.text = pasted;
                          final ok = await b.connectGithubWithToken(pasted);
                          if (ok) {
                            widget.onToast?.call(
                                'GitHub povezan (@${b.githubUsername})');
                          }
                        }
                      },
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'Prijava',
                icon: Icons.check_circle_outline,
                isPrimaryAccent: true,
                onTap: b.isGithubAuthenticating
                    ? null
                    : () async {
                        final ok = await b
                            .connectGithubWithToken(_ghTokenCtrl.text);
                        if (ok) {
                          widget.onToast?.call(
                              'GitHub povezan (@${b.githubUsername})');
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceFlowAuthCard(
    UltronHudTheme hud,
    UltronBrainRouter b,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hud.bgInput.alphaPct(0.48),
        borderRadius: BorderRadius.circular(hud.cutRadius),
        border: Border.all(color: hud.borderLine.alphaPct(0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'GitHub OAuth Device Flow ([github.com/login/device](https://github.com/login/device))',
                  style: TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    color: hud.textPrimary,
                  ),
                ),
              ),
              HudActionButton(
                label: 'Registriraj OAuth App',
                icon: Icons.open_in_new_rounded,
                compact: true,
                onTap: () =>
                    b.openWebUrl('[https://github.com/settings/applications/new](https://github.com/settings/applications/new)'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Vnesi Client ID svoje GitHub OAuth aplikacije (z vklopljeno možnostjo "Enable Device Flow") za prijavo z 8-mestno kodo v brskalniku.',
            style: TextStyle(fontSize: 11.2, color: hud.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _ghClientIdCtrl,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      color: hud.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'GitHub OAuth Client ID (npr. Ov23li...)',
                      hintStyle:
                          TextStyle(fontSize: 11.5, color: hud.textMuted),
                      filled: true,
                      fillColor: hud.bgDeep.alphaPct(0.75),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            BorderSide(color: hud.borderLine.alphaPct(0.8)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              HudActionButton(
                label: 'Generiraj kodo & Odpri brskalnik',
                icon: Icons.qr_code_rounded,
                isPrimaryAccent: true,
                onTap: b.isGithubAuthenticating
                    ? null
                    : () => b.startGithubDeviceFlow(
                          customClientId: _ghClientIdCtrl.text,
                        ),
              ),
            ],
          ),
          if (b.githubDeviceUserCode.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hud.bgDeep.alphaPct(0.90),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hud.accentSuccessGreen.alphaPct(0.65),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TVOJA ENKRATNA PRIJAVNA KODA:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                            color: hud.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          b.githubDeviceUserCode,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3.0,
                            color: hud.accentSuccessGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  HudActionButton(
                    label: 'Kopiraj kodo',
                    icon: Icons.copy_rounded,
                    onTap: () async {
                      await Clipboard.setData(
                          ClipboardData(text: b.githubDeviceUserCode));
                      widget.onToast?.call('Koda kopirana v odložišče');
                    },
                  ),
                  const SizedBox(width: 8),
                  HudActionButton(
                    label: 'Odpri stran',
                    icon: Icons.open_in_new_rounded,
                    isPrimaryAccent: true,
                    onTap: () => b.openWebUrl(b.githubDeviceVerificationUri),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  //**************
  // Povezani pogled: Profilna kartica + Lokalni Git + Iskalnik in Kloniranje repozitorijev *
  //**************
  Widget _buildGithubConnectedWorkspace(UltronHudTheme hud) {
    final b = widget.brain;

    final filteredRepos = b.githubRepos.where((repo) {
      if (_repoVisibilityFilter == 1 && !repo.isPrivate) return false;
      if (_repoVisibilityFilter == 2 && repo.isPrivate) return false;
      if (_repoSearchQuery.isNotEmpty) {
        final q = _repoSearchQuery.toLowerCase();
        return repo.fullName.toLowerCase().contains(q) ||
            repo.description.toLowerCase().contains(q) ||
            repo.language.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Column(
      key: const ValueKey('gh_connected_workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Bogata profilna kartica prijavljenega uporabnika
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: hud.bgInput.alphaPct(0.55),
            borderRadius: BorderRadius.circular(hud.cutRadius),
            border: Border.all(color: hud.accentSuccessGreen.alphaPct(0.45)),
          ),
          child: Row(
            children: [
              ClipOval(
                child: Container(
                  width: 40,
                  height: 40,
                  color: hud.bgDeep,
                  child: b.githubAvatarUrl.isNotEmpty
                      ? Image.network(
                          b.githubAvatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person_outline_rounded,
                            color: hud.primaryPeriwinkle,
                          ),
                        )
                      : Icon(
                          Icons.person_outline_rounded,
                          color: hud.primaryPeriwinkle,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            b.githubDisplayName.isNotEmpty
                                ? b.githubDisplayName
                                : b.githubUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.2,
                              fontWeight: FontWeight.w700,
                              color: hud.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '@${b.githubUsername}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: hud.accentSuccessGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Javni: ${b.githubPublicReposCount} · Zasebni: ${b.githubPrivateReposCount} · API kvota: ${b.githubRateLimitRemaining}/${b.githubRateLimitTotal}',
                      style: TextStyle(fontSize: 11, color: hud.textMuted),
                    ),
                  ],
                ),
              ),
              HudActionButton(
                label: b.isFetchingRepos ? 'Osvežujem...' : 'Osveži',
                icon: Icons.refresh_rounded,
                compact: true,
                onTap: b.isFetchingRepos ? null : b.fetchGithubRepos,
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'Odjava',
                icon: Icons.logout_rounded,
                compact: true,
                accentColor: hud.accentErrorRed,
                onTap: () {
                  _ghTokenCtrl.clear();
                  b.disconnectGithub();
                },
              ),
            ],
          ),
        ),

        // 2. Vrstica lokalnega Git repozitorija (če je trenutna mapa povezana z Gitom)
        if (b.localGitBranch.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildLocalGitStrip(hud, b),
        ],

        const SizedBox(height: 10),

        // 3. Iskalna in filtrirna vrstica repozitorijev
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _repoSearchCtrl,
                  onChanged: (v) => setState(() => _repoSearchQuery = v),
                  style: TextStyle(fontSize: 12, color: hud.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 15, color: hud.textMuted),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, maxHeight: 28),
                    hintText:
                        'Išči po repozitorijih, opisu ali jeziku (Dart, C#, Python...)...',
                    hintStyle: TextStyle(fontSize: 11.2, color: hud.textMuted),
                    filled: true,
                    fillColor: hud.bgInput.alphaPct(0.70),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            HudActionButton(
              label: 'Vsi (${b.githubRepos.length})',
              compact: true,
              isPrimaryAccent: _repoVisibilityFilter == 0,
              onTap: () => setState(() => _repoVisibilityFilter = 0),
            ),
            const SizedBox(width: 5),
            HudActionButton(
              label: 'Zasebni',
              icon: Icons.lock_outline_rounded,
              compact: true,
              isPrimaryAccent: _repoVisibilityFilter == 1,
              onTap: () => setState(() => _repoVisibilityFilter = 1),
            ),
            const SizedBox(width: 5),
            HudActionButton(
              label: 'Javni',
              icon: Icons.public_rounded,
              compact: true,
              isPrimaryAccent: _repoVisibilityFilter == 2,
              onTap: () => setState(() => _repoVisibilityFilter = 2),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 4. Seznam repozitorijev z interaktivnimi karticami
        Expanded(
          child: b.isFetchingRepos && b.githubRepos.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: hud.primaryPeriwinkle,
                  ),
                )
              : filteredRepos.isEmpty
                  ? Center(
                      child: Text(
                        'Ni ujemajočih se repozitorijev.',
                        style: TextStyle(fontSize: 12, color: hud.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredRepos.length,
                      itemBuilder: (context, idx) {
                        final repo = filteredRepos[idx];
                        final isCloningThis =
                            b.cloningRepoFullName == repo.fullName;

                        return _GithubRepoTile(
                          repo: repo,
                          isCloning: isCloningThis,
                          onOpenWeb: () => b.openWebUrl(repo.htmlUrl),
                          onCloneAndOpen: b.cloningRepoFullName != null
                              ? null
                              : () async {
                                  final path = await b.cloneRepoAndOpenInUltron(
                                    repo,
                                    openAsActiveProject: true,
                                  );
                                  if (path != null) {
                                    widget.onToast?.call(
                                      'Odprt projekt iz GitHuba: ${repo.name}',
                                    );
                                    widget.onClose();
                                  } else {
                                    widget.onToast?.call(
                                      'Kloniranje ni uspelo (preveri Git namestitev)',
                                    );
                                  }
                                },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildLocalGitStrip(UltronHudTheme hud, UltronBrainRouter b) {
    final targetName = b.hasActiveProject
        ? b.activeProjectName
        : 'Trenutna mapa brskalnika';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: hud.bgDeep.alphaPct(0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hud.borderLine.alphaPct(0.8)),
      ),
      child: Row(
        children: [
          Icon(Icons.call_split_rounded,
              size: 14, color: hud.primaryPeriwinkle),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '$targetName · veja "${b.localGitBranch}" · ${b.localGitChangedCount == 0 ? "čisto stanje" : "${b.localGitChangedCount} spremenjenih datotek"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.2, color: hud.textPrimary),
            ),
          ),
          HudActionButton(
            label: b.isSyncingLocalGit ? 'Sinhroniziram...' : 'Git Pull',
            icon: Icons.sync_rounded,
            compact: true,
            onTap: b.isSyncingLocalGit
                ? null
                : () async {
                    final ok = await b.pullCurrentGitWorkspace();
                    widget.onToast?.call(
                      ok ? 'Git Pull uspešen' : 'Git Pull ni uspel',
                    );
                  },
          ),
        ],
      ),
    );
  }
}

class _GithubRepoTile extends StatefulWidget {
  final GitHubRepoEntry repo;
  final bool isCloning;
  final VoidCallback onOpenWeb;
  final VoidCallback? onCloneAndOpen;

  const _GithubRepoTile({
    required this.repo,
    required this.isCloning,
    required this.onOpenWeb,
    required this.onCloneAndOpen,
  });

  @override
  State<_GithubRepoTile> createState() => _GithubRepoTileState();
}

class _GithubRepoTileState extends State<_GithubRepoTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final r = widget.repo;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _hovered
              ? hud.bgInput.alphaPct(0.78)
              : hud.bgInput.alphaPct(0.42),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: _hovered
                ? hud.primaryPeriwinkle.alphaPct(0.55)
                : hud.borderLine.alphaPct(0.75),
          ),
        ),
        child: Row(
          children: [
            Icon(
              r.isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded,
              size: 16,
              color: r.isPrivate ? hud.accentWarningAmber : hud.primaryPeriwinkle,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.4,
                            fontWeight: FontWeight.w600,
                            color: hud.textPrimary,
                          ),
                        ),
                      ),
                      if (r.language.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: hud.primaryPeriwinkle.alphaPct(0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            r.language,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: hud.primaryPeriwinkle,
                            ),
                          ),
                        ),
                      ],
                      if (r.stargazersCount > 0) ...[
                        const SizedBox(width: 7),
                        Icon(Icons.star_border_rounded,
                            size: 12, color: hud.textMuted),
                        const SizedBox(width: 2),
                        Text(
                          '${r.stargazersCount}',
                          style: TextStyle(fontSize: 10.5, color: hud.textMuted),
                        ),
                      ],
                    ],
                  ),
                  if (r.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      r.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: hud.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Odpri na GitHubu',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.open_in_new_rounded,
                  size: 15, color: hud.textMuted),
              onPressed: widget.onOpenWeb,
            ),
            const SizedBox(width: 4),
            HudActionButton(
              label: widget.isCloning ? 'Kloniram...' : 'Clone & Odpri',
              icon: Icons.download_rounded,
              compact: true,
              isPrimaryAccent: _hovered || widget.isCloning,
              onTap: widget.onCloneAndOpen,
            ),
          ],
        ),
      ),
    );
  }
}