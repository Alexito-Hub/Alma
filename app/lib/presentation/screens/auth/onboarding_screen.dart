import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/neo.dart';
import '../../../data/device/media_tools.dart';
import '../../../data/repositories/auth_repository.dart';

/// Post-registration identity step. Asks for an avatar + display name so the
/// bond graphic and chat bubbles have something warmer than an email.
///
/// Skippable — both fields are optional. The user can always edit later from
/// the Dashboard.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  File? _avatarFile;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(currentUserProvider)?.displayName ?? '';
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final shot = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (shot == null) return;
    final cropped = await MediaTools.cropImage(shot.path, square: true);
    if (mounted) setState(() => _avatarFile = File(cropped));
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var user = ref.read(currentUserProvider);

      // Avatar first so we have the URL when the user lands on Dashboard.
      if (_avatarFile != null) {
        user = await ref
            .read(authRepositoryProvider)
            .uploadAvatar(_avatarFile!);
      }
      // Then display_name.
      final name = _name.text.trim();
      if (name.isNotEmpty) {
        user = await ref
            .read(authRepositoryProvider)
            .updateProfile(displayName: name);
      }
      if (user != null) {
        ref.read(currentUserProvider.notifier).state = user;
      }
      widget.onDone?.call();
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    // Persist a sensible default so AuthGate doesn't bounce us back here.
    setState(() => _busy = true);
    try {
      var user = ref.read(currentUserProvider);
      final fallback = (user?.email ?? '').split('@').first;
      if (fallback.isNotEmpty) {
        final updated = await ref
            .read(authRepositoryProvider)
            .updateProfile(displayName: fallback);
        ref.read(currentUserProvider.notifier).state = updated;
      }
      widget.onDone?.call();
    } catch (_) {
      // If the request fails (offline), at least update locally so the
      // gate lets us through this session.
      final user = ref.read(currentUserProvider);
      if (user != null) {
        ref.read(currentUserProvider.notifier).state = user.copyWith(
          displayName: user.email.split('@').first,
        );
      }
      widget.onDone?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: NeoButton(
                  label: 'Omitir',
                  color: Neo.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shadowOffset: Neo.shadowSm,
                  onPressed: _busy ? null : _skip,
                ),
              ),
              const SizedBox(height: 16),
              Text('Preséntate', style: txt.headlineMedium),
              const SizedBox(height: 10),
              Text(
                'Tu pareja verá tu foto y tu nombre en el lienzo central. Lo puedes cambiar cuando quieras.',
                style: txt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 36),
              Center(
                child: GestureDetector(
                  onTap: _busy ? null : _pickAvatar,
                  child: _AvatarPicker(
                    file: _avatarFile,
                    remoteUrl: me?.avatarUrl,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Neo.sky,
                    border: Neo.borderThin,
                    borderRadius: Neo.cornerSm,
                  ),
                  child: Text(
                    _avatarFile == null && (me?.avatarUrl ?? '').isEmpty
                        ? 'Toca para elegir una foto'
                        : 'Toca para cambiar',
                    style: txt.labelSmall?.copyWith(letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Tu nombre o apodo',
                  prefixIcon: Icon(Icons.person_outline),
                  hintText: 'Como quieres que te vea',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                NeoErrorBanner(message: _error!),
              ],
              const SizedBox(height: 24),
              NeoButton(
                label: 'Continuar',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                busy: _busy,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({this.file, this.remoteUrl});
  final File? file;
  final String? remoteUrl;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (file != null) {
      content = Image.file(file!, fit: BoxFit.cover);
    } else if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      final url = remoteUrl!.startsWith('http')
          ? remoteUrl!
          : '${Env.apiBaseUrl}$remoteUrl';
      content = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => _placeholder(),
      );
    } else {
      content = _placeholder();
    }

    return NeoAvatar(
      size: 148,
      color: Neo.rose,
      shadowOffset: Neo.shadowCard,
      child: SizedBox.expand(child: content),
    );
  }

  Widget _placeholder() => const Center(
    child: Icon(Icons.add_a_photo_outlined, size: 40, color: Neo.ink),
  );
}
