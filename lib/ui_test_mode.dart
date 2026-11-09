/// Yalnızca CI'daki emülatör ekran testinde `--dart-define=UI_TEST=true` ile açılır.
/// Testin önüne çıkıp onu bekleten pencereleri (güncelleme, konum ve bildirim izni) atlar.
/// Yayınlanan sürümlerde hiçbir zaman açık değildir (CI yayın derlemesinde verilmez).
/// Yayın (release) derlemesinde UI_TEST verilse bile kapalı kalır.
const bool kUiTest = bool.fromEnvironment('UI_TEST') && !bool.fromEnvironment('dart.vm.product');
