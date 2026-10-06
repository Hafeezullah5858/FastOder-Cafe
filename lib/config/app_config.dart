class AppConfig {
  static const appName = 'FastOder Cafe';

  // Add production values through secure configuration/environment variables.
  // Do not commit private API keys or Firebase service-account credentials.
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
}
