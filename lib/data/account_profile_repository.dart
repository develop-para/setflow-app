/// Personal account data belongs to Setflow, separately from the login vendor.
class AccountProfile {
  const AccountProfile({
    required this.userId,
    required this.email,
    required this.providers,
    this.birthDate,
  });

  final String userId;
  final String? email;
  final Set<String> providers;
  final DateTime? birthDate;

  bool get needsBirthDate =>
      birthDate == null && providers.any((provider) => provider != 'email');
}

abstract interface class AccountProfileRepository {
  Future<AccountProfile> loadMyProfile();
  Future<AccountProfile> saveMyBirthDate(DateTime? birthDate);
}

abstract final class AccountBirthDate {
  static String format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? parse(String value) {
    final text = value.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
    final parsed = DateTime.tryParse(text);
    return parsed != null && format(parsed) == text ? parsed : null;
  }

  static String? validate(String? value, {DateTime? today}) {
    if (value == null || value.trim().isEmpty) return null;
    final date = parse(value);
    if (date == null) return '생년월일을 YYYY-MM-DD 형식으로 입력해주세요.';
    final now = today ?? DateTime.now();
    if (date.year < 1900 ||
        date.isAfter(DateTime(now.year, now.month, now.day))) {
      return '1900년부터 오늘까지의 날짜를 입력해주세요.';
    }
    return null;
  }
}
