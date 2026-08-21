#!/usr/bin/env bash
# Builds the Flutter web bundle on a Vercel builder.
#
# Vercel has no Flutter runtime, so the SDK is fetched per build. The version is
# pinned to the same one CI and the release build use — a web bundle compiled by
# a different SDK than the APK is a debugging trap nobody enjoys.
set -euo pipefail

FLUTTER_VERSION="3.44.7"
FLUTTER_DIR="$HOME/flutter"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "==> Fetching Flutter $FLUTTER_VERSION"
  # --depth 1 on the tag: the full history is ~1GB and none of it is needed.
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# Vercel's builder runs as a user git does not recognise as the repo owner.
git config --global --add safe.directory "$FLUTTER_DIR" || true

flutter --version
flutter pub get

# Build-time secrets come from Vercel project env vars. Absent, the defaults in
# SupabaseConfig apply, which is what preview builds want.
EXTRA_ARGS=()
if [ -n "${SUPABASE_URL:-}" ]; then
  EXTRA_ARGS+=("--dart-define=SUPABASE_URL=$SUPABASE_URL")
fi
if [ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  EXTRA_ARGS+=("--dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY")
fi

echo "==> Building web bundle"
flutter build web --release "${EXTRA_ARGS[@]}"
