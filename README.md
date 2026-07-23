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

## Architecture

- `lib/theme/`: semantic color, spacing, radius, shadow, and motion tokens
- `lib/data/`: repository contracts, Hive adapter, and versioned snapshot codec
- `lib/app_state.dart`: synchronous UI state with debounced repository writes

The local Hive adapter can be replaced by a Supabase repository without changing
the screen-level state API.

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
