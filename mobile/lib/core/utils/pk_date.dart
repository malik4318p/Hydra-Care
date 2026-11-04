/// Pakistan Standard Time is UTC+05:00 and has no DST, so the offset below
/// is a fixed constant, not a timezone database lookup. Mirrors the boundary
/// math already used by `TodaySalesService` so every "today, Pakistan time"
/// filter in the app agrees on the same UTC interval.
class PakistanDate {
  const PakistanDate._();

  static const Duration _offset = Duration(hours: 5);

  /// Today's calendar date in Pakistan local time, as a date-only UTC
  /// `DateTime` (time fields zeroed) suitable for a date picker's default.
  static DateTime todayLocal() {
    final pakistanNow = DateTime.now().toUtc().add(_offset);
    return DateTime.utc(pakistanNow.year, pakistanNow.month, pakistanNow.day);
  }

  /// The half-open UTC interval `[start, end)` covering local calendar day
  /// [localDate] (its year/month/day, any time-of-day and time zone on the
  /// value itself are ignored) in Pakistan Standard Time.
  static (DateTime startUtc, DateTime endUtc) utcBoundsFor(DateTime localDate) {
    final localMidnightAsUtc =
        DateTime.utc(localDate.year, localDate.month, localDate.day);
    final startUtc = localMidnightAsUtc.subtract(_offset);
    final endUtc = startUtc.add(const Duration(days: 1));
    return (startUtc, endUtc);
  }
}
