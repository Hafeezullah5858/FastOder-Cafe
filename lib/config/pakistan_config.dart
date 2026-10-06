class PakistanConfig {
  static const currencyCode = 'PKR';
  static const currencySymbol = 'Rs.';
  static const countryDialCode = '+92';

  /// Accepts common Pakistani mobile formats: 03XXXXXXXXX or +923XXXXXXXXX.
  static bool isValidMobile(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[\s-()]'), '');
    return RegExp(r'^(?:03\d{9}|\+923\d{9})$').hasMatch(normalized);
  }

  static String normalizeMobile(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[\s-()]'), '');
    if (normalized.startsWith('03') && normalized.length == 11) {
      return '+92${normalized.substring(1)}';
    }
    return normalized;
  }
}
