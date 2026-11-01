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

  /// Google Cloud'daki "Web application" OAuth istemcisinin Client ID'si (gizli değildir).
  /// Telefondaki hesap seçimiyle giriş, kimlik kartını bu ID için ister; Supabase de bunu doğrular.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '688413758748-g6lmmi2injhh48hpemku3n4475vfdvia.apps.googleusercontent.com',
  );

  /// Google girişinden sonra uygulamaya dönüş adresi (yedek tarayıcı girişi için).
  /// AndroidManifest / Info.plist içindeki şema ile aynı olmalıdır.
  static const authRedirect = 'io.supabase.aileilenamaz://login-callback/';

  /// Öneri ve hata bildirimlerinin gideceği adres (kullanıcı mail uygulamasıyla gönderir).
  static const supportEmail = 'e.bilkil5391@gmail.com';
}
