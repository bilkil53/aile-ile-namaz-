// Günün ayeti / hadisi / duası içerikleri.
import 'content_en.dart';

class DailyQuote {
  // Metinler Türkçe saklanır; okunurken seçilen dile çevrilir (content_en.dart).
  final String _category, _title, _text, _source;
  final String? arabic;
  const DailyQuote({required String category, required String title, required String text, required String source, this.arabic})
      : _category = category,
        _title = title,
        _text = text,
        _source = source;

  String get category => tc(_category);
  String get title => tc(_title);
  String get text => tc(_text);
  String get source => tc(_source);
}

class Greeting {
  final String _title, _category, _text;
  final String emoji;
  const Greeting({required String title, required String category, required this.emoji, required String text})
      : _title = title,
        _category = category,
        _text = text;

  String get title => tc(_title);
  String get category => tc(_category);
  String get text => tc(_text);

  /// Aileye gönderilen metin her zaman Türkçedir; alıcı kendi dilinde görür ([familyMessageText]).
  String get textTr => _text;
  String get textEn => contentEn[_text] ?? _text;
}

const ayetler = <DailyQuote>[
  DailyQuote(category: "Günün Ayeti · Diyanet Meali", title: "Namazın Önemi", text: "Şüphesiz namaz, mü’minler üzerine belirli vakitlerde farz kılınmıştır.", source: "Nisâ Sûresi, 103. Âyet (Diyanet İşleri Başkanlığı Meali)", arabic: "إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَابًا مَوْقُوتًا"),
  DailyQuote(category: "Günün Ayeti · Diyanet Meali", title: "Huşû ve Kurtuluş", text: "Müminler gerçekten kurtuluşa ermişlerdir; onlar ki, namazlarında derin bir saygı ve huşû içindedirler.", source: "Mü'minûn Sûresi, 1-2. Âyetler (Diyanet İşleri Başkanlığı Meali)", arabic: "قَدْ أَفْلَحَ الْمُؤْمِنُونَ ﴿١﴾ الَّذِينَ هُمْ فِي صَلَاتِهِمْ خَاشِعُونَ"),
  DailyQuote(category: "Günün Ayeti · Diyanet Meali", title: "Sabır ve Namazla Yardım", text: "Sabır ve namaz ile Allah'tan yardım isteyin. Şüphesiz o, huşû duyanlardan başkasına pek ağır gelir.", source: "Bakara Sûresi, 45. Âyet (Diyanet İşleri Başkanlığı Meali)", arabic: "وَاسْتَعِينُوا بِالصَّبْرِ وَالصَّلَاةِ"),
  DailyQuote(category: "Günün Ayeti · Diyanet Meali", title: "Kötülükten Alıkoyan Namaz", text: "Şüphesiz namaz, insanı hayasızlıktan ve her türlü kötülükten alıkoyar.", source: "Ankebût Sûresi, 45. Âyet (Diyanet İşleri Başkanlığı Meali)", arabic: "إِنَّ الصَّلَاةَ تَنْهَىٰ عَنِ الْفَحْشَاءِ وَالْمُنْكَرِ"),
];

const hadisler = <DailyQuote>[
  DailyQuote(category: "Günün Hadis-i Şerifi · Diyanet", title: "Namaz Dinin Direğidir", text: "Namaz dinin direğidir. Kim onu dosdoğru kılarsa dinini ikame etmiş olur; kim de onu terk ederse dinini yıkmış olur.", source: "Beyhakî, Şu'abü'l-Îmân (Diyanet Hadislerle İslam)", arabic: "الصَّلَاةُ عِمَادُ الدِّينِ"),
  DailyQuote(category: "Günün Hadis-i Şerifi · Diyanet", title: "Cemaatle Namazın Fazileti", text: "Cemaatle kılınan namaz, tek başına kılınan namazdan yirmi yedi derece daha faziletlidir.", source: "Buhârî, Ezân, 30; Müslim, Mesâcid, 249"),
  DailyQuote(category: "Günün Hadis-i Şerifi · Diyanet", title: "Kulun Rabbine En Yakın Olduğu An", text: "Kulun Rabbine en yakın olduğu an, secde anıdır. Öyleyse secdede çokça dua ediniz.", source: "Müslim, Salât, 215 (Diyanet İşleri Başkanlığı)", arabic: "أَقْرَبُ مَا يَكُونُ الْعَبْدُ مِنْ رَبِّهِ وَهُوَ سَاجِدٌ"),
  DailyQuote(category: "Günün Hadis-i Şerifi · Diyanet", title: "Günahları Arındıran Beş Vakit Namaz", text: "Birinizin kapısı önünden bir nehir aksa ve o kimse nehirde her gün beş kere yıkansa üzerinde hiç kir kalır mı? İşte beş vakit namaz da böyledir; Allah onunla günahları siler.", source: "Buhârî, Mevâkît, 6; Müslim, Mesâcid, 283"),
  DailyQuote(category: "Günün Hadis-i Şerifi · Diyanet", title: "Kıyamette İlk Hesaba Çekilecek Amel", text: "Kıyamet gününde kulun ilk hesaba çekileceği amel namazdır. Eğer namazı düzgün çıkarsa kurtulur ve kazanır.", source: "Tirmizî, Salât, 188 (Diyanet Hadislerle İslam)"),
];

