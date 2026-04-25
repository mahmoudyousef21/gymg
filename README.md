# LiftTier Flutter App

## Run locally

1. Install Flutter dependencies:

	flutter pub get

2. Start the app with your Supabase project values:

	flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

## Authentication setup

This app uses Supabase Auth with email/password and Google OAuth.

### Supabase URL Configuration

In Supabase Dashboard -> Authentication -> URL Configuration:

- Add your web origin(s) to Site URL and Redirect URLs for web sign-in.
- For mobile OAuth callback, add:

  io.supabase.flutter://login-callback

### Google provider

In Supabase Dashboard -> Authentication -> Providers -> Google:

- Enable Google provider.
- Ensure the redirect/callback URLs above are present in Supabase URL Configuration.

### Mobile deep-link callback

This project is already configured for mobile callback handling:

- Android intent-filter in android/app/src/main/AndroidManifest.xml
- iOS URL scheme in ios/Runner/Info.plist

Both are set to use:

io.supabase.flutter://login-callback
"# gymg" 
