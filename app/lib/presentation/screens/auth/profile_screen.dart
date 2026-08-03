import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/neo.dart';
import '../../../data/device/media_tools.dart';
import '../../../data/remote/media_headers.dart';
import '../../../data/repositories/auth_repository.dart';

/// Edit profile from inside the app — change name and avatar. Sync and other
/// preferences live in Ajustes.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  File? _avatarFile;
  bool _busy = false;

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
    setState(() => _busy = true);
    try {
      var user = ref.read(currentUserProvider);
      if (_avatarFile != null) {
        user = await ref
            .read(authRepositoryProvider)
            .uploadAvatar(_avatarFile!);
      }
      final name = _name.text.trim();
      if (name.isNotEmpty && name != user?.displayName) {
        user = await ref
            .read(authRepositoryProvider)
            .updateProfile(displayName: name);
      }
      if (user != null) {
        ref.read(currentUserProvider.notifier).state = user;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: ${e.toString()}')),
        );
      }
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
    final me = ref.watch(currentUserProvider);
    final cs = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
          child: Column(
            children: [
              Row(
                children: [
                  NeoIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  Text('Tu perfil', style: txt.titleLarge),
                ],
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: _busy ? null : _pickAvatar,
                child: _AvatarView(file: _avatarFile, remoteUrl: me?.avatarUrl),
              ),
              const SizedBox(height: 14),
              NeoButton(
                label: 'Cambiar foto',
                icon: Icons.image_outlined,
                color: Neo.lilac,
                shadowOffset: Neo.shadowSm,
                onPressed: _busy ? null : _pickAvatar,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Tu nombre o apodo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tu correo: ${me?.email ?? "—"}',
                  style: txt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 28),
              NeoButton(
                label: 'Guardar cambios',
                icon: Icons.check_rounded,
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

class _AvatarView extends StatelessWidget {
  const _AvatarView({this.file, this.remoteUrl});
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
        httpHeaders: mediaHeaders(),
        fit: BoxFit.cover,
      );
    } else {
      content = const Icon(Icons.person, size: 52, color: Neo.ink);
    }
    return NeoAvatar(
      size: 140,
      color: Neo.rose,
      shadowOffset: Neo.shadowCard,
      child: SizedBox.expand(child: content),
    );
  }
}
