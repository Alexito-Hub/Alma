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

  @override
  void dispose() {
    _intro.dispose();
    _noteCtrl.dispose();
    _statusCtrl.dispose();
    _postTitleCtrl.dispose();
    _postTagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveStatus() async {
    final text = _statusCtrl.text.trim();
    final me = ref.read(currentUserProvider);
    if (me == null || text.isEmpty) return;
    await _run(() async {
      await ref
          .read(statusRepositoryProvider)
          .updateMine(authorId: me.id, text: text);
      _statusCtrl.clear();
      _snack('Estado actualizado');
    });
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

  Future<void> _capture({required ImageSource source}) async {
    final me = ref.read(currentUserProvider);
    if (me == null) return;
    final picker = ImagePicker();
    final shot = await picker.pickImage(source: source, imageQuality: 92);
    if (shot == null) return;
    final cropped = await MediaTools.cropImage(shot.path);

    await _run(() async {
      final tags = _postTagsCtrl.text
          .split(RegExp(r'[\s,]+'))
          .where((t) => t.isNotEmpty)
          .map((t) => t.replaceAll('#', '').toLowerCase())
          .toList();

      await ref
          .read(postRepositoryProvider)
          .create(
            title: _postTitleCtrl.text.trim().isEmpty
                ? 'Sin título'
                : _postTitleCtrl.text.trim(),
            description: '',
            authorId: me.id,
            tags: tags,
            media: [File(cropped)],
          );
      _postTitleCtrl.clear();
      _postTagsCtrl.clear();
      _snack('Foto guardada');
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
                  NeoIconButton(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 14),
                  const NeoIconBadge(
                    icon: Icons.add_rounded,
                    color: Neo.pink,
                    size: 40,
                    iconSize: 26,
                  ),
                  const SizedBox(width: 10),
                  Text('Crear', style: txt.titleLarge),
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
                        child: TextField(
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
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: NeoButton(
                                    label: 'Galería',
                                    icon: Icons.image_outlined,
                                    color: Neo.white,
                                    expand: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    onPressed: _working
                                        ? null
                                        : () => _capture(
                                            source: ImageSource.gallery,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: NeoButton(
                                    label: 'Cámara',
                                    icon: Icons.camera_alt_outlined,
                                    expand: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    onPressed: _working
                                        ? null
                                        : () => _capture(
                                            source: ImageSource.camera,
                                          ),
                                  ),
                                ),
                              ],
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
