# Setflow

Setflow is a Flutter prototype for zero-friction workout tracking and coaching.
The implementation follows the React UX reference in `C:\Users\SIMJAE\Downloads\setflow`
and the product documents under [`share`](share/).

## Included flows

- Role selection and onboarding for members, trainers, and gyms
- Calendar-first workout tracking with weekly totals
- Daily workout, exercise library, set editing, completion, and rest timer
- Personal routines and expert routine marketplace
- Community and asynchronous coaching consultation
- Trainer member management, routine performance, consultation, and revenue views
- Gym member, trainer, and settlement views
- Operator user review, certification queue, SLA, and settlement views
- Responsive light/dark mobile UI
- Material 3 semantic design tokens and reusable production state components
- Replaceable `AppRepository` data boundary with Hive local persistence
- Google ID token login through the Setflow custom auth API

## Architecture

- `lib/theme/`: semantic color, spacing, radius, shadow, and motion tokens
- `lib/data/`: repository contracts, Hive adapter, and versioned snapshot codec
- `lib/app_state.dart`: synchronous UI state with debounced repository writes

The local Hive adapter can be replaced by a Supabase repository without changing
the screen-level state API. Login does not use Supabase Auth: the `custom-auth`
Edge Function verifies Google ID tokens and issues opaque Setflow sessions stored
as hashes in `public.user_sessions`.

## Google login setup

1. Create a Google OAuth web client and add the local/production origins.
2. Set the Edge Function secrets `GOOGLE_CLIENT_IDS` (comma-separated when
   multiple client IDs are used) and `ALLOWED_ORIGINS` in Supabase.
3. Run Flutter with the same web client ID:

```powershell
flutter run -d chrome --web-port=7357 --dart-define=GOOGLE_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

For a different auth endpoint, also pass
`--dart-define=CUSTOM_AUTH_URL=https://.../functions/v1/custom-auth`.
Never put the Supabase service-role/secret key or a Google client secret in the
Flutter app. Kakao, Apple, and email buttons intentionally show a `준비 중`
dialog until their server integrations are added.

## Run

```powershell
flutter pub get
flutter run
```

For a web preview:

```powershell
flutter run -d chrome
```

## Verify

```powershell
flutter analyze
flutter test
flutter build web
```
