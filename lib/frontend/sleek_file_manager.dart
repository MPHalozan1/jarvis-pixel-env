import 'dart:io';
import 'package:flutter/material.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**************
// Minimalističen razširljiv File Manager za brskanje po celotnem računalniku *
// Zazna vse diske (C:\, D:\ itd.), hitre mape, omogoča iskanje, pripenjanje v klepet *
// ter neposredno sprožanje učenja (Learn) nad poljubno mapo *
//**************
class FuturisticHoverFileStack extends StatefulWidget {
  final UltronBrainRouter brain;
  final bool isDarkMode;
  final ValueChanged<String>? onStatusToast;

  const FuturisticHoverFileStack({
    super.key,
    required this.brain,
    required this.isDarkMode,
    this.onStatusToast,
  });

  @override
  State<FuturisticHoverFileStack> createState() =>
      _FuturisticHoverFileStackState();
}

class _FuturisticHoverFileStackState extends State<FuturisticHoverFileStack> {
  bool _isExpanded = false;
  bool _isPinned = false;
  bool _showHidden = false;
  bool _editingPath = false;

  String _searchQuery = '';
  List<FileSystemEntity> _entries = [];
  String? _accessError;

  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _filterCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pathCtrl.text = widget.brain.currentBrowserDirectory;
    _loadDirectory(widget.brain.currentBrowserDirectory);
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  void _loadDirectory(String path) {
    final targetDir = Directory(path);
    if (!targetDir.existsSync()) {
      setState(() {
        _accessError = 'Mapa ne obstaja: $path';
      });
      return;
    }

    try {
      final rawList = targetDir.listSync(followLinks: false);
      rawList.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return _entityName(a.path)
            .toLowerCase()
            .compareTo(_entityName(b.path).toLowerCase());
      });

      widget.brain.setCurrentBrowserDirectory(targetDir.path);
      _pathCtrl.text = targetDir.path;

