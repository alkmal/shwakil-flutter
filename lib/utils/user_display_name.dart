class UserDisplayName {
  const UserDisplayName._();

  static String fromMap(Map<String, dynamic>? user, {String fallback = ''}) {
    if (user == null) {
      return fallback;
    }

    for (final key in const [
      'displayName',
      'businessName',
      'fullName',
      'username',
    ]) {
      final value = user[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }

    return fallback;
  }

  static String initialFromMap(
    Map<String, dynamic>? user, {
    String fallback = '-',
  }) {
    final displayName = fromMap(user);
    if (displayName.isEmpty) {
      return fallback;
    }

    return String.fromCharCode(displayName.runes.first).toUpperCase();
  }
}
