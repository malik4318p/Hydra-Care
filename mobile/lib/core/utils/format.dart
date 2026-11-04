String formatMoney(num value) => value.toStringAsFixed(2);

String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso;
  }
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// Formats an ISO timestamp as a Pakistan-local date and time
/// (`YYYY-MM-DD HH:MM`), independent of the device's own time zone. Pakistan
/// Standard Time is a fixed UTC+05:00 offset with no DST.
String formatPakistanDateTime(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso;
  }
  final pk = parsed.toUtc().add(const Duration(hours: 5));
  final month = pk.month.toString().padLeft(2, '0');
  final day = pk.day.toString().padLeft(2, '0');
  final hour = pk.hour.toString().padLeft(2, '0');
  final minute = pk.minute.toString().padLeft(2, '0');
  return '${pk.year}-$month-$day $hour:$minute';
}