      if (mounted) {
        setState(() {
          _entries = rawList;
          _accessError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _entries = [];
          _accessError = 'Dostop zavrnjen za to sistemsko mapo.';
        });
      }
    }
  }

  void _navigateUp() {
    final current = Directory(widget.brain.currentBrowserDirectory);
    final parent = current.parent;
    if (parent.path != current.path) {
      _loadDirectory(parent.path);
    }
  }

  Map<String, String> _quickFolders() {
    final map = <String, String>{};
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (home.isNotEmpty && Directory(home).existsSync()) {
      map['Domov'] = home;
      final desktop = '$home${Platform.pathSeparator}Desktop';
      final docs = '$home${Platform.pathSeparator}Documents';
      final downloads = '$home${Platform.pathSeparator}Downloads';
      if (Directory(desktop).existsSync()) map['Namizje'] = desktop;
      if (Directory(docs).existsSync()) map['Dokumenti'] = docs;
      if (Directory(downloads).existsSync()) map['Prenosi'] = downloads;
    }
    map['Projekt'] = Directory.current.path;
    return map;
  }

  String _entityName(String fullPath) {
    final cleaned =
        fullPath.endsWith(Platform.pathSeparator) && fullPath.length > 3
            ? fullPath.substring(0, fullPath.length - 1)
            : fullPath;
    final idx = cleaned.lastIndexOf(Platform.pathSeparator);
    return idx == -1 ? cleaned : cleaned.substring(idx + 1);
  }

  IconData _iconForFile(String name, bool isDir) {
    if (isDir) return Icons.folder_outlined;
    final lower = name.toLowerCase();
    if (lower.endsWith('.docx') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.odt') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.md')) {
      return Icons.description_outlined;
    }
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return Icons.archive_outlined;
    }
    if (lower.endsWith('.dart') ||
        lower.endsWith('.cs') ||
        lower.endsWith('.py') ||
        lower.endsWith('.cpp') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.go') ||
        lower.endsWith('.sql') ||
        lower.endsWith('.json') ||
        lower.endsWith('.yaml')) {
      return Icons.code;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final bool open = _isExpanded || _isPinned;

    final filtered = _entries.where((e) {
      final name = _entityName(e.path);
      if (!_showHidden && name.startsWith('.')) return false;
      if (_searchQuery.isNotEmpty &&
          !name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _isExpanded = true),
      onExit: (_) {
        if (!_isPinned && !_editingPath) {
          setState(() => _isExpanded = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: open ? 325 : 178,
        height: open ? 510 : 42,
        decoration: BoxDecoration(
          color: hud.bgPanel.alphaPct(open ? 0.94 : 0.80),
          borderRadius: BorderRadius.circular(hud.cutRadius),
          border: Border.all(
            color: open
                ? hud.primaryPeriwinkle.alphaPct(0.45)
                : hud.borderLine.alphaPct(0.85),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.alphaPct(open ? 0.28 : 0.12),
              blurRadius: open ? 24 : 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Zgornja glava brskalnika
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.folder_open : Icons.folder_outlined,
                    size: 16,
                    color: hud.primaryPeriwinkle,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      open
                          ? _entityName(widget.brain.currentBrowserDirectory)
                          : 'PC Datoteke',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hud.textPrimary,
                      ),
                    ),
                  ),
                  if (open) ...[
                    IconButton(
                      tooltip: 'Nauči se iz trenutne mape (Learn)',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: Icon(
                        Icons.psychology_alt,
                        size: 15,
                        color: hud.accentSuccessGreen,
                      ),
                      onPressed: () async {
                        widget.onStatusToast
                            ?.call('Učim se iz izbrane mape...');
                        final count = await widget.brain.triggerLearnPass(
                          customFolder: widget.brain.currentBrowserDirectory,
                        );
                        widget.onStatusToast?.call(
                          count > 0
                              ? 'Learn zaključen: +$count novih pravil'
                              : 'Learn posodobljen za to mapo',
                        );
                      },
                    ),
                    IconButton(
                      tooltip: _showHidden
                          ? 'Skrij skrite datoteke'
                          : 'Prikaži skrite datoteke',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: Icon(
                        _showHidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 14,
                        color: hud.textMuted,
                      ),
                      onPressed: () =>
                          setState(() => _showHidden = !_showHidden),
                    ),
                    IconButton(
                      tooltip: _isPinned ? 'Odpni okno' : 'Pripni odprto okno',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: Icon(
                        _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 14,
                        color:
                            _isPinned ? hud.primaryPeriwinkle : hud.textMuted,
                      ),
                      onPressed: () => setState(() => _isPinned = !_isPinned),
                    ),
                  ],
                ],
              ),
            ),

            if (open) ...[
              Divider(height: 1, color: hud.borderLine.alphaPct(0.75)),

              // Vrstica z vsemi diski (C:\, D:\ ...) in hitrimi mapami
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    for (final drive in widget.brain.availableSystemRoots)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: _QuickDriveChip(
                          label: drive,
                          icon: Icons.storage_rounded,
                          isSelected: widget.brain.currentBrowserDirectory
                              .toUpperCase()
                              .startsWith(drive.toUpperCase()),
                          onTap: () => _loadDirectory(drive),
                        ),
                      ),
                    for (final entry in _quickFolders().entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: _QuickDriveChip(
                          label: entry.key,
                          isSelected: widget.brain.currentBrowserDirectory ==
                              entry.value,
                          onTap: () => _loadDirectory(entry.value),
                        ),
                      ),
                  ],
                ),
              ),

              // Vrstica za pot in skok nivo višje
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Mapa višje',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(
                        Icons.arrow_upward_rounded,
                        size: 15,
                        color: hud.textPrimary,
                      ),
                      onPressed: _navigateUp,
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 28,
                        child: TextField(
                          controller: _pathCtrl,
                          onTap: () => _editingPath = true,
                          onSubmitted: (val) {
                            _editingPath = false;
                            _loadDirectory(val.trim());
                          },
                          style: TextStyle(
                            fontSize: 11,
                            color: hud.textPrimary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            filled: true,
                            fillColor: hud.bgInput.alphaPct(0.8),
                            hintText: 'Vpiši pot (npr. D:\\)...',
                            hintStyle: TextStyle(
                                fontSize: 11, color: hud.textMuted),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(5),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Osveži mapo',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(
                        Icons.refresh_rounded,
                        size: 15,
                        color: hud.textMuted,
                      ),
                      onPressed: () {
                        widget.brain.refreshSystemRoots();
                        _loadDirectory(widget.brain.currentBrowserDirectory);
                      },
                    ),
                  ],
                ),
              ),

              // Iskalni filter v trenutni mapi
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _filterCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(fontSize: 11.5, color: hud.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 14, color: hud.textMuted),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 28, maxHeight: 24),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _filterCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: Icon(Icons.close_rounded,
                                  size: 13, color: hud.textMuted),
                            )
                          : null,
                      hintText: 'Filtriraj v tej mapi...',
                      hintStyle:
                          TextStyle(fontSize: 11, color: hud.textMuted),
                      filled: true,
                      fillColor: hud.bgInput.alphaPct(0.55),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),

              Divider(height: 1, color: hud.borderLine.alphaPct(0.65)),

              // Seznam map in datotek
              Expanded(
                child: _accessError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _accessError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: hud.accentErrorRed),
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Mapa je prazna',
                              style: TextStyle(
                                  fontSize: 12, color: hud.textMuted),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            itemCount: filtered.length,
                            itemBuilder: (context, idx) {
                              final entity = filtered[idx];
                              final isDir = entity is Directory;
                              final name = _entityName(entity.path);

                              return _FileEntryTile(
                                name: name,
                                icon: _iconForFile(name, isDir),
                                isDirectory: isDir,
                                onPrimaryTap: () {
                                  if (isDir) {
                                    _filterCtrl.clear();
                                    _searchQuery = '';
                                    _loadDirectory(entity.path);
                                  } else {
                                    widget.brain
                                        .openFileInEditorTab(entity.path);
                                  }
                                },
                                onAttachTap: isDir
                                    ? null
                                    : () async {
                                        final ok = await widget.brain
                                            .attachFileFromPath(entity.path);
                                        if (ok) {
                                          widget.onStatusToast?.call(
                                              'Pripeta datoteka: $name');
                                        }
                                      },
                              );
                            },
                          ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickDriveChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickDriveChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? hud.primaryPeriwinkle.alphaPct(0.20)
              : hud.bgInput.alphaPct(0.65),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected
                ? hud.primaryPeriwinkle.alphaPct(0.65)
                : hud.borderLine.alphaPct(0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: hud.primaryPeriwinkle),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? hud.textPrimary : hud.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileEntryTile extends StatefulWidget {
  final String name;
  final IconData icon;
  final bool isDirectory;
  final VoidCallback onPrimaryTap;
  final VoidCallback? onAttachTap;

  const _FileEntryTile({
    required this.name,
    required this.icon,
    required this.isDirectory,
    required this.onPrimaryTap,
    this.onAttachTap,
  });

  @override
  State<_FileEntryTile> createState() => _FileEntryTileState();
}

class _FileEntryTileState extends State<_FileEntryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPrimaryTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          padding: EdgeInsets.only(
            left: _hovered ? 11 : 8,
            right: 6,
            top: 5,
            bottom: 5,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? hud.primaryPeriwinkle.alphaPct(0.11)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 15,
                color: widget.isDirectory
                    ? hud.primaryPeriwinkle
                    : hud.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.8,
                    color: _hovered
                        ? hud.textPrimary
                        : hud.textPrimary.alphaPct(0.88),
                    fontWeight: widget.isDirectory
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (!widget.isDirectory &&
                  _hovered &&
                  widget.onAttachTap != null)
                Tooltip(
                  message: 'Pripni datoteko v klepet',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: widget.onAttachTap,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.attach_file,
                        size: 14,
                        color: hud.primaryPeriwinkle,
                      ),
                    ),
                  ),
                ),
              if (widget.isDirectory && _hovered)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: hud.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}