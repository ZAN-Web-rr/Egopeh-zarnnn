/// Template for API keys configuration
/// 
/// Instructions:
/// 1. Copy this file to 'api_keys.dart' in the same directory
/// 2. Replace the placeholder values with your actual API keys
/// 3. The 'api_keys.dart' file is gitignored for security
/// 
/// NEVER commit actual API keys to version control!

class ApiKeys {
  // Firebase API Key (from google-services.json)
  static const String firebaseApiKey = 'YOUR_FIREBASE_API_KEY_HERE';
  
  // Google Maps API Key (if using maps)
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY_HERE';
  
  // Other API keys can be added here
  // static const String openAiApiKey = 'YOUR_OPENAI_API_KEY_HERE';
  // static const String stripeApiKey = 'YOUR_STRIPE_API_KEY_HERE';
  
  // Environment-specific configurations
  static const bool isProduction = false; // Set to true for production builds
  static const String environment = isProduction ? 'production' : 'development';
  
  // Validation method
  static bool get isConfigured {
    return firebaseApiKey != 'YOUR_FIREBASE_API_KEY_HERE' &&
           firebaseApiKey.isNotEmpty;
  }
}
