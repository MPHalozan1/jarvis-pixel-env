import 'dart:io';
import 'package:flutter/material.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**********************************************************************
// PHASE 2 // SHARP HUD HOVER-STACK FILE MANAGER                       *
// - Square chamfered Home icon at top-left                            *
// - Hover fans out the folder stack; double-click pins on top         *
//**********************************************************************

class FuturisticHoverFileStack extends StatefulWidget {
  final UltronBrainRouter brain;
  final bool isDarkMode;

  const FuturisticHoverFileStack({
    super.key,
    required this.brain,
    required this.isDarkMode,
  });

  @override
  State<FuturisticHoverFileStack> createState() =>
      _FuturisticHoverFileStackState();
}

class _FuturisticHoverFileStackState extends State<FuturisticHoverFileStack> {
  bool _isHovered = false;
  String? _hoveredPreviewFolderPath;
  int _activeVaultMode = 0; // 0 = Stack, 1 = Learned Notes, 2 = GitHub
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
    final brain = widget.brain;
    final hasPinned =
        brain.pinnedFolderPath != null || brain.pinnedFilePath != null;
    final expanded = _isHovered || hasPinned;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) {
        setState(() {
          _isHovered = false;
          _hoveredPreviewFolderPath = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: expanded
            ? (_hoveredPreviewFolderPath != null ? 520 : 305)
            : 46,
        constraints: BoxConstraints(maxHeight: expanded ? 500 : 46),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSharpHomeHeader(hud, brain, hasPinned, expanded),
            if (expanded) ...[
              const SizedBox(height: 6),
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildStackBody(hud, brain, hasPinned),
                    ),
                    if (_hoveredPreviewFolderPath != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 5,
                        child: _buildSubFolderPreview(
                          hud,
                          brain,
                          _hoveredPreviewFolderPath!,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSharpHomeHeader(
    UltronHudTheme hud,
    UltronBrainRouter brain,
    bool hasPinned,
    bool expanded,
  ) {
    final pinnedPath = brain.pinnedFilePath ?? brain.pinnedFolderPath;
    final pinnedName = pinnedPath != null
        ? pinnedPath.split(Platform.pathSeparator).last.toUpperCase()
        : 'HOME';

    return Container(
      height: 44,
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
      decoration: ShapeDecoration(
        color: hud.bgPanel,
        shape: hud.chamferShape(
          borderColor:
              hasPinned ? hud.accentErrorRed : hud.primaryPeriwinkle,
          width: 1.2,
        ),
      ),
      child: expanded
          ? Row(
              children: [
                Icon(
                  hasPinned ? Icons.folder_special_sharp : Icons.home_sharp,
                  size: 18,
                  color: hasPinned ? hud.accentErrorRed : hud.primaryPeriwinkle,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasPinned ? 'PINNED // $pinnedName' : 'HOME // WORKSPACE STACK',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: hud.textPrimary,
                    ),
                  ),
                ),
                if (hasPinned)
                  InkWell(
                    onTap: () {
                      _searchCtrl.clear();
                      brain.resetStackToHome();
                    },
                    child: Icon(
                      Icons.close,
                      size: 15,
                      color: hud.primaryPeriwinkle,
                    ),
                  ),
              ],
            )
          : Center(
              child: Icon(
                Icons.home_sharp,
                size: 19,
                color: hud.primaryPeriwinkle,
              ),
            ),
    );
  }

  Widget _buildStackBody(
    UltronHudTheme hud,
    UltronBrainRouter brain,
    bool hasPinned,
  ) {
    return HudBracketPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _tabChip(hud, 0, 'FILES'),
              const SizedBox(width: 4),
              _tabChip(hud, 1, 'LEARNED'),
              const SizedBox(width: 4),
              _tabChip(hud, 2, 'GITHUB'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            child: TextField(
              controller: _searchCtrl,
              onChanged: brain.updateSearchInPinnedFolder,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'SEARCH STACK...',
                prefixIcon: Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: hud.primaryPeriwinkle,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                filled: true,
                fillColor: hud.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: hud.borderLine),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: _activeVaultMode == 0
                ? ListView.builder(
                    shrinkWrap: true,
                    itemCount: brain.currentFolderEntities.length,
                    itemBuilder: (context, i) {
                      final entity = brain.currentFolderEntities[i];
                      final isDir = entity is Directory;
                      final name =
                          entity.path.split(Platform.pathSeparator).last;
                      return MouseRegion(
                        onEnter: (_) {
                          if (isDir) {
                            setState(
                              () => _hoveredPreviewFolderPath = entity.path,
                            );
                          }
                        },
                        child: GestureDetector(
                          onTap: () {
                            if (isDir) {
                              setState(
                                () => _hoveredPreviewFolderPath = entity.path,
                              );
                            } else {
                              brain.openFileInEditorTab(entity.path);
                            }
                          },
                          onDoubleTap: () {
                            if (isDir) {
                              setState(() => _hoveredPreviewFolderPath = null);
                              brain.pinFolderOnTop(entity.path);
                            } else {
                              brain.pinFileAndOpenVsCodeWindow(entity.path);
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: hud.bgInput,
                              border: Border.all(color: hud.borderLine),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isDir ? Icons.folder_sharp : Icons.code_sharp,
                                  size: 14,
                                  color: isDir
                                      ? hud.accentWarningAmber
                                      : hud.primaryPeriwinkle,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10.5),
                                  ),
                                ),
                                Text(
                                  isDir ? '[2x PIN]' : '[2x EDIT]',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    color: hud.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : _activeVaultMode == 1
                    ? ListView(
                        shrinkWrap: true,
                        children: brain.memoryService.learnedDir
                            .listSync()
                            .whereType<File>()
                            .map((f) {
                          final name =
                              f.path.split(Platform.pathSeparator).last;
                          return ListTile(
                            dense: true,
                            title: Text(
                              name,
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () => brain.openFileInEditorTab(f.path),
                          );
                        }).toList(),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: brain.githubRepos.length,
                        itemBuilder: (context, i) {
                          final r = brain.githubRepos[i];
                          return ListTile(
                            dense: true,
                            title: Text(
                              r.name,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: HudActionButton(
                              label: r.isCloned ? 'OPEN' : 'CLONE',
                              onTap: () => brain.cloneRepoToDesktop(r),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(UltronHudTheme hud, int idx, String label) {
    final isSel = _activeVaultMode == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeVaultMode = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSel
                ? hud.primaryPeriwinkle.withValues(alpha: 0.2)
                : hud.bgInput,
            border: Border.all(
              color: isSel ? hud.primaryPeriwinkle : hud.borderLine,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: isSel ? hud.primaryPeriwinkle : hud.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubFolderPreview(
    UltronHudTheme hud,
    UltronBrainRouter brain,
    String folderPath,
  ) {
    final items = brain.listEntitiesForDirectory(folderPath);
    return HudBracketPanel(
      padding: const EdgeInsets.all(8),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final sub = items[i];
          final isDir = sub is Directory;
          final name = sub.path.split(Platform.pathSeparator).last;
          return GestureDetector(
            onDoubleTap: () {
              if (isDir) {
                setState(() => _hoveredPreviewFolderPath = null);
                brain.pinFolderOnTop(sub.path);
              } else {
                brain.pinFileAndOpenVsCodeWindow(sub.path);
              }
            },
            onTap: () {
              if (!isDir) brain.openFileInEditorTab(sub.path);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${isDir ? "[DIR]" : "FILE"} $name',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ),
          );
        },
      ),
    );
  }
}