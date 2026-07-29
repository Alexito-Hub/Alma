import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/neo.dart';

/// Big, breathing day counter. Re-ticks every minute (cheap) so the number
/// stays current without forcing the whole Dashboard to rebuild.
class DaysTogetherCounter extends StatefulWidget {
  const DaysTogetherCounter({super.key, required this.since});
  final DateTime since;

  @override
  State<DaysTogetherCounter> createState() => _DaysTogetherCounterState();
}

class _DaysTogetherCounterState extends State<DaysTogetherCounter> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int get _days {
    final diff = DateTime.now().difference(widget.since);
    return diff.inDays.abs();
  }

  ({int years, int months, int days}) _breakdown() {
    var start = widget.since.toLocal();
    final now = DateTime.now();
    var years = now.year - start.year;
    var months = now.month - start.month;
    var days = now.day - start.day;
    if (days < 0) {
      months -= 1;
      final prevMonth = DateTime(now.year, now.month, 0);
      days += prevMonth.day;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    return (years: years, months: months, days: days);
  }

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    final d = _days;
    final b = _breakdown();
    final pretty = _formatBreakdown(b);

    return NeoBox(
      width: double.infinity,
      color: Neo.pink,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Neo.white,
              border: Neo.borderThin,
              borderRadius: Neo.cornerSm,
            ),
            child: Text(
              d == 1 ? 'DÍA JUNTOS' : 'DÍAS JUNTOS',
              style: txt.labelMedium?.copyWith(letterSpacing: 3),
            ),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                '$d',
                key: ValueKey(d),
                style: txt.displayLarge?.copyWith(
                  fontSize: 108,
                  height: .92,
                  fontWeight: FontWeight.w900,
                  color: Neo.ink,
                ),
              ),
            ),
          ),
          if (pretty.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              pretty,
              style: txt.titleSmall?.copyWith(
                color: Neo.ink.withValues(alpha: .8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatBreakdown(({int years, int months, int days}) b) {
    final parts = <String>[];
    if (b.years > 0) parts.add('${b.years} ${b.years == 1 ? "año" : "años"}');
    if (b.months > 0) {
      parts.add('${b.months} ${b.months == 1 ? "mes" : "meses"}');
    }
    if (b.days > 0 && b.years == 0) {
      parts.add('${b.days} ${b.days == 1 ? "día" : "días"}');
    }
    return parts.join(' · ');
  }
}
