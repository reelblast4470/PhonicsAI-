/// Date helpers kept pure so they are unit-testable without a clock hack.
abstract final class DateUtil {
  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whole days between two dates, ignoring time of day (DST-safe because it
  /// works on calendar days, not 24h multiples).
  static int daysBetween(DateTime from, DateTime to) {
    final a = startOfDay(from), b = startOfDay(to);
    return DateTime(b.year, b.month, b.day)
            .difference(DateTime(a.year, a.month, a.day))
            .inDays;
  }

  /// Monday-based week key, e.g. 2026-09-14 -> 2026-09-14 (Mon) -> this week.
  static DateTime weekStart(DateTime d) {
    final day = startOfDay(d);
    return addDays(day, -(day.weekday - 1));
  }

  static int isoWeek(DateTime d) {
    final jan4 = DateTime(d.year, 1, 4);
    final week1Start = addDays(jan4, -(jan4.weekday - 1));
    return daysBetween(week1Start, weekStart(d)) ~/ 7 + 1;
  }
}
