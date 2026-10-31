// Eski uygulamadan taşındı: vakte özel hatırlatma sözleri (DailyContentProvider.getPrayerApproachingQuote).
import 'daily_content.dart';

const approachingQuotes = <String, List<DailyQuote>>{
  'fajr': [
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Sabah Niyazı", title: "Sabah Namazının Fazileti", text: "Kim sabah namazını kılarsa, o kimse Allah'ın güvencesi ve himayesi altındadır.", source: "Müslim, Mesâcid, 262 (Diyanet Hadislerle İslam)"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Sabah Bereketi", title: "Dünyadan Hayırlı İki Rekât", text: "Sabah namazının iki rekât sünneti, dünyadan ve dünyadaki her şeyden daha hayırlıdır.", source: "Müslim, Müsâfirîn, 96 (Diyanet İşleri Başkanlığı)"),
    DailyQuote(category: "Diyanet Meali · Âyet-i Kerime & Sabah", title: "Şahitli Sabah Namazı", text: "Gündüzün güneş dönüp batmaya meylettiği andan gecenin karanlığına kadar namaz kıl; bir de sabah namazını. Çünkü sabah namazı meleklerin şahit olduğu bir namazdır.", source: "İsrâ Sûresi, 78. Âyet (Diyanet Meali)", arabic: "إِنَّ قُرْآنَ الْفَجْرِ كَانَ مَشْهُودًا"),
    DailyQuote(category: "Diyanet · Sabah Duası ve İltica", title: "Sabahın Nuru ve Afiyeti", text: "Allah'ım! Sabahın bereketini, hayrını, nurunu ve hidayetini Sen'den niyaz ederiz. Bizi ve ailemizi sabah namazının nurlu iklimiyle bereketlendir.", source: "Ebû Dâvûd, Edeb, 101 & Diyanet Niyaz"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Meleklerin Şahitliği", title: "Meleklerin Buluşma Vakti", text: "Gece ve gündüz melekleri sabah namazında toplanırlar. Sabah namazı ibadetin ve günün en bereketli anahtarıdır.", source: "Buhârî, Mevâkît, 16 (Diyanet Hadislerle İslam)"),
    DailyQuote(category: "Diyanet · Manevi Niyaz & Seher Vakti", title: "Seherde Huzura Durmak", text: "Ey Rabbim! Seher vaktinde uyanıp huzuruna yöneldik. Bizi gaflet uykusundan uyandır, kalbimizi namazla aydınlat, dualarımızı kabul eyle.", source: "Diyanet Manevi Dua ve İltica"),
  ],
  'cuma': [
    DailyQuote(category: "Diyanet · Cuma Sûresi & Cuma Namazı Vakti 🕌", title: "Hayırlı Cumalar · Cuma Namazı Vakti", text: "Ey iman edenler! Cuma günü namaza çağrıldığınızda Allah'ı anmaya koşun ve alışverişi bırakın. Eğer bilirseniz bu sizin için daha hayırlıdır.", source: "Cuma Sûresi, 9. Âyet (Diyanet İşleri Başkanlığı)"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Cuma Müjdesi", title: "Haftanın En Hayırlı Günü", text: "Üzerine güneşin doğduğu en hayırlı gün Cuma günüdür. O günde öyle mübarek bir icabet saati vardır ki, Müslüman kul o anda dua ederse Allah duasını kabul buyurur.", source: "Müslim, Cum'a, 18 (Diyanet Hadislerle İslam)"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Cuma Namazı Fazileti", title: "Cuma Namazı ve Bağışlanma", text: "Cuma namazına güzelce hazırlanıp huşû ile camiye giden kimsenin iki cuma arasındaki kusurları bağışlanır.", source: "Buhârî, Cum'a, 6; Müslim, Cum'a, 27"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Peygamberimize Salavat", title: "Cuma Salavatı ve Selam", text: "Cuma günü bana çokça salavat getiriniz; çünkü sizin salavatlarınız bana arz olunur. Allahümme salli alâ seyyidinâ Muhammedin ve alâ âli seyyidinâ Muhammed.", source: "Ebû Dâvûd, Salât, 201 (Diyanet İşleri Başkanlığı)"),
    DailyQuote(category: "Diyanet · Cuma Niyazı ve Rahmet", title: "Cuma Bereketi ve Aile Duası", text: "Rabbimiz! Bu mübarek Cuma gününde hürmetine ailemizi koru, dualarımızı ve tevbelerimizi makbul eyle, hanelerimize huzur ve bereket ihsan buyur.", source: "Diyanet Cuma Duası"),
  ],
  'dhuhr': [
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Öğle Vakti", title: "Gök Kapılarının Açıldığı An", text: "Öğle vakti, sema kapılarının açıldığı ve salih amellerin Allah Teâlâ'ya yükseldiği mübarek bir vakittir.", source: "Tirmizî, Vitir, 15 (Diyanet İşleri Başkanlığı)"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Günün Telaşı", title: "Dünya Meşgalesinde Tevekkül", text: "Günün ortasındaki dünya telaşından sıyrılıp Rabbin huzuruna durmak, kalbin yorgunluğunu dindirir ve ömrü bereketlendirir.", source: "Diyanet Hadislerle İslam"),
    DailyQuote(category: "Diyanet Meali · Âyet-i Kerime & Öğle", title: "Namaz Vakitli Bir Farzdır", text: "Şüphesiz namaz, mü’minler üzerine belirli vakitlerde farz kılınmıştır. Vaktinde kılınan namaz Allah katında en sevimli ameldir.", source: "Nisâ Sûresi, 103. Âyet (Diyanet Meali)", arabic: "إِنَّ الصَّلَاةَ كَانَتْ عَلَى الْمُؤْمِنِينَ كِتَابًا مَوْقُوتًا"),
    DailyQuote(category: "Diyanet · Öğle Niyazı ve Dua", title: "Günün İkramı ve Şükür", text: "Allah'ım! Günün yarısına ulaştık, bize lütfettiğin nimetlerin şükrünü eda edebilmeyi ve huzurunda samimiyetle secdeye varmayı nasip eyle.", source: "Diyanet Manevi İltica"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Öğle Sünneti", title: "Öğle Namazının Fazileti", text: "Öğle namazından önce kılınan dört rekât sünnet, sema kapılarının aralandığı kıymetli bir ibadettir.", source: "Tirmizî, Salât, 192 (Diyanet Hadislerle İslam)"),
  ],
  'asr': [
    DailyQuote(category: "Diyanet Meali · Âyet-i Kerime & İkindi", title: "Orta Namaza Dikkat Edin", text: "Namazlara ve orta namaza (ikindi namazına) devam edin; gönülden boyun eğerek Allah'ın huzurunda durun.", source: "Bakara Sûresi, 238. Âyet (Diyanet İşleri Başkanlığı Meali)", arabic: "حَافِظُوا عَلَى الصَّلَوَاتِ وَالصَّلَاةِ الْوُسْطَىٰ"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & İkindi Müjdesi", title: "Cennet Müjdesi", text: "Kim sabah ve ikindi namazlarını aksatmadan huşû ile kılarsa cennete girer.", source: "Buhârî, Mevâkît, 17; Müslim, Mesâcid, 215"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & İkindi Vaktinin Kıymeti", title: "Meleklerin Hüsn-ü Şahitliği", text: "İkindi namazını vaktinde kılan kimse, o vaktin meleklerinin Rablerine sunacağı güzel şahitliğe nail olur.", source: "Buhârî, Ezân, 31 (Diyanet Hadislerle İslam)"),
    DailyQuote(category: "Diyanet · İkindi Duası ve İltica", title: "Günün Hitamında İstiğfar", text: "Rabbimiz! Gün batımına doğru ilerlerken huzurundayız; günahlarımızı bağışla, kalan ömrümüzü ve amellerimizi rızanla taçlandır.", source: "Diyanet Manevi Niyaz"),
    DailyQuote(category: "Diyanet · Hikmet ve İbadet & İkindi", title: "Vaktin Kıymetini Bilmek", text: "Asr vaktinde ikindi namazı, zamanın hızla akıp gittiğini hatırlatan ve kulun Rabbine sadakatini tazeleyen mukaddes bir kalkandır.", source: "Diyanet Hadislerle İslam Tefekkürü"),
  ],
  'maghrib': [
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Akşam Niyazı", title: "Dua ve İltica Vakti", text: "Akşam vakti girdiğinde dualarınıza sarılın; günün yorgunluğunu huzur ve şükür secdesiyle taçlandırın.", source: "Ebû Dâvûd, Salât, 9 (Diyanet İşleri Başkanlığı)"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Akşam Ezanı Duası", title: "Akşam Ezanı İlticası", text: "Akşam ezanı okunurken: 'Allah'ım! Bu Senin gecenin gelişi, gündüzünün çekilişi ve kullarının davet sesleridir. Beni ve sevdiklerimi bağışla' diye dua ediniz.", source: "Tirmizî, De'avât, 85 (Diyanet İşleri Başkanlığı)"),
    DailyQuote(category: "Diyanet Meali · Âyet-i Kerime & Akşam", title: "İyilikler Kötülükleri Giderir", text: "Gündüzün iki tarafında ve gecenin gündüze yakın vakitlerinde namaz kıl. Çünkü iyilikler kötülükleri giderir.", source: "Hûd Sûresi, 114. Âyet (Diyanet Meali)", arabic: "إِنَّ الْحَسَنَاتِ يُذْهِبْنَ السَّيِّئَاتِ"),
    DailyQuote(category: "Diyanet · Akşam Duası ve İstiğfar", title: "Günün Şükrü ve Huzur", text: "Allah'ım! Akşama erdik, mülk de Sana ait olarak akşama erdi. Bizi bu gecenin şerrinden koru, hayrını ve affını üzerimize yağdır.", source: "Müslim, Zikir, 75 & Diyanet Niyaz"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Akşam Namazı", title: "Akşam Namazının Bereketli Ecri", text: "Akşam namazından sonra yapılan samimi tevbe ve dualar, gün boyunca işlenen küçük kusurlara kefaret olur.", source: "Tirmizî, De'avât, 108 (Diyanet Hadislerle İslam)"),
  ],
  'isha': [
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Yatsı ve Gece", title: "Yatsı Namazının Müjdesi", text: "Yatsı namazını cemaatle kılan kimse, gecenin yarısını ibadet ve namazla ihya etmiş gibi ecir kazanır.", source: "Müslim, Mesâcid, 260 (Diyanet İşleri Başkanlığı Hadislerle İslam)"),
    DailyQuote(category: "Diyanet · Gece İbadeti & Vitir Bereketi", title: "Günü İbadetle Mühürlemek", text: "Günü yatsı ve vitir namazıyla tamamlamak, kabir gecesini aydınlatmanın ve huzurlu bir uykunun en yüce vesilesidir.", source: "Diyanet Hadislerle İslam"),
    DailyQuote(category: "Diyanet Meali · Âyet-i Kerime & Gece Secdesi", title: "Gece Vakti Huşû", text: "Gecenin bir kısmında da O'na secde et ve geceleyin O'nu uzun uzun tesbih et.", source: "İnsan Sûresi, 26. Âyet (Diyanet Meali)", arabic: "وَمِنَ اللَّيْلِ فَاسْجُدْ لَهُ وَسَبِّحْهُ لَيْلًا طَوِيلًا"),
    DailyQuote(category: "Diyanet · Yatsı Duası ve Tevekkül", title: "Geceye Giriş Duası", text: "Allah'ım! Günün beş vaktini huzurunda tamamlamayı nasip eyledin, hamdolsun. Uykumuzu ibadet, uyanışımızı şükür ve afiyet kıl.", source: "Diyanet Manevi Niyaz"),
    DailyQuote(category: "Diyanet · Hadis-i Şerif & Vitir Namazı", title: "Vitir Namazının Önemi", text: "Şüphesiz Allah tektir (vitr), teki sever. Ey Kur'an ehli! Siz de vitir namazını kılınız.", source: "Tirmizî, Vitir, 2; Ebû Dâvûd, Vitir, 1"),
  ],
};
