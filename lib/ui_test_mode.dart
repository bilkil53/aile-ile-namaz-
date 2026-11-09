/// Yalnızca CI'daki emülatör ekran testinde `--dart-define=UI_TEST=true` ile açılır.
/// Testin önüne çıkıp onu bekleten pencereleri (güncelleme, konum ve bildirim izni) atlar.
/// Yayınlanan sürümlerde hiçbir zaman açık değildir (CI yayın derlemesinde verilmez).
const bool kUiTest = bool.fromEnvironment('UI_TEST');
