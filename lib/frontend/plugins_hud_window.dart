import 'package:flutter/material.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**************
// Minimalistično okno za upravljanje vtičnikov in uvoz iz GitHuba *
//**************
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
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final svc = widget.brain.pluginService;

    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
            child: HudBracketPanel(
              padding: const EdgeInsets.all(18),
              fillColor: hud.bgPanel.alphaPct(0.97),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.extension_outlined,
                          size: 18, color: hud.primaryPeriwinkle),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Vtičniki in spretnosti',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: hud.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        svc.statusMessage,
                        style: TextStyle(fontSize: 11, color: hud.textMuted),
                      ),
                      const SizedBox(width: 8),
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
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            controller: _searchCtrl,
                            style:
                                TextStyle(fontSize: 12, color: hud.textPrimary),
                            onSubmitted: svc.searchGithubPlugins,
                            decoration: InputDecoration(
                              hintText:
                                  'Poišči na GitHubu ali prilepi URL vtičnika...',
                              hintStyle: TextStyle(
                                  fontSize: 11.5, color: hud.textMuted),
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
                        label: 'Išči',
                        icon: Icons.search_rounded,
                        onTap: () =>
                            svc.searchGithubPlugins(_searchCtrl.text),
                      ),
                      const SizedBox(width: 6),
                      HudActionButton(
                        label: 'Namesti URL',
                        isPrimaryAccent: true,
                        onTap: () =>
                            svc.installPluginFromGithubUrl(_searchCtrl.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        Text(
                          'Nameščeni vtičniki:',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hud.textMuted),
                        ),
                        const SizedBox(height: 6),
                        ...svc.installedPlugins.map((p) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: hud.bgInput.alphaPct(0.45),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: hud.borderLine.alphaPct(0.7)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontSize: 12.2,
                                          fontWeight: FontWeight.w600,
                                          color: hud.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        p.description,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: hud.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: p.enabled,
                                  onChanged: (v) =>
                                      svc.approveAndTogglePlugin(p.id, v),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.delete_outline_rounded,
                                      size: 16, color: hud.textMuted),
                                  onPressed: () => svc.uninstallPlugin(p.id),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (svc.browseResults.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'GitHub zadetki:',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: hud.textMuted),
                          ),
                          const SizedBox(height: 6),
                          ...svc.browseResults.map((r) {
                            return ListTile(
                              dense: true,
                              title: Text(r.name,
                                  style: TextStyle(
                                      fontSize: 12, color: hud.textPrimary)),
                              subtitle: Text(r.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: hud.textMuted)),
                              trailing: HudActionButton(
                                label: 'Namesti',
                                compact: true,
                                onTap: () =>
                                    svc.installPluginFromGithubUrl(r.repoUrl),
                              ),
                            );
                          }),
                        ],
                      ],
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
}