const dualar = <DailyQuote>[
  DailyQuote(category: "Günün Duası · Manevi Niyaz", title: "İbadette Süreklilik Duası", text: "Ey Rabbim! Beni ve neslimi namazı dosdoğru ve devamlı kılanlardan eyle. Ey Rabbimiz, dualarımızı kabul buyur!", source: "İbrâhim Sûresi, 40. Âyet Meali / Manevi Dua", arabic: "رَبِّ اجْعَلْنِي مُقِيمَ الصَّلَاةِ وَمِنْ ذُرِّيَّتِي ۚ رَبَّنَا وَتَقَبَّلْ دُعَاءِ"),
  DailyQuote(category: "Günün Duası · Manevi Niyaz", title: "Gönül Huzuru ve Doğruluk", text: "Ey kalpleri halden hale çeviren Allah'ım! Kalbimizi rızana, ibadetine ve dinine sabit kıl. Bizi namazla huzur bulanlardan eyle.", source: "Tirmizî, De'avât, 120 (Manevi Niyaz)", arabic: "يَا مُقَلِّبَ الْقُلُوبِ ثَبِّتْ قَلْبِي عَلَى دِينِكَ"),
  DailyQuote(category: "Günün Duası · Manevi Niyaz", title: "Tövbe ve Kaza Azmi", text: "Allah'ım! Geçmişte kaçırdığımız, kusurlu kıldığımız namazlarımızı bağışla. Kaza borçlarımızı şevkle ve ihlasla tamamlamayı bizlere kolaylaştır.", source: "Manevi Dua ve İltica"),
  DailyQuote(category: "Günün Duası · Manevi Niyaz", title: "Rıza ve Cennet Duası", text: "Rabbena âtina fi'd-dünya haseneten ve fi'l-âhireti haseneten ve kınâ azâbe'n-nâr. Rabbimiz! Bize dünyada da iyilik ver, ahirette de iyilik ver ve bizi cehennem azabından koru.", source: "Bakara Sûresi, 201. Âyet"),
];

const motivasyonlar = <DailyQuote>[
  DailyQuote(category: "Bugünün Manevi Hatırlatması", title: "Namaz Vakti Bir Fırsattır", text: "Her ezan, dünyanın telaşından sıyrılıp Yaratıcının huzuruna çıkmak için sana sunulan eşsiz bir randevudur. Bugün vakitlerini erteleme.", source: "Aile ile Namaz Manevi Hatırlatma"),
  DailyQuote(category: "Bugünün Manevi Hatırlatması", title: "Birlikte Daha Güçlüyüz", text: "Aile fertlerinin 'Namazını kıldın mı?' teşviki, cennet yolunda birbirine uzatılan en samimi eldir. Aileni teşvik etmeyi unutma!", source: "Aile ile Namaz Manevi Hatırlatma"),
  DailyQuote(category: "Bugünün Manevi Hatırlatması", title: "Kaza Borcu Dağ Değildir", text: "Kılınan her bir kaza namazı, ruhun üzerindeki bir yükü hafifletir. Küçük adımların istikrarı, büyük engelleri aşmanın en kutlu yoludur.", source: "Aile ile Namaz Manevi Hatırlatma"),
];

const ozluSozler = <DailyQuote>[
  DailyQuote(category: "Günün Özlü Sözü · Hikmet", title: "Secdenin Kıymeti", text: "Secde, yere fısıldayıp göklerin ötesinden işitildiğin en yakın ve en samimi makamdır.", source: "Gönül Dünyasından Hikmet Damlaları"),
  DailyQuote(category: "Günün Özlü Sözü · Hikmet", title: "Vaktin Bereketi", text: "Zamanın efendisi olmak istiyorsan, vaktini namazla tanzim et; çünkü namaz ömrün nizamıdır.", source: "İslami Tefekkür ve Hikmet"),
];

const greetings = <Greeting>[
  Greeting(title: "Vakit Namazı Tebriki", category: "Tebrik", emoji: "🌟", text: "Allah kabul etsin, kıldığın namazlar kalbine nur, ömrüne huzur ve bereket olsun kardeşim."),
  Greeting(title: "Samimi Kabul Duası", category: "Dua", emoji: "🤲", text: "Rabbim kıldığın namazları, ettiğin duaları dergâh-ı izzetinde en güzel şekilde makbul eylesin."),
  Greeting(title: "İstikrar ve Gayret Takdiri", category: "İstikrar", emoji: "🌿", text: "Namaz dinin direğidir. Birlikte hayırda yarışarak istikrarımızı koruduğumuz için Elhamdülillah!"),
  Greeting(title: "Hayırlı ve Huzurlu Gün", category: "Dua", emoji: "🕊️", text: "Rabbim sana ve ailene afiyet, kalbine inşirah, hanene bereket ihsan eylesin."),
  Greeting(title: "Kaza Namazı Teşviki", category: "Kaza", emoji: "📿", text: "Kaza namazlarını eritmeye devam; Rabbim azmini, gayretini ve sevabını kat kat artırsın."),
  Greeting(title: "Günün Tamamlanma Şükrü", category: "Tebrik", emoji: "🌙", text: "Günün farzlarını tamamlayarak huzurla geceye kavuşturan Yüce Allah'a hamdolsun."),
];

int _dayOfYear(DateTime d) => d.difference(DateTime(d.year, 1, 1)).inDays + 1;

/// Günün içerikleri: ayet, hadis, dua, motivasyon (her gün değişir).
List<DailyQuote> dailyQuotes([DateTime? date]) {
  final day = _dayOfYear(date ?? DateTime.now());
  return [
    ayetler[day % ayetler.length],
    hadisler[day % hadisler.length],
    dualar[day % dualar.length],
    motivasyonlar[day % motivasyonlar.length],
  ];
}
