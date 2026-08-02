import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/neo.dart';
import '../../../data/device/media_tools.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/note_repository.dart';
import '../../../data/repositories/post_repository.dart';
import '../../../data/repositories/status_repository.dart';
import '../../../data/sync/media_compressor.dart';
import '../../../data/sync/sync_worker.dart';

/// "Crear" sheet opened from the bottom bar's central button. Three focused
/// capture actions: a status, a diary note, or a photo moment. Personalisation
/// (shared background, avatar) lives in Ajustes/Perfil, not here.
class QuickActionSheet extends ConsumerStatefulWidget {
  const QuickActionSheet({super.key});

  @override
  ConsumerState<QuickActionSheet> createState() => _QuickActionSheetState();
}

class _QuickActionSheetState extends ConsumerState<QuickActionSheet>
    with SingleTickerProviderStateMixin {
  final _noteCtrl = TextEditingController();
  final _statusCtrl = TextEditingController();
  final _postTitleCtrl = TextEditingController();
  final _postTagsCtrl = TextEditingController();

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  bool _working = false;
  bool _private = false;

  /// Draft for the feed post: media is collected first, then published, so a
  /// moment can carry several photos, a clip and a place.
  final List<File> _media = [];
  GeoTag? _geo;
  bool _locating = false;

  /// Optional snapshot attached to the next "siente".
  File? _statusPhoto;

  @override
  void dispose() {
    _intro.dispose();
    _noteCtrl.dispose();
    _statusCtrl.dispose();
    _postTitleCtrl.dispose();
    _postTagsCtrl.dispose();
    super.dispose();
  }

  /// A "siente" is a snapshot: a line of text, optionally with a photo taken
  /// right then. Either one alone is enough to post.
  Future<void> _saveStatus() async {
    final text = _statusCtrl.text.trim();
    final me = ref.read(currentUserProvider);
    if (me == null || (text.isEmpty && _statusPhoto == null)) return;
    await _run(() async {
      await ref
          .read(statusRepositoryProvider)
          .updateMine(
            authorId: me.id,
            text: text,
            imagePath: _statusPhoto?.path,
          );
      _statusCtrl.clear();
      _snack('Estado actualizado');
      if (mounted) setState(() => _statusPhoto = null);
    });
  }

  Future<void> _pickStatusPhoto({required ImageSource source}) async {
    final shot = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
    );
    if (shot == null) return;
    // Compress now: the status photo rides along on every sync.
    final compressed = await MediaCompressor.compressImage(File(shot.path));
    if (mounted) setState(() => _statusPhoto = compressed);
  }

  Future<void> _saveNote() async {
    final text = _noteCtrl.text.trim();
    final me = ref.read(currentUserProvider);
    if (me == null || text.isEmpty) return;
    await _run(() async {
      await ref
          .read(noteRepositoryProvider)
          .create(body: text, authorId: me.id);
      _noteCtrl.clear();
      _snack('Nota guardada');
    });
  }

  /// Add photos from the gallery. Multi-select: a moment is often several
  /// shots, and cropping every one would be tedious, so they go in as picked.
  Future<void> _addFromGallery() async {
    final shots = await ImagePicker().pickMultiImage(imageQuality: 92);
    if (shots.isEmpty) return;
    setState(() => _media.addAll(shots.map((x) => File(x.path))));
  }

  /// One shot from the camera, with the crop step (framing matters here).
  Future<void> _addFromCamera() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (shot == null) return;
    final cropped = await MediaTools.cropImage(shot.path);
    if (mounted) setState(() => _media.add(File(cropped)));
  }

  Future<void> _addVideo({required ImageSource source}) async {
    final clip = await ImagePicker().pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 5),
    );
    if (clip == null) return;
    if (mounted) setState(() => _media.add(File(clip.path)));
  }

  /// Where it happened. Reads the phone's position, then lets the user rename
  /// it — the venue ("Cine del centro") is what they'll want to read later.
  Future<void> _addLocation() async {
    setState(() => _locating = true);
    final geo = await MediaTools.captureLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (geo != null) _geo = geo;
    });
    if (geo == null) {
      _snack('No se pudo leer la ubicación. Puedes escribirla a mano.');
      await _editLocation();
    }
  }

  /// Name the place, or search a different one entirely ("marcar dónde fue").
  Future<void> _editLocation() async {
    final result = await showDialog<_PlaceInput>(
      context: context,
      builder: (_) => _PlaceDialog(initial: _geo?.label ?? ''),
    );
    if (result == null || !mounted) return;

    if (result.search) {
      setState(() => _locating = true);
      final found = await MediaTools.geocodePlace(result.name);
      if (!mounted) return;
      setState(() {
        _locating = false;
        if (found != null) _geo = found;
      });
      if (found == null) _snack('No encontré ese lugar. Guardé el nombre.');
      if (found != null) return;
    }
    // Keep the coordinates we already have (if any) and just rename them.
    setState(() {
      _geo = GeoTag(
        latitude: _geo?.latitude ?? 0,
        longitude: _geo?.longitude ?? 0,
        label: result.name.trim().isEmpty ? null : result.name.trim(),
      );
    });
  }

  Future<void> _publish() async {
    final me = ref.read(currentUserProvider);
    if (me == null || _media.isEmpty) return;

    await _run(() async {
      final tags = _postTagsCtrl.text
          .split(RegExp(r'[\s,]+'))
          .where((t) => t.isNotEmpty)
          .map((t) => t.replaceAll('#', '').toLowerCase())
          .toList();

      // A place typed without coordinates is still worth keeping as a label.
      final hasCoords =
          _geo != null && (_geo!.latitude != 0 || _geo!.longitude != 0);

      await ref
          .read(postRepositoryProvider)
          .create(
            title: _postTitleCtrl.text.trim().isEmpty
                ? 'Sin título'
                : _postTitleCtrl.text.trim(),
            description: '',
            authorId: me.id,
            tags: tags,
            media: List<File>.from(_media),
            private: _private,
            latitude: hasCoords ? _geo!.latitude : null,
            longitude: hasCoords ? _geo!.longitude : null,
            placeLabel: _geo?.label,
          );
      _postTitleCtrl.clear();
      _postTagsCtrl.clear();
      _snack(_private ? 'Guardado en el feed privado' : 'Momento publicado');
      if (mounted) {
        setState(() {
          _media.clear();
          _geo = null;
          _private = false;
        });
      }
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await body();
      // Push what we just created to the server right away instead of waiting
      // for the 15-minute background tick.
      unawaited(runForegroundSync());
    } catch (e) {
      _snack('Algo no funcionó: ${_short(e)}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  const NeoIconBadge(
                    icon: Icons.add_rounded,
                    color: Neo.pink,
                    size: 40,
                    iconSize: 26,
                  ),
                  const SizedBox(width: 10),
                  Text('Crear', style: txt.titleLarge),
                  const Spacer(),
                  NeoIconButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Container(height: Neo.strokeThin, color: Neo.ink),
            Expanded(
              child: AnimatedBuilder(
                animation: _intro,
                builder: (_, child) {
                  final t = Curves.easeOutCubic.transform(_intro.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 24),
                      child: child,
                    ),
                  );
                },
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Lo que captures aparece al instante. La sincronización al servidor pasa en segundo plano.',
                        style: txt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Status -----------------------------------------------------
                      _SectionCard(
                        icon: Icons.favorite_rounded,
                        color: Neo.mint,
                        label: 'Cómo te sientes ahora',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _statusCtrl,
                              decoration: InputDecoration(
                                hintText: 'Una palabra o frase corta',
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.send_rounded),
                                  onPressed: _working ? null : _saveStatus,
                                ),
                              ),
                              onSubmitted: (_) => _saveStatus(),
                            ),
                            const SizedBox(height: 10),
                            if (_statusPhoto != null)
                              Row(
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      border: Neo.borderThin,
                                      borderRadius: Neo.cornerSm,
                                    ),
                                    clipBehavior: Clip.antiAliasWithSaveLayer,
                                    child: Image.file(
                                      _statusPhoto!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Instantánea lista. Se enviará con tu siente.',
                                      style: txt.bodySmall,
                                    ),
                                  ),
                                  NeoIconButton(
                                    icon: Icons.close_rounded,
                                    size: 38,
                                    iconSize: 17,
                                    onPressed: () =>
                                        setState(() => _statusPhoto = null),
                                  ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: NeoButton(
                                      label: 'Instantánea',
                                      icon: Icons.photo_camera_outlined,
                                      color: Neo.white,
                                      expand: true,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 11,
                                      ),
                                      onPressed: _working
                                          ? null
                                          : () => _pickStatusPhoto(
                                              source: ImageSource.camera,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  NeoIconButton(
                                    icon: Icons.image_outlined,
                                    tooltip: 'Elegir de la galería',
                                    size: 42,
                                    iconSize: 18,
                                    onPressed: _working
                                        ? null
                                        : () => _pickStatusPhoto(
                                            source: ImageSource.gallery,
                                          ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Note -------------------------------------------------------
                      _SectionCard(
                        icon: Icons.menu_book_rounded,
                        color: Neo.lilac,
                        label: 'Un pensamiento para el Diario',
                        child: TextField(
                          controller: _noteCtrl,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Lo que quieras recordar más tarde…',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.bookmark_add_outlined),
                              onPressed: _working ? null : _saveNote,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Capture ----------------------------------------------------
                      _SectionCard(
                        icon: Icons.camera_alt_rounded,
                        color: Neo.sky,
                        label: 'Captura un momento',
                        child: Column(
                          children: [
                            TextField(
                              controller: _postTitleCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Título (opcional)',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _postTagsCtrl,
                              decoration: const InputDecoration(
                                hintText:
                                    'Tags separadas por espacio (#viaje #risa)',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                NeoChip(
                                  icon: _private
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                  label: _private ? 'Privado' : 'Normal',
                                  selected: _private,
                                  color: Neo.rose,
                                  onTap: () =>
                                      setState(() => _private = !_private),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: NeoButton(
                                    label: 'Fotos',
                                    icon: Icons.image_outlined,
                                    color: Neo.white,
                                    expand: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    onPressed: _working
                                        ? null
                                        : _addFromGallery,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: NeoButton(
                                    label: 'Cámara',
                                    icon: Icons.camera_alt_outlined,
                                    expand: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    onPressed: _working ? null : _addFromCamera,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: NeoButton(
                                    label: 'Video',
                                    icon: Icons.video_library_outlined,
                                    color: Neo.lilac,
                                    expand: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    onPressed: _working
                                        ? null
                                        : () => _addVideo(
                                            source: ImageSource.gallery,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: NeoButton(
                                    label: 'Grabar',
                                    icon: Icons.videocam_outlined,
                                    color: Neo.coral,
                                    expand: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    onPressed: _working
                                        ? null
                                        : () => _addVideo(
                                            source: ImageSource.camera,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            if (_media.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _DraftStrip(
                                media: _media,
                                onRemove: (f) => setState(() {
                                  _media.remove(f);
                                }),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Flexible(
                                  child: NeoChip(
                                    icon: Icons.place_rounded,
                                    label: _locating
                                        ? 'Ubicando…'
                                        : (_geo?.label ?? 'Añadir ubicación'),
                                    selected: _geo != null,
                                    color: Neo.mint,
                                    onTap: _locating ? null : _addLocation,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                NeoIconButton(
                                  icon: Icons.edit_outlined,
                                  tooltip: 'Escribir o buscar el lugar',
                                  size: 40,
                                  iconSize: 18,
                                  onPressed: _locating ? null : _editLocation,
                                ),
                                if (_geo != null) ...[
                                  const SizedBox(width: 6),
                                  NeoIconButton(
                                    icon: Icons.close_rounded,
                                    tooltip: 'Quitar ubicación',
                                    size: 40,
                                    iconSize: 18,
                                    onPressed: () =>
                                        setState(() => _geo = null),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 14),
                            NeoButton(
                              label: _media.isEmpty
                                  ? 'Agrega una foto o un video'
                                  : 'Publicar (${_media.length})',
                              icon: Icons.send_rounded,
                              expand: true,
                              busy: _working,
                              onPressed: (_media.isEmpty || _working)
                                  ? null
                                  : _publish,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnails of what the moment will carry, each removable. Videos show a
/// neo tile with a film icon — generating real posters would need another
/// dependency and this reads clearly enough while composing.
class _DraftStrip extends StatelessWidget {
  const _DraftStrip({required this.media, required this.onRemove});

  final List<File> media;
  final void Function(File) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: media.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final file = media[i];
          final isVideo = MediaTools.isVideo(file.path);
          return Stack(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isVideo ? Neo.lilac : Neo.white,
                  border: Neo.borderThin,
                  borderRadius: Neo.cornerSm,
                ),
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: isVideo
                    ? const Icon(
                        Icons.videocam_rounded,
                        color: Neo.ink,
                        size: 28,
                      )
                    : Image.file(
                        file,
                        fit: BoxFit.cover,
                        width: 72,
                        height: 72,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: Neo.ink,
                        ),
                      ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => onRemove(file),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Neo.ink,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: Neo.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What the place dialog returns: the text, and whether to look it up.
class _PlaceInput {
  const _PlaceInput(this.name, {this.search = false});
  final String name;
  final bool search;
}

/// Name the place, or search for a different one — so a moment can be pinned
/// where it actually happened, not only where the phone is right now.
class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({required this.initial});
  final String initial;

  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: NeoBox(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Dónde fue?',
              style: txt.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Escribe el nombre del lugar, o búscalo para marcar el punto '
              'exacto en el mapa de datos.',
              textAlign: TextAlign.center,
              style: txt.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Cine del centro, Casa de May…',
              ),
              onSubmitted: (v) => Navigator.pop(context, _PlaceInput(v)),
            ),
            const SizedBox(height: 16),
            NeoButton(
              label: 'Buscar este lugar',
              icon: Icons.travel_explore_rounded,
              color: Neo.sky,
              expand: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
              onPressed: () =>
                  Navigator.pop(context, _PlaceInput(_name.text, search: true)),
            ),
            const SizedBox(height: 10),
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
                    label: 'Usar nombre',
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    onPressed: () =>
                        Navigator.pop(context, _PlaceInput(_name.text)),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.label,
    required this.child,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NeoBox(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      shadowOffset: Neo.shadowBtn,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeoSectionLabel(icon: icon, label: label, color: Neo.white),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
