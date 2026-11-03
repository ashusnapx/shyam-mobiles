/// Which backend this build talks to (docs/FIREBASE.md D7): `--dart-define=BACKEND=firebase`, else Supabase until the
/// cut-over. One switch for the whole app, so a build never mixes the two. Removed in Phase 2 with Supabase.
enum Backend { supabase, firebase }

const backend = String.fromEnvironment('BACKEND') == 'firebase' ? Backend.firebase : Backend.supabase;

/// `--dart-define=USE_EMULATORS=true`: the Firebase build talks to the local emulator suite (docs/FIREBASE.md §8).
const useEmulators = bool.fromEnvironment('USE_EMULATORS');
