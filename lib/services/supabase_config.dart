abstract final class SupabaseConfig {
  static const projectUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://fblrtxnpgftrtplqmsqe.supabase.co',
  );

  // Publishable keys are designed for client applications. Database access is
  // protected by RLS; never place a service-role key in the app.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_C9fh17Vm_9AV1xnCcyFX6A_frY8lgdM',
  );

  static const mobileAuthRedirect = 'com.setflow.setflow://login-callback';

  /// Register Naver as a Supabase custom OAuth/OIDC provider and pass its wire
  /// name (for example custom:naver) at build time.
  static const naverProviderName = String.fromEnvironment(
    'SUPABASE_NAVER_PROVIDER',
  );
}
