/// Supabase bağlantı ayarları.
/// Publishable (anon) anahtar istemci tarafında kullanılmak üzere tasarlanmıştır;
/// veri güvenliği veritabanındaki RLS kurallarıyla sağlanır.
/// Gizli (service_role) anahtarı ASLA bu uygulamaya koymayın.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://tgshrnodnhmnofjhzpqp.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ecpaSUNve-SlWZ1Vk6XRkA_R40sbBvf',
  );

  /// Google girişinden sonra uygulamaya dönüş adresi.
  /// AndroidManifest / Info.plist içindeki şema ile aynı olmalıdır.
  static const authRedirect = 'io.supabase.aileilenamaz://login-callback/';
}
