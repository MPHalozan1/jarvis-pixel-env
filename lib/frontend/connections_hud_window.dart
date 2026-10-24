import 'package:flutter/material.dart';
import '../backend/memory_learning_usage_service.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**************
// Nastavitveno HUD okno za: *
// 1. Skeniranje in izbiro lokalnih LLM-jev ter nastavitev GPU/VRAM slojev (num_gpu) *
// 2. Pregled in upravljanje dejansko naučenega znanja (Learn Vault) *
// 3. GitHub in zunanje integracije *
//**************
class ConnectionsHudWindow extends StatefulWidget {
  final UltronBrainRouter brain;
  final VoidCallback onClose;
  final int initialTab;

  const ConnectionsHudWindow({
    super.key,
    required this.brain,
    required this.onClose,
    this.initialTab = 0,
  });

  @override
  State<ConnectionsHudWindow> createState() => _ConnectionsHudWindowState();
}

class _ConnectionsHudWindowState extends State<ConnectionsHudWindow> {
  late int _tabIndex;
  late final TextEditingController _ollamaUrlCtrl;
  late final TextEditingController _ghTokenCtrl;
  late final TextEditingController _ruleTitleCtrl;
  late final TextEditingController _ruleBodyCtrl;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
    _ollamaUrlCtrl = TextEditingController(text: widget.brain.ollamaBaseUrl);
    _ghTokenCtrl = TextEditingController(text: widget.brain.githubToken);
    _ruleTitleCtrl = TextEditingController();
    _ruleBodyCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _ollamaUrlCtrl.dispose();
    _ghTokenCtrl.dispose();
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
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 580),
            child: HudBracketPanel(
              padding: const EdgeInsets.all(18),
              fillColor: hud.bgPanel.alphaPct(0.97),
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
                          'Modeli, Learn Vault & Povezave',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
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
                        icon: Icons.terminal_rounded,
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

  Widget _buildLocalLlmTab(UltronHudTheme hud) {
    final models = widget.brain.discoveredModels;

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
                label: 'Poveži D:/Disk modele',
                compact: true,
                onTap: () => widget.brain.startLocalOllamaServer(
                  customModelsPath: widget.brain.detectedDiskModelsFolder,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),

        // Drsnik za prilagoditev GPU slojev (num_gpu) in kontekstnega okna
        Container(
          padding: const EdgeInsets.all(11),
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
                    'Kontekst: ${widget.brain.contextWindowTokens}',
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
              Text(
                'Pusti na 0 za privzete nastavitve modela (npr. gemma2-gpu) ali ročno povišaj za večjo izrabo VRAM-a.',
                style: TextStyle(fontSize: 11, color: hud.textMuted),
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
              'Noben lokalni model še ni bil zaznan. Preveri, da si prenesel model (npr. gemma2:9b) in klikni "Skeniraj PC".',
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
                  color:
                      selected ? hud.primaryPeriwinkle : hud.textMuted,
                ),
                title: Text(
                  m.name,
                  style: TextStyle(
                    fontSize: 12.8,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
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
        // Ročno dodajanje trajnega pravila
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
                        'Nauči Ultrona trajno pravilo (npr. vedno piši komentarje v okvir)...',
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
                            tooltip: e.pinned ? 'Odpni' : 'Pripni v vrh konteksta',
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

  Widget _buildGithubTab(UltronHudTheme hud) {
    return Column(
      key: const ValueKey('gh_tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 35,
                child: TextField(
                  controller: _ghTokenCtrl,
                  obscureText: true,
                  style: TextStyle(fontSize: 12, color: hud.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'GitHub Personal Access Token...',
                    hintStyle: TextStyle(fontSize: 11.5, color: hud.textMuted),
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
            const SizedBox(width: 8),
            HudActionButton(
              label: 'Poveži',
              isPrimaryAccent: true,
              onTap: () =>
                  widget.brain.connectGithubWithToken(_ghTokenCtrl.text),
            ),
            const SizedBox(width: 6),
            HudActionButton(
              label: 'Ustvari žeton',
              icon: Icons.open_in_new_rounded,
              onTap: widget.brain.startGithubDeviceFlow,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.brain.isGithubConnected)
          Text(
            'Prijavljen kot ${widget.brain.githubUsername} · API kvota: ${widget.brain.githubRateLimitRemaining}/${widget.brain.githubRateLimitTotal}',
            style: TextStyle(fontSize: 11.5, color: hud.accentSuccessGreen),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: widget.brain.githubRepos.isEmpty
              ? Center(
                  child: Text(
                    'Poveži GitHub žeton za prikaz in kloniranje repozitorijev.',
                    style: TextStyle(fontSize: 12, color: hud.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.brain.githubRepos.length,
                  itemBuilder: (context, idx) {
                    final repo = widget.brain.githubRepos[idx];
                    return ListTile(
                      dense: true,
                      title: Text(repo.fullName,
                          style: TextStyle(
                              fontSize: 12, color: hud.textPrimary)),
                      trailing: HudActionButton(
                        label: 'Clone',
                        compact: true,
                        onTap: () =>
                            widget.brain.cloneRepoToDesktop(repo.cloneUrl),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}