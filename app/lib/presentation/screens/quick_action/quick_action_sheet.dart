import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/neo.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/status_repository.dart';
import '../../../data/sync/media_compressor.dart';
import '../../../data/sync/sync_worker.dart';

/// "Crear" sheet opened from the bottom bar's central button.
///
/// One composer: a "siente". It used to be a two-way switch with a feed
/// moment on the other side, but the Feed was absorbed into the Diary and its
/// screens are gone — the composer stayed behind, uploading media to a server
/// nothing read back. Memories are written from the Diary tab, plans from
/// Citas, and personalisation (shared background, avatar) from Ajustes.
class QuickActionSheet extends ConsumerStatefulWidget {
  const QuickActionSheet({super.key});

  @override
  ConsumerState<QuickActionSheet> createState() => _QuickActionSheetState();
}

class _QuickActionSheetState extends ConsumerState<QuickActionSheet>
    with SingleTickerProviderStateMixin {
  final _statusCtrl = TextEditingController();

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  bool _working = false;

  /// Optional snapshot attached to the next "siente".
  File? _statusPhoto;

  @override
  void dispose() {
    _intro.dispose();
    _statusCtrl.dispose();
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
                      const SizedBox(height: 18),
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
                                  NeoFrame(
                                    width: 64,
                                    height: 64,
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
