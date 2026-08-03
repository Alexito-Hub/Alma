import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/neo.dart';
import '../../../data/device/media_tools.dart';
import '../../../data/local/isar/date_idea_local.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/date_idea_repository.dart';
import '../../../data/sync/sync_worker.dart';
import '../../widgets/neo_confirm_dialog.dart';
import '../../widgets/post_media.dart';

/// "Citas" — the couple's shared plans. Pending ideas at the top ("¿a dónde
/// deberíamos ir?"), the ones already lived below, with the photos and the
/// note written when marking them done.
class CitasScreen extends ConsumerStatefulWidget {
  const CitasScreen({super.key});

  @override
  ConsumerState<CitasScreen> createState() => _CitasScreenState();
}

class _CitasScreenState extends ConsumerState<CitasScreen> {
  Future<void> _create() async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final result = await showDialog<_IdeaInput>(
      context: context,
      builder: (_) => const _IdeaDialog(),
    );
    if (result == null) return;

    await ref
        .read(dateIdeaRepositoryProvider)
        .create(
          title: result.title,
          description: result.description,
          proposedBy: me.id,
          plannedAt: result.plannedAt,
          latitude: result.geo?.latitude,
          longitude: result.geo?.longitude,
          placeLabel: result.place,
        );
    unawaited(runForegroundSync());
  }

  Future<void> _edit(DateIdeaLocal d) async {
    final result = await showDialog<_IdeaInput>(
      context: context,
      builder: (_) => _IdeaDialog(existing: d),
    );
    if (result == null) return;

    await ref
        .read(dateIdeaRepositoryProvider)
        .update(
          isarId: d.isarId,
          title: result.title,
          description: result.description,
          plannedAt: result.plannedAt,
          placeLabel: result.place,
        );
    unawaited(runForegroundSync());
  }

  Future<void> _markDone(DateIdeaLocal d) async {
    final result = await showDialog<_DoneInput>(
      context: context,
      builder: (_) => _DoneDialog(title: d.title),
    );
    if (result == null) return;

    await ref
        .read(dateIdeaRepositoryProvider)
        .markDone(isarId: d.isarId, note: result.note, photos: result.photos);
    unawaited(runForegroundSync());
  }

  Future<void> _remove(DateIdeaLocal d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => NeoConfirmDialog(
        title: 'Eliminar cita',
        message:
            '¿Quieres eliminar "${d.title}"? También desaparecerá para tu '
            'pareja y no se puede deshacer.',
        confirmLabel: 'Eliminar',
      ),
    );
    if (ok != true) return;
    await ref.read(dateIdeaRepositoryProvider).delete(d.isarId);
    unawaited(runForegroundSync());
  }

  @override
  Widget build(BuildContext context) {
    final ideas =
        ref.watch(dateIdeasProvider).valueOrNull ?? const <DateIdeaLocal>[];
    final me = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final pending = ideas.where((d) => !d.done).toList();
    final done = ideas.where((d) => d.done).toList()
      ..sort(
        (a, b) => (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt),
      );

    String who(DateIdeaLocal d) => d.proposedBy == me?.id
        ? (me?.prettyName ?? 'tú')
        : (partner?.prettyName ?? 'tu pareja');

    return Scaffold(
      backgroundColor: Neo.paper,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 4),
        child: NeoButton(
          label: 'Proponer',
          icon: Icons.add_rounded,
          onPressed: _create,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              child: Row(
                children: [
                  const NeoIconBadge(
                    icon: Icons.favorite_border_rounded,
                    color: Neo.coral,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Citas', style: txt.titleLarge),
                        Text(
                          '¿A dónde deberíamos ir?',
                          style: txt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ideas.isEmpty
                  ? const _EmptyCitas()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(22, 6, 22, 90),
                      children: [
                        _SectionHeader(
                          icon: Icons.schedule_rounded,
                          color: Neo.yellow,
                          label: 'Pendientes',
                          count: pending.length,
                        ),
                        const SizedBox(height: 10),
                        if (pending.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Text(
                              'Nada pendiente. Propón algo.',
                              style: txt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          for (final d in pending)
                            Padding(
                              key: ValueKey('cita-${d.isarId}'),
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _IdeaCard(
                                idea: d,
                                proposedBy: who(d),
                                onDone: () => _markDone(d),
                                onEdit: () => _edit(d),
                                onDelete: () => _remove(d),
                              ),
                            ),
                        const SizedBox(height: 12),
                        _SectionHeader(
                          icon: Icons.check_circle_rounded,
                          color: Neo.mint,
                          label: 'Hechas',
                          count: done.length,
                        ),
                        const SizedBox(height: 10),
                        for (final d in done)
                          Padding(
                            key: ValueKey('cita-done-${d.isarId}'),
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _IdeaCard(
                              idea: d,
                              proposedBy: who(d),
                              onUndo: () async {
                                await ref
                                    .read(dateIdeaRepositoryProvider)
                                    .markPending(d.isarId);
                                unawaited(runForegroundSync());
                              },
                              onDelete: () => _remove(d),
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NeoIconBadge(icon: icon, color: color, size: 30, iconSize: 16),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Neo.white,
            border: Neo.borderThin,
            borderRadius: Neo.cornerSm,
          ),
          child: Text('$count', style: Theme.of(context).textTheme.labelSmall),
        ),
      ],
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.proposedBy,
    this.onDone,
    this.onUndo,
    this.onEdit,
    this.onDelete,
  });

  final DateIdeaLocal idea;
  final String proposedBy;
  final VoidCallback? onDone;
  final VoidCallback? onUndo;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final photos = idea.imagePaths.isNotEmpty
        ? idea.imagePaths
        : idea.remoteImageUrls.map(absoluteMediaUrl).toList();

    return NeoBox(
      width: double.infinity,
      padding: EdgeInsets.zero,
      shadowOffset: Neo.shadowBtn,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: idea.done ? Neo.mint : Neo.yellow,
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    idea.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: txt.titleSmall,
                  ),
                ),
                if (onEdit != null)
                  _Action(icon: Icons.edit_outlined, onTap: onEdit!),
                if (onDelete != null)
                  _Action(icon: Icons.delete_outline_rounded, onTap: onDelete!),
              ],
            ),
          ),
          if (photos.isNotEmpty) PostMediaCarousel(sources: photos),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (idea.description.isNotEmpty) ...[
                  Text(idea.description, style: txt.bodyMedium),
                  const SizedBox(height: 10),
                ],
                if ((idea.doneNote ?? '').isNotEmpty) ...[
                  Text(
                    idea.doneNote!,
                    style: txt.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(
                      icon: Icons.person_rounded,
                      color: Neo.white,
                      label: 'Propuesta por $proposedBy',
                    ),
                    if ((idea.placeLabel ?? '').isNotEmpty)
                      _Tag(
                        icon: Icons.place_rounded,
                        color: Neo.sky,
                        label: idea.placeLabel!,
                      ),
                    if (idea.plannedAt != null && !idea.done)
                      _Tag(
                        icon: Icons.event_rounded,
                        color: Neo.lilac,
                        label: DateFormat(
                          "d 'de' MMMM",
                          'es',
                        ).format(idea.plannedAt!),
                      ),
                    if (idea.done && idea.doneAt != null)
                      _Tag(
                        icon: Icons.check_rounded,
                        color: Neo.mint,
                        label: DateFormat(
                          "d 'de' MMMM, y",
                          'es',
                        ).format(idea.doneAt!),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (onDone != null)
                  NeoButton(
                    label: 'Ya lo hicimos',
                    icon: Icons.check_rounded,
                    color: Neo.mint,
                    expand: true,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    onPressed: onDone,
                  ),
                if (onUndo != null)
                  NeoButton(
                    label: 'Volver a pendientes',
                    icon: Icons.undo_rounded,
                    color: Neo.white,
                    expand: true,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shadowOffset: Neo.shadowSm,
                    textStyle: txt.labelSmall,
                    onPressed: onUndo,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(left: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Neo.white,
          border: Neo.borderThin,
          borderRadius: Neo.cornerSm,
        ),
        child: Icon(icon, size: 15, color: Neo.ink),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        border: Neo.borderThin,
        borderRadius: Neo.cornerSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Neo.ink),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Neo.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCitas extends StatelessWidget {
  const _EmptyCitas();

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NeoAvatar(
              size: 88,
              color: Neo.coral,
              child: Icon(Icons.map_rounded, size: 42, color: Neo.ink),
            ),
            const SizedBox(height: 20),
            Text(
              'Sin citas todavía',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Apunta a dónde quieren ir. Cuando lo hagan, márquenlo como '
              'hecho y guarden las fotos aquí.',
              style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── dialogs ─────────────────────────────────────────────────────────────────

class _IdeaInput {
  const _IdeaInput({
    required this.title,
    required this.description,
    this.plannedAt,
    this.place,
    this.geo,
  });
  final String title;
  final String description;
  final DateTime? plannedAt;
  final String? place;
  final GeoTag? geo;
}

class _IdeaDialog extends StatefulWidget {
  const _IdeaDialog({this.existing});
  final DateIdeaLocal? existing;

  @override
  State<_IdeaDialog> createState() => _IdeaDialogState();
}

class _IdeaDialogState extends State<_IdeaDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _desc = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _place = TextEditingController(
    text: widget.existing?.placeLabel ?? '',
  );
  late DateTime? _plannedAt = widget.existing?.plannedAt;
  GeoTag? _geo;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _here() async {
    setState(() => _busy = true);
    final geo = await MediaTools.captureLocation();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (geo != null) {
        _geo = geo;
        if (geo.label != null) _place.text = geo.label!;
      }
    });
  }

  Future<void> _search() async {
    if (_place.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final found = await MediaTools.geocodePlace(_place.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (found != null) _geo = found;
    });
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('es'),
    );
    if (picked != null && mounted) setState(() => _plannedAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: NeoBox(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'Proponer una cita' : 'Editar cita',
                style: txt.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ir al mirador, cenar sushi…',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Detalles (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _place,
                decoration: const InputDecoration(
                  hintText: 'Lugar',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: NeoButton(
                      label: 'Aquí',
                      icon: Icons.my_location_rounded,
                      color: Neo.white,
                      expand: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shadowOffset: Neo.shadowSm,
                      textStyle: txt.labelSmall,
                      onPressed: _busy ? null : _here,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeoButton(
                      label: 'Buscar',
                      icon: Icons.travel_explore_rounded,
                      color: Neo.sky,
                      expand: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shadowOffset: Neo.shadowSm,
                      textStyle: txt.labelSmall,
                      onPressed: _busy ? null : _search,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              NeoButton(
                label: _plannedAt == null
                    ? 'Poner fecha (opcional)'
                    : DateFormat("d 'de' MMMM, y", 'es').format(_plannedAt!),
                icon: Icons.event_rounded,
                color: Neo.lilac,
                expand: true,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shadowOffset: Neo.shadowSm,
                textStyle: txt.labelSmall,
                onPressed: _pickDay,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: NeoButton(
                      label: 'Cancelar',
                      color: Neo.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeoButton(
                      label: 'Guardar',
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () {
                        final t = _title.text.trim();
                        if (t.isEmpty) return;
                        Navigator.pop(
                          context,
                          _IdeaInput(
                            title: t,
                            description: _desc.text.trim(),
                            plannedAt: _plannedAt,
                            place: _place.text.trim().isEmpty
                                ? null
                                : _place.text.trim(),
                            geo: _geo,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneInput {
  const _DoneInput({this.note, this.photos = const []});
  final String? note;
  final List<File> photos;
}

class _DoneDialog extends StatefulWidget {
  const _DoneDialog({required this.title});
  final String title;

  @override
  State<_DoneDialog> createState() => _DoneDialogState();
}

class _DoneDialogState extends State<_DoneDialog> {
  final _note = TextEditingController();
  final List<File> _photos = [];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final shots = await ImagePicker().pickMultiImage(imageQuality: 90);
    if (shots.isEmpty) return;
    setState(() => _photos.addAll(shots.map((x) => File(x.path))));
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: NeoBox(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¡Lo hicimos!',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: txt.bodySmall?.copyWith(
                color: Neo.ink.withValues(alpha: .6),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: '¿Cómo estuvo? (opcional)',
              ),
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      NeoFrame(
                        width: 68,
                        height: 68,
                        child: Image.file(_photos[i], fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Neo.ink,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 12,
                              color: Neo.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            NeoButton(
              label: 'Añadir fotos',
              icon: Icons.add_photo_alternate_outlined,
              color: Neo.white,
              expand: true,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shadowOffset: Neo.shadowSm,
              textStyle: txt.labelSmall,
              onPressed: _addPhotos,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: NeoButton(
                    label: 'Cancelar',
                    color: Neo.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeoButton(
                    label: 'Guardar',
                    color: Neo.mint,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () => Navigator.pop(
                      context,
                      _DoneInput(
                        note: _note.text,
                        photos: List<File>.from(_photos),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
