/// 막차 알림을 언제 울릴지 계산한다.
///
/// [departBy]는 막차를 타기 위해 출발해야 하는 마지막 시각이고,
/// [leadMinutes]는 그보다 몇 분 먼저 알릴지다. 이미 지난 시각이면
/// 알림을 예약할 수 없으므로 null을 돌려준다.
DateTime? planAlertTime({
  required DateTime departBy,
  required int leadMinutes,
  required DateTime now,
}) {
  if (!departBy.isAfter(now)) return null;
  final alertAt = departBy.subtract(Duration(minutes: leadMinutes));
  // 알림 시각은 지났지만 아직 출발은 가능하면 바로 알린다.
  return alertAt.isAfter(now) ? alertAt : now;
}

/// 출발까지 남은 시간을 "1시간 5분" 같은 글자로 바꾼다.
String formatRemaining(Duration remaining) {
  if (remaining.isNegative || remaining.inMinutes == 0) return '지금 출발';
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  if (hours == 0) return '$minutes분';
  if (minutes == 0) return '$hours시간';
  return '$hours시간 $minutes분';
}
