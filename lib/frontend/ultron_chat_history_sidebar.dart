import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../backend/memory_learning_usage_service.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_hud_theme.dart';

//**************
// Kompaktna lebdeča značka in razširljiv predal za zgodovino klepetov *
// V zaprtem stanju zavzame le 186x42 px (usklajeno s PC Datoteke), *
// ob prehodu z miško ali pripenjanju pa gladko odpre seznam sej *
//**************
class UltronChatHistorySidebar extends StatefulWidget {
  final UltronBrainRouter brain;
  final ValueChanged<String>? onToast;
  final double maxExpandedHeight;

  const UltronChatHistorySidebar({
    super.key,
    required this.brain,
    this.onToast,
    this.maxExpandedHeight = 430,
  });

  @override
  State<UltronChatHistorySidebar> createState() =>
      _UltronChatHistorySidebarState();
}

class _UltronChatHistorySidebarState extends State<UltronChatHistorySidebar> {
  bool _isExpanded = false;
  bool _isPinned = false;
  // 0 = Vsi klepeti, 1 = Ta projekt (oz. Splošni, če ni aktivnega projekta)
  int _tabIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDateLabel(DateTime dt) {
    final now = DateTime.now();
    final sameDay =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Danes $hh:$mm';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m. $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final bool open = _isExpanded || _isPinned;
    final double expandedH = math.max(240.0, widget.maxExpandedHeight);

    return ListenableBuilder(
      listenable: Listenable.merge([widget.brain, widget.brain.memoryService]),
      builder: (context, _) {
        final mem = widget.brain.memoryService;
        final allChats = mem.savedChatArchives;
        final projectChats = widget.brain.hasActiveProject
            ? mem.chatsForProject(widget.brain.activeProjectPath)
            : mem.chatsForProject('');

        List<SavedChatArchive> displayChats =
            _tabIndex == 1 ? projectChats : allChats;

        if (_searchQuery.trim().isNotEmpty) {
          final q = _searchQuery.trim().toLowerCase();
          displayChats = displayChats
              .where((c) =>
                  c.title.toLowerCase().contains(q) ||
                  c.previewSnippet.toLowerCase().contains(q) ||
                  c.projectName.toLowerCase().contains(q))
              .toList();
        }

        return MouseRegion(
          onEnter: (_) => setState(() => _isExpanded = true),
          onExit: (_) {
            if (!_isPinned && _searchQuery.isEmpty) {
              setState(() => _isExpanded = false);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 230),
            curve: Curves.easeOutCubic,
            width: open ? 348 : 186,
            height: open ? expandedH : 42,
            decoration: BoxDecoration(
              color: hud.bgPanel.alphaPct(open ? 0.96 : 0.84),
              borderRadius: BorderRadius.circular(hud.cutRadius),
              border: Border.all(
                color: open
                    ? hud.primaryPeriwinkle.alphaPct(0.50)
                    : hud.borderLine.alphaPct(0.85),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.alphaPct(open ? 0.28 : 0.14),
                  blurRadius: open ? 24 : 10,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Kompaktna glava značke (vedno poravnana s PC Datoteke)
                SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          open
                              ? Icons.forum_outlined
                              : Icons.history_rounded,
                          size: 16,
                          color: hud.primaryPeriwinkle,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            open ? 'Zgodovina klepetov' : 'Zgodovina',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hud.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: hud.primaryPeriwinkle.alphaPct(0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${allChats.length}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: hud.primaryPeriwinkle,
                            ),
                          ),
                        ),
                        if (open) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Začni nov prazen klepet',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 25, minHeight: 25),
                            icon: Icon(
                              Icons.add_comment_outlined,
                              size: 14.5,
                              color: hud.accentSuccessGreen,
                            ),
                            onPressed: () {
                              widget.brain.startNewChatSession();
                              widget.onToast?.call('Začet nov klepet');
                            },
                          ),
                          IconButton(
                            tooltip:
                                _isPinned ? 'Odpni okno' : 'Pripni odprto okno',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 24, minHeight: 24),
                            icon: Icon(
                              _isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              size: 14,
                              color: _isPinned
                                  ? hud.primaryPeriwinkle
                                  : hud.textMuted,
                            ),
                            onPressed: () =>
                                setState(() => _isPinned = !_isPinned),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                if (open) ...[
                  Divider(height: 1, color: hud.borderLine.alphaPct(0.75)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildTabButton(
                                hud: hud,
                                label: 'Vsi klepeti (${allChats.length})',
                                isActive: _tabIndex == 0,
                                onTap: () => setState(() => _tabIndex = 0),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: _buildTabButton(
                                hud: hud,
                                label: widget.brain.hasActiveProject
                                    ? 'Ta projekt (${projectChats.length})'
                                    : 'Splošni (${projectChats.length})',
                                isActive: _tabIndex == 1,
                                onTap: () => setState(() => _tabIndex = 1),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 28,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: TextStyle(
                                fontSize: 11.5, color: hud.textPrimary),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.search_rounded,
                                  size: 14, color: hud.textMuted),
                              prefixIconConstraints: const BoxConstraints(
                                  minWidth: 28, maxHeight: 24),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? GestureDetector(
                                      onTap: () {
                                        _searchCtrl.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      child: Icon(Icons.close_rounded,
                                          size: 13, color: hud.textMuted),
                                    )
                                  : null,
                              hintText: 'Poišči pogovor ali projekt...',
                              hintStyle: TextStyle(
                                  fontSize: 11, color: hud.textMuted),
                              filled: true,
                              fillColor: hud.bgInput.alphaPct(0.60),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: hud.borderLine.alphaPct(0.65)),
                  Expanded(
                    child: displayChats.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _searchQuery.isNotEmpty
                                    ? 'Ni zadetkov za "$_searchQuery".'
                                    : 'Še ni shranjenih pogovorov v tem pogledu.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11.5, color: hud.textMuted),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 5),
                            itemCount: displayChats.length,
                            itemBuilder: (context, idx) {
                              final archive = displayChats[idx];
                              final projMeta = archive.hasProject
                                  ? mem.getProjectMeta(archive.projectPath)
                                  : null;

                              return _ChatArchiveTile(
                                archive: archive,
                                projectMeta: projMeta,
                                timeLabel: _formatDateLabel(archive.savedAt),
                                isActive: archive.sessionId ==
                                    widget.brain.currentChatSessionId,
                                hud: hud,
                                onLoad: () {
                                  widget.brain
                                      .loadSavedChatArchiveIntoView(archive);
                                  widget.onToast?.call(
                                      'Naložen klepet: ${archive.title}');
                                },
                                onRename: () => _showRenameDialog(archive),
                                onDelete: () {
                                  mem.deleteChatSession(archive.sessionId);
                                  if (archive.sessionId ==
                                      widget.brain.currentChatSessionId) {
                                    widget.brain.startNewChatSession();
                                  }
                                  widget.onToast?.call('Klepet izbrisan');
                                },
                                onPinToggle: () =>
                                    mem.togglePinChatSession(archive.sessionId),
                              );
                            },
                          ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabButton({
    required UltronHudTheme hud,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? hud.primaryPeriwinkle.alphaPct(0.20)
              : hud.bgInput.alphaPct(0.65),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isActive
                ? hud.primaryPeriwinkle.alphaPct(0.65)
                : hud.borderLine.alphaPct(0.70),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? hud.textPrimary : hud.textMuted,
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(SavedChatArchive archive) {
    final ctrl = TextEditingController(text: archive.title);
    showDialog(
      context: context,
      builder: (ctx) {
        final hud =
            Theme.of(ctx).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
        return AlertDialog(
          backgroundColor: hud.bgPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(hud.cutRadius),
            side: BorderSide(color: hud.borderLine),
          ),
          title: Text(
            'Preimenuj sejo klepeta',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: hud.textPrimary,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            onSubmitted: (_) {
              widget.brain.memoryService
                  .renameChatSession(archive.sessionId, ctrl.text);
              Navigator.pop(ctx);
            },
            style: TextStyle(fontSize: 12.5, color: hud.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: hud.bgInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hud.borderLine),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Prekliči', style: TextStyle(color: hud.textMuted)),
            ),
            TextButton(
              onPressed: () {
                widget.brain.memoryService
                    .renameChatSession(archive.sessionId, ctrl.text);
                Navigator.pop(ctx);
              },
              child: Text(
                'Shrani',
                style: TextStyle(
                  color: hud.primaryPeriwinkle,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatArchiveTile extends StatefulWidget {
  final SavedChatArchive archive;
  final UltronProjectMeta? projectMeta;
  final String timeLabel;
  final bool isActive;
  final UltronHudTheme hud;
  final VoidCallback onLoad;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onPinToggle;

  const _ChatArchiveTile({
    required this.archive,
    this.projectMeta,
    required this.timeLabel,
    required this.isActive,
    required this.hud,
    required this.onLoad,
    required this.onRename,
    required this.onDelete,
    required this.onPinToggle,
  });

  @override
  State<_ChatArchiveTile> createState() => _ChatArchiveTileState();
}

class _ChatArchiveTileState extends State<_ChatArchiveTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hud = widget.hud;
    final a = widget.archive;
    final meta = widget.projectMeta;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onLoad,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? hud.primaryPeriwinkle.alphaPct(0.16)
                : (_hovered
                    ? hud.bgInput.alphaPct(0.75)
                    : hud.bgInput.alphaPct(0.32)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isActive
                  ? hud.primaryPeriwinkle.alphaPct(0.65)
                  : (_hovered
                      ? hud.primaryPeriwinkle.alphaPct(0.35)
                      : hud.borderLine.alphaPct(0.55)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    a.pinned
                        ? Icons.push_pin_rounded
                        : (widget.isActive
                            ? Icons.chat_bubble_rounded
                            : Icons.chat_bubble_outline_rounded),
                    size: 13.5,
                    color: (a.pinned || widget.isActive)
                        ? hud.primaryPeriwinkle
                        : hud.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.8,
                        fontWeight: widget.isActive
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: hud.textPrimary,
                      ),
                    ),
                  ),
                  if (_hovered) ...[
                    _miniIconBtn(
                      icon: a.pinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      color:
                          a.pinned ? hud.primaryPeriwinkle : hud.textMuted,
                      onTap: widget.onPinToggle,
                    ),
                    _miniIconBtn(
                      icon: Icons.edit_outlined,
                      color: hud.textMuted,
                      onTap: widget.onRename,
                    ),
                    _miniIconBtn(
                      icon: Icons.delete_outline_rounded,
                      color: hud.accentErrorRed,
                      onTap: widget.onDelete,
                    ),
                  ] else
                    Text(
                      widget.timeLabel,
                      style: TextStyle(fontSize: 9.8, color: hud.textMuted),
                    ),
                ],
              ),
              if (a.previewSnippet.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  a.previewSnippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.6,
                    color: hud.textMuted.alphaPct(0.88),
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Wrap(
                spacing: 5,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: a.hasProject
                          ? hud.secondaryVioletBloom.alphaPct(0.18)
                          : hud.bgDeep.alphaPct(0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      a.hasProject
                          ? 'Projekt: ${a.projectName}'
                          : 'Splošni klepet',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: a.hasProject
                            ? hud.primaryPeriwinkle
                            : hud.textMuted,
                      ),
                    ),
                  ),
                  if (meta != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: (meta.isCompleted
                                ? hud.accentSuccessGreen
                                : hud.accentWarningAmber)
                            .alphaPct(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        meta.hasDeadline
                            ? '${meta.statusLabel} ·${meta.deadlineSummaryLabel}'
                            : meta.statusLabel,
                        style: TextStyle(
                          fontSize: 9.2,
                          fontWeight: FontWeight.w600,
                          color: meta.isCompleted
                              ? hud.accentSuccessGreen
                              : hud.accentWarningAmber,
                        ),
                      ),
                    ),
                  Text(
                    '${a.messageCount} spor.',
                    style: TextStyle(fontSize: 9.5, color: hud.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniIconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Icon(icon, size: 13.5, color: color),
      ),
    );
  }
}