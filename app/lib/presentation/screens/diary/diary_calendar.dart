part of 'diary_screen.dart';

// Calendar card, its collapse toggle, and the view switch.

/// Calendar · continuous list · gallery. The grid the Feed used to own now
/// lives here, where the memories actually are.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _icons = [
    Icons.calendar_month_rounded,
    Icons.view_agenda_rounded,
    Icons.grid_view_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return NeoFrame(
      borderWidth: Neo.stroke,
      shadowOffset: Neo.shadowSm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _icons.length; i++) ...[
            if (i > 0)
              Container(width: Neo.strokeThin, height: 38, color: Neo.ink),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: Container(
                width: 42,
                height: 38,
                alignment: Alignment.center,
                color: i == index ? Neo.mint : Neo.white,
                child: Icon(_icons[i], size: 18, color: Neo.ink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CalendarToggle extends StatelessWidget {
  const _CalendarToggle({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shadowOffset: Neo.shadowSm,
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, size: 18, color: Neo.ink),
          const SizedBox(width: 8),
          Text('Calendario', style: txt.labelLarge),
          const Spacer(),
          Icon(
            open
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: Neo.ink,
          ),
        ],
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.focusedDay,
    required this.selectedDay,
    required this.events,
    required this.specials,
    required this.dayKey,
    required this.matchesDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final Map<DateTime, List<NoteLocal>> events;
  final List<SpecialDateLocal> specials;
  final DateTime Function(DateTime) dayKey;
  final bool Function(SpecialDateLocal, DateTime) matchesDay;
  final void Function(DateTime selected, DateTime focused) onDaySelected;
  final void Function(DateTime focused) onPageChanged;

  bool _isSpecial(DateTime day) => specials.any((s) => matchesDay(s, day));

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return NeoBox(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      shadowOffset: Neo.shadowBtn,
      child: TableCalendar<NoteLocal>(
        locale: 'es',
        firstDay: DateTime.utc(2015),
        lastDay: DateTime.utc(2035, 12, 31),
        focusedDay: focusedDay,
        currentDay: DateTime.now(),
        startingDayOfWeek: StartingDayOfWeek.monday,
        availableCalendarFormats: const {CalendarFormat.month: 'Mes'},
        selectedDayPredicate: (d) => isSameDay(selectedDay, d),
        eventLoader: (day) => events[dayKey(day)] ?? const [],
        onDaySelected: onDaySelected,
        onPageChanged: onPageChanged,
        rowHeight: 46,
        daysOfWeekHeight: 22,
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          headerPadding: const EdgeInsets.symmetric(vertical: 6),
          titleTextStyle:
              txt.titleMedium ?? const TextStyle(fontWeight: FontWeight.w800),
          leftChevronIcon: const Icon(
            Icons.chevron_left_rounded,
            color: Neo.ink,
          ),
          rightChevronIcon: const Icon(
            Icons.chevron_right_rounded,
            color: Neo.ink,
          ),
        ),
        daysOfWeekStyle: const DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            color: Neo.ink,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
          weekendStyle: TextStyle(
            color: Neo.ink,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
        calendarBuilders: CalendarBuilders<NoteLocal>(
          defaultBuilder: (context, day, _) => _cell(day),
          outsideBuilder: (context, day, _) => _cell(day, outside: true),
          disabledBuilder: (context, day, _) => _cell(day, outside: true),
          todayBuilder: (context, day, _) =>
              _cell(day, fill: Neo.yellow, heavy: true),
          selectedBuilder: (context, day, _) =>
              _cell(day, fill: Neo.pink, heavy: true),
          markerBuilder: (context, day, dayEvents) {
            final special = _isSpecial(day);
            final hasEntries = dayEvents.isNotEmpty;
            if (!special && !hasEntries) return const SizedBox.shrink();
            return Positioned(
              bottom: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasEntries)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Neo.ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (special)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.star_rounded, size: 9, color: Neo.ink),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _cell(
    DateTime day, {
    Color? fill,
    bool outside = false,
    bool heavy = false,
  }) {
    return Container(
      margin: const EdgeInsets.all(3),
      alignment: Alignment.center,
      decoration: fill == null
          ? null
          : BoxDecoration(
              color: fill,
              border: Neo.borderThin,
              borderRadius: Neo.cornerSm,
            ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: outside ? Neo.ink.withValues(alpha: .3) : Neo.ink,
          fontWeight: heavy ? FontWeight.w900 : FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }
}
