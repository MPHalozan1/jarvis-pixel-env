import 'package:flutter/material.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**********************************************************************
// PHASE 6 // BUILT-IN EDITABLE VS CODE WINDOW & DIFF HUNK REVIEWER    *
// Features:                                                           *
// - Multi-tab bar with Git status indicators (M, CLEAN)               *
// - Editable code buffer with syntax highlighting & Save / Undo       *
// - Interactive Diff Hunk queue (ACCEPT HUNK / REJECT HUNK)           *
// - Auto-Apply toggle & external Code-OSS launcher                    *
//**********************************************************************

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
  final SyntaxHighlightingController _editorController =
      SyntaxHighlightingController();
  String _loadedTabPath = '';

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  void _syncControllerWithActiveTab(OpenEditorTab? tab) {
    if (tab == null) {
      _loadedTabPath = '';
      _editorController.text = '';
      return;
    }
    final joined = tab.lines.join('\n');
    if (_loadedTabPath != tab.filePath || _editorController.text != joined) {
      _loadedTabPath = tab.filePath;
      _editorController.text = joined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final brain = widget.brain;
    final tab = brain.activeTab;
    _syncControllerWithActiveTab(tab);

    return HudBracketPanel(
      padding: const EdgeInsets.all(14),
      borderColor: hud.primaryPeriwinkle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP TOOLBAR
          Row(
            children: [
              Icon(Icons.terminal_sharp, size: 16, color: hud.primaryPeriwinkle),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LIVE WORKSPACE EDITOR // ${tab?.fileName ?? "NO FILE"} [GIT: ${tab?.gitStatusBadge ?? "N/A"}]',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: hud.textPrimary,
                  ),
                ),
              ),
              // Auto-Apply Diff Toggle
              HudActionButton(
                label: brain.autoApplyEdits ? 'AUTO-APPLY: ON' : 'AUTO-APPLY: OFF',
                accentColor: brain.autoApplyEdits
                    ? hud.accentSuccessGreen
                    : hud.textMuted,
                onTap: () {
                  brain.autoApplyEdits = !brain.autoApplyEdits;
                  setState(() {});
                },
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'SAVE',
                icon: Icons.save_outlined,
                accentColor: hud.accentSuccessGreen,
                onTap: () => brain.saveActiveTabContent(_editorController.text),
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'UNDO',
                icon: Icons.undo,
                onTap: brain.undoLastEditOnActiveTab,
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'CODE-OSS',
                icon: Icons.open_in_new,
                onTap: () => brain.openActiveFileInRealVsCode(line: 1),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: brain.closeVsCodeWindow,
                child: Icon(Icons.close, size: 17, color: hud.accentErrorRed),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. MULTI-TAB STRIP
          if (brain.openTabs.isNotEmpty)
            SizedBox(
              height: 28,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: brain.openTabs.length,
                itemBuilder: (context, i) {
                  final t = brain.openTabs[i];
                  final isSel = i == brain.activeTabIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => brain.activeTabIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSel
                              ? hud.primaryPeriwinkle.withValues(alpha: 0.2)
                              : hud.bgInput,
                          border: Border.all(
                            color:
                                isSel ? hud.primaryPeriwinkle : hud.borderLine,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${t.fileName} [${t.gitStatusBadge}]',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight:
                                    isSel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => brain.closeEditorTab(i),
                              child: const Icon(Icons.close, size: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),

          // 3. PENDING DIFF HUNK ACCEPT / REJECT VIEW
          if (brain.pendingDiffHunks.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hud.bgInput,
                border: Border.all(color: hud.accentWarningAmber),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PENDING AI DIFF HUNK // ${brain.pendingDiffHunks.first.description.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: hud.accentWarningAmber,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...brain.pendingDiffHunks.first.proposedLines.take(4).map(
                        (l) => Text(
                          '+ $l',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: hud.accentSuccessGreen,
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      HudActionButton(
                        label: 'ACCEPT HUNK (WRITE TO DISK)',
                        accentColor: hud.accentSuccessGreen,
                        isPrimaryAccent: true,
                        onTap: () =>
                            brain.acceptDiffHunk(brain.pendingDiffHunks.first),
                      ),
                      const SizedBox(width: 8),
                      HudActionButton(
                        label: 'REJECT HUNK',
                        accentColor: hud.accentErrorRed,
                        onTap: () =>
                            brain.rejectDiffHunk(brain.pendingDiffHunks.first),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 4. EDITABLE SYNTAX-HIGHLIGHTED CODE BUFFER
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hud.bgInput,
                border: Border.all(color: hud.borderLine),
              ),
              child: TextField(
                controller: _editorController,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.45,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Lightweight syntax highlighting controller for Dart/Markdown/JSON
class SyntaxHighlightingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final lines = text.split('\n');
    final List<InlineSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      Color lineColor = hud.textPrimary;
      if (line.trim().startsWith('//') || line.trim().startsWith('#')) {
        lineColor = hud.textMuted;
      } else if (line.contains('class ') ||
          line.contains('void ') ||
          line.contains('Future<') ||
          line.contains('import ')) {
        lineColor = hud.primaryPeriwinkle;
      } else if (line.contains('return ') || line.contains('final ')) {
        lineColor = hud.accentSuccessGreen;
      }
      spans.add(
        TextSpan(
          text: i < lines.length - 1 ? '$line\n' : line,
          style: style?.copyWith(color: lineColor),
        ),
      );
    }
    return TextSpan(style: style, children: spans);
  }
}