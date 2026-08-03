import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/neo.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/status_repository.dart';
import '../../widgets/couple_bond_graphic.dart';
import '../../widgets/days_together_counter.dart';
import '../../widgets/status_box.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'Buena madrugada';
    if (h < 13) return 'Buenos días';
    if (h < 20) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String? _withBase(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    return '${Env.apiBaseUrl}$url';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final partner = ref.watch(partnerUserProvider);
    final partnerStatus = ref.watch(partnerStatusProvider).valueOrNull;
    final myStatus = ref.watch(myStatusProvider).valueOrNull;
    final since = me?.coupleStartedAt ?? DateTime.now();
    final txt = Theme.of(context).textTheme;

    final myAvatar = _withBase(me?.avatarUrl);
    final partnerAvatar = _withBase(partner?.avatarUrl);

    return ColoredBox(
      color: Neo.paper,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      NeoReveal(
                        child: NeoBox(
                          color: Neo.yellow,
                          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                          shadowOffset: Neo.shadowBtn,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _greeting().toUpperCase(),
                                      style: txt.labelSmall?.copyWith(
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (me?.prettyName ?? 'amor'),
                                      style: txt.titleLarge,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const NeoIconBadge(
                                icon: Icons.favorite_rounded,
                                color: Neo.white,
                                size: 44,
                                iconSize: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(flex: 2),
                      NeoReveal(
                        delay: const Duration(milliseconds: 90),
                        child: DaysTogetherCounter(since: since),
                      ),
                      const SizedBox(height: 18),
                      NeoReveal(
                        delay: const Duration(milliseconds: 180),
                        child: StatusBox(
                          text: partnerStatus?.text,
                          updatedAt: partnerStatus?.updatedAt,
                          partnerLabel: (partner?.prettyName ?? 'pareja'),
                          imagePath: partnerStatus?.imagePath,
                          imageUrl: partnerStatus?.remoteImageUrl,
                        ),
                      ),
                      if (myStatus != null && myStatus.text.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        NeoReveal(
                          delay: const Duration(milliseconds: 240),
                          child: _MyStatusChip(
                            text: myStatus.text,
                            at: myStatus.updatedAt,
                          ),
                        ),
                      ],
                      const Spacer(flex: 3),
                      NeoReveal(
                        delay: const Duration(milliseconds: 300),
                        child: NeoBox(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          shadowOffset: Neo.shadowBtn,
                          child: CoupleBondGraphic(
                            leftAvatarUrl: myAvatar,
                            rightAvatarUrl: partnerAvatar,
                            leftLabel: (me?.prettyName ?? 'amor'),
                            rightLabel: (partner?.prettyName ?? 'pareja'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MyStatusChip extends StatelessWidget {
  const _MyStatusChip({required this.text, this.at});
  final String text;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .62,
        ),
        decoration: BoxDecoration(
          color: Neo.sky,
          borderRadius: Neo.cornerSm,
          border: Neo.borderThin,
          boxShadow: Neo.shadow(const Offset(2, 2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_rounded, size: 15, color: Neo.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'tú: $text',
                style: txt.bodySmall?.copyWith(
                  color: Neo.ink,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
