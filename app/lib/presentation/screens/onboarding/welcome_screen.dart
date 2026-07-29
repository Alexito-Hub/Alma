import 'package:flutter/material.dart';

import '../../../core/theme/neo.dart';

/// One-time welcome shown on the very first launch, before login. A short,
/// heartfelt intro: why Alma exists (to keep our connection) and where it's
/// going (it keeps growing with us, so no memory is lost). Text is intentionally
/// easy to edit — it's personal.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  /// Called when the user finishes (or skips) the intro. The caller persists
  /// the "seen" flag and routes on to login.
  final VoidCallback onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pager = PageController();
  int _page = 0;

  static const _pages = <_WelcomePage>[
    _WelcomePage(
      icon: Icons.favorite_rounded,
      color: Neo.pink,
      title: 'Bienvenidos a lo nuestro',
      lead: 'ALE & MAY',
      body: 'Un espacio que es solo nuestro, para los dos.',
    ),
    _WelcomePage(
      icon: Icons.all_inclusive_rounded,
      color: Neo.lilac,
      title: 'Nuestra conexión',
      body:
          'Alma nació para guardar nuestra historia, nuestros recuerdos y fechas importantes y que aunque estemoes'
          'lejos. Aquí guardamos lo que somoss, nuestros recuerdos fotos y videos.'
          'y todo los que pensamos dia a dia, para que nunca se pierda.',
    ),
    _WelcomePage(
      icon: Icons.auto_awesome_rounded,
      color: Neo.mint,
      title: 'Esto recién empieza',
      body:
          'Nuestro recuerdo se va a mantener en mi laptop, tenemos 280 GB para guardar todo lo que queramos para que'
          'nuestros recuerdos nunca se pierdan.',
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
    } else {
      _pager.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Neo.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/logotype/alma.png',
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  if (!_isLast)
                    TextButton(
                      onPressed: widget.onDone,
                      child: Text(
                        'Saltar',
                        style: txt.labelLarge?.copyWith(color: Neo.ink),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _WelcomePageView(page: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 26 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i == _page ? Neo.ink : Neo.white,
                      border: Neo.borderThin,
                      borderRadius: Neo.cornerSm,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: NeoButton(
                label: _isLast ? 'Empezar' : 'Siguiente',
                icon: _isLast
                    ? Icons.favorite_rounded
                    : Icons.arrow_forward_rounded,
                expand: true,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage {
  const _WelcomePage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.lead,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? lead;
}

class _WelcomePageView extends StatelessWidget {
  const _WelcomePageView({required this.page});

  final _WelcomePage page;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          NeoAvatar(
            size: 108,
            color: page.color,
            shadowOffset: Neo.shadowCard,
            child: Icon(page.icon, color: Neo.ink, size: 48),
          ),
          const SizedBox(height: 28),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: txt.headlineMedium,
          ),
          if (page.lead != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Neo.yellow,
                border: Neo.borderThin,
                borderRadius: Neo.cornerSm,
              ),
              child: Text(
                page.lead!,
                style: txt.labelLarge?.copyWith(letterSpacing: 2),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: txt.bodyLarge?.copyWith(
              color: Neo.ink.withValues(alpha: .75),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
