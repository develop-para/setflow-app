/// A server-confirmed, account-bound grant. Never restored from a snapshot.
class PersonalCoachingAccess {
  const PersonalCoachingAccess({required this.userId, required this.expiresAt});
  final String userId;
  final DateTime expiresAt;

  bool isActiveFor(String? accountId, DateTime now) =>
      accountId == userId && now.toUtc().isBefore(expiresAt.toUtc());
}

abstract interface class PersonalCoachingRepository {
  Future<PersonalCoachingAccess?> loadMyPersonalCoachingAccess();
}
