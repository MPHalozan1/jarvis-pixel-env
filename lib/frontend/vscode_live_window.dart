import 'package:flutter/material.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**************
// Vgrajeni kirurški urejevalnik kode z zavihki in neposrednim mostom v VS Code *
//**************
class VsCodeLiveSurgicalWindow extends StatefulWidget {
  final UltronBrainRouter brain;
  final bool isDarkMode;

  const VsCodeLiveSurgicalWindow({
    super.key,
    required this.brain,
    required this.isDarkMode,
  });

  @override
  State<VsCodeLiveSurgicalWindow> createState() =>
      _VsCodeLiveSurgicalWindowState();
}

class _VsCodeLiveSurgicalWindowState extends State<VsCodeLiveSurgicalWindow> {
  final TextEditingController _editorCtrl = TextEditingController();
  String _boundPath = '';

  @override
  void initState() {
    super.initState();
    _syncEditorFromTab();
    widget.brain.addListener(_onBrainChanged);
  }

  @override
  void dispose() {
    widget.brain.removeListener(_onBrainChanged);
    _editorCtrl.dispose();
    super.dispose();
  }

  void _onBrainChanged() {
    if (!mounted) return;
    final tab = widget.brain.activeTab;
    if (tab == null) {
      _boundPath = '';
      _editorCtrl.text = '';
    } else if (tab.filePath != _boundPath) {
      _syncEditorFromTab();
    }
    setState(() {});
  }

  void _syncEditorFromTab() {
    final tab = widget.brain.activeTab;
    if (tab == null) return;
    _boundPath = tab.filePath;
    _editorCtrl.text = tab.lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final tab = widget.brain.activeTab;

    return Container(
      width: 440,
      decoration: BoxDecoration(
        color: hud.bgPanel.alphaPct(0.95),
        border: Border(
          left: BorderSide(color: hud.borderLine.alphaPct(0.9), width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zgornja orodna vrstica urejevalnika
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: hud.borderLine.alphaPct(0.8)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.code, size: 16, color: hud.primaryPeriwinkle),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Urejevalnik · ${widget.brain.activeExecutionModel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hud.textPrimary,
                    ),
                  ),
                ),
                if (tab != null) ...[
                  IconButton(
                    tooltip: 'Razveljavi zadnjo spremembo',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.undo_rounded,
                        size: 16, color: hud.textMuted),
                    onPressed: () {
                      widget.brain.undoLastEditOnActiveTab();
                      _syncEditorFromTab();
                    },
                  ),
                  IconButton(
                    tooltip: 'Shrani datoteko',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.save_outlined,
                      size: 16,
                      color: tab.isDirty
                          ? hud.accentWarningAmber
                          : hud.textMuted,
                    ),
                    onPressed: () => widget.brain.saveActiveTabContent(),
                  ),
                  IconButton(
                    tooltip: 'Pripni to datoteko v klepet',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.attach_file,
                        size: 16, color: hud.primaryPeriwinkle),
                    onPressed: () =>
                        widget.brain.attachFileFromPath(tab.filePath),
                  ),
                ],
                IconButton(
                  tooltip: 'Odpri v VS Code',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.open_in_new_rounded,
                      size: 15, color: hud.textMuted),
                  onPressed: widget.brain.openActiveFileInRealVsCode,
                ),
                IconButton(
                  tooltip: 'Zapri panel',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: hud.textMuted),
                  onPressed: widget.brain.closeVsCodeWindow,
                ),
              ],
            ),
          ),

          // Zavihki odprtih datotek
          if (widget.brain.openTabs.isNotEmpty)
            SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: widget.brain.openTabs.length,
                itemBuilder: (context, index) {
                  final t = widget.brain.openTabs[index];
                  final active = index == widget.brain.activeTabIndex;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => widget.brain.selectEditorTab(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? hud.primaryPeriwinkle.alphaPct(0.18)
                              : hud.bgInput.alphaPct(0.6),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: active
                                ? hud.primaryPeriwinkle.alphaPct(0.6)
                                : hud.borderLine.alphaPct(0.7),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${t.fileName}${t.isDirty ? " *" : ""}',
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    active ? hud.textPrimary : hud.textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => widget.brain.closeEditorTab(index),
                              child: Icon(Icons.close_rounded,
                                  size: 12, color: hud.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Zaznani kirurški predlogi popravkov
          if (widget.brain.detectedIssues.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: hud.accentWarningAmber.alphaPct(0.08),
              child: Column(
                children: widget.brain.detectedIssues.take(3).map((issue) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.auto_fix_high_rounded,
                            size: 14, color: hud.accentWarningAmber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Vrstica ${issue.lineNumber}: ${issue.description}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: hud.textPrimary),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await widget.brain
                                .fixIssueSurgicallyInPlace(issue);
                            _syncEditorFromTab();
                          },
                          child: const Text('Popravi',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          // Urejevalno polje
          Expanded(
            child: tab == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Klikni katerokoli datoteko v levem PC File Managerju za ogled in urejanje.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: hud.textMuted),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: _editorCtrl,
                      maxLines: null,
                      expands: true,
                      onChanged: widget.brain.updateActiveTabText,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12.2,
                        height: 1.45,
                        color: hud.textPrimary,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: hud.bgDeep.alphaPct(0.75),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: hud.borderLine.alphaPct(0.8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                              color: hud.borderLine.alphaPct(0.8)),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}