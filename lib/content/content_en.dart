// Dini içeriklerin İngilizcesi (Diyanet Türkçe metninden çeviri; kullanıcı onayıyla, 9 Kasım 2026).
// Anahtar: uygulamadaki Türkçe metin. Bulunamayan metin Türkçe gösterilir.
import '../lang.dart';

/// Dini içeriği seçilen dilde verir.
String tc(String tr) => Lang.isEn ? (contentEn[tr] ?? tr) : tr;

const contentEn = <String, String>{
  "Günün Ayeti · Diyanet Meali":
      "Verse of the Day · Diyanet Translation",
  "Günün Hadis-i Şerifi · Diyanet":
      "Hadith of the Day · Diyanet",
  "Günün Duası · Manevi Niyaz":
      "Dua of the Day · Supplication",
  "Bugünün Manevi Hatırlatması":
      "Today's Spiritual Reminder",
  "Günün Özlü Sözü · Hikmet":
      "Saying of the Day · Wisdom",
  "Namazın Önemi":
      "The Importance of Prayer",
  "Şüphesiz namaz, mü’minler üzerine belirli vakitlerde farz kılınmıştır.":
      "Indeed, prayer has been made obligatory upon the believers at fixed times.",
  "Nisâ Sûresi, 103. Âyet (Diyanet İşleri Başkanlığı Meali)":
      "Surah an-Nisa, 4:103 (translated from the Diyanet Turkish meal)",
  "Huşû ve Kurtuluş":
      "Humility and Salvation",
  "Müminler gerçekten kurtuluşa ermişlerdir; onlar ki, namazlarında derin bir saygı ve huşû içindedirler.":
      "The believers have truly attained salvation: those who are humble and full of deep reverence in their prayers.",
  "Mü'minûn Sûresi, 1-2. Âyetler (Diyanet İşleri Başkanlığı Meali)":
      "Surah al-Mu'minun, 23:1-2 (translated from the Diyanet Turkish meal)",
  "Sabır ve Namazla Yardım":
      "Seeking Help Through Patience and Prayer",
  "Sabır ve namaz ile Allah'tan yardım isteyin. Şüphesiz o, huşû duyanlardan başkasına pek ağır gelir.":
      "Seek help from Allah through patience and prayer. Indeed, it is very hard except for those who are humble.",
  "Bakara Sûresi, 45. Âyet (Diyanet İşleri Başkanlığı Meali)":
      "Surah al-Baqarah, 2:45 (translated from the Diyanet Turkish meal)",
  "Kötülükten Alıkoyan Namaz":
      "Prayer That Keeps Away From Evil",
  "Şüphesiz namaz, insanı hayasızlıktan ve her türlü kötülükten alıkoyar.":
      "Indeed, prayer keeps a person away from indecency and every kind of evil.",
  "Ankebût Sûresi, 45. Âyet (Diyanet İşleri Başkanlığı Meali)":
      "Surah al-Ankabut, 29:45 (translated from the Diyanet Turkish meal)",
  "Namaz Dinin Direğidir":
      "Prayer Is the Pillar of the Religion",
  "Namaz dinin direğidir. Kim onu dosdoğru kılarsa dinini ikame etmiş olur; kim de onu terk ederse dinini yıkmış olur.":
      "Prayer is the pillar of the religion. Whoever performs it properly has upheld their religion; whoever abandons it has torn down their religion.",
  "Beyhakî, Şu'abü'l-Îmân (Diyanet Hadislerle İslam)":
      "Bayhaqi, Shu'ab al-Iman (Diyanet, Islam Through Hadiths)",
  "Cemaatle Namazın Fazileti":
      "The Virtue of Praying in Congregation",
  "Cemaatle kılınan namaz, tek başına kılınan namazdan yirmi yedi derece daha faziletlidir.":
      "Prayer in congregation is twenty-seven degrees more virtuous than prayer performed alone.",
  "Buhârî, Ezân, 30; Müslim, Mesâcid, 249":
      "Bukhari, Adhan, 30; Muslim, Masajid, 249",
  "Kulun Rabbine En Yakın Olduğu An":
      "When the Servant Is Closest to His Lord",
  "Kulun Rabbine en yakın olduğu an, secde anıdır. Öyleyse secdede çokça dua ediniz.":
      "The closest a servant is to his Lord is while in prostration. So make much supplication in prostration.",
  "Müslim, Salât, 215 (Diyanet İşleri Başkanlığı)":
      "Muslim, Salat, 215 (Diyanet)",
  "Günahları Arındıran Beş Vakit Namaz":
      "The Five Prayers That Cleanse Sins",
  "Birinizin kapısı önünden bir nehir aksa ve o kimse nehirde her gün beş kere yıkansa üzerinde hiç kir kalır mı? İşte beş vakit namaz da böyledir; Allah onunla günahları siler.":
      "If a river flowed by the door of one of you and he bathed in it five times every day, would any dirt remain on him? The five daily prayers are just like this; Allah wipes away sins through them.",
  "Buhârî, Mevâkît, 6; Müslim, Mesâcid, 283":
      "Bukhari, Mawaqit, 6; Muslim, Masajid, 283",
  "Kıyamette İlk Hesaba Çekilecek Amel":
      "The First Deed to Be Judged on the Day of Judgment",
  "Kıyamet gününde kulun ilk hesaba çekileceği amel namazdır. Eğer namazı düzgün çıkarsa kurtulur ve kazanır.":
      "The first deed a servant will be held accountable for on the Day of Judgment is prayer. If his prayer is sound, he will be saved and succeed.",
  "Tirmizî, Salât, 188 (Diyanet Hadislerle İslam)":
      "Tirmidhi, Salat, 188 (Diyanet, Islam Through Hadiths)",
  "İbadette Süreklilik Duası":
      "Dua for Steadfastness in Worship",
  "Ey Rabbim! Beni ve neslimi namazı dosdoğru ve devamlı kılanlardan eyle. Ey Rabbimiz, dualarımızı kabul buyur!":
      "My Lord! Make me and my descendants among those who establish prayer properly and steadfastly. Our Lord, accept our prayers!",
  "İbrâhim Sûresi, 40. Âyet Meali / Manevi Dua":
      "Meaning of Surah Ibrahim, 14:40 / Supplication",
  "Gönül Huzuru ve Doğruluk":
      "Peace of Heart and Uprightness",
  "Ey kalpleri halden hale çeviren Allah'ım! Kalbimizi rızana, ibadetine ve dinine sabit kıl. Bizi namazla huzur bulanlardan eyle.":
      "O Allah, Turner of hearts! Keep our hearts firm upon Your pleasure, Your worship and Your religion. Make us among those who find peace in prayer.",
  "Tirmizî, De'avât, 120 (Manevi Niyaz)":
      "Tirmidhi, Da'awat, 120 (Supplication)",
  "Tövbe ve Kaza Azmi":
      "Repentance and Resolve to Make Up Prayers",
  "Allah'ım! Geçmişte kaçırdığımız, kusurlu kıldığımız namazlarımızı bağışla. Kaza borçlarımızı şevkle ve ihlasla tamamlamayı bizlere kolaylaştır.":
      "O Allah! Forgive the prayers we missed or performed imperfectly in the past. Make it easy for us to make up our missed prayers with enthusiasm and sincerity.",
  "Manevi Dua ve İltica":
      "Supplication and Refuge",
  "Rıza ve Cennet Duası":
      "Dua for Contentment and Paradise",
  "Rabbena âtina fi'd-dünya haseneten ve fi'l-âhireti haseneten ve kınâ azâbe'n-nâr. Rabbimiz! Bize dünyada da iyilik ver, ahirette de iyilik ver ve bizi cehennem azabından koru.":
      "Rabbana atina fi'd-dunya hasanatan wa fi'l-akhirati hasanatan wa qina 'adhaba'n-nar. Our Lord! Give us good in this world and good in the Hereafter, and protect us from the punishment of the Fire.",
  "Bakara Sûresi, 201. Âyet":
      "Surah al-Baqarah, 2:201",
  "Namaz Vakti Bir Fırsattır":
      "Prayer Time Is an Opportunity",
  "Her ezan, dünyanın telaşından sıyrılıp Yaratıcının huzuruna çıkmak için sana sunulan eşsiz bir randevudur. Bugün vakitlerini erteleme.":
      "Every call to prayer is a unique appointment offered to you to step away from the rush of the world and stand before the Creator. Don't postpone your prayers today.",
  "Aile ile Namaz Manevi Hatırlatma":
      "Aile ile Namaz Spiritual Reminder",
  "Birlikte Daha Güçlüyüz":
      "We Are Stronger Together",
  "Aile fertlerinin 'Namazını kıldın mı?' teşviki, cennet yolunda birbirine uzatılan en samimi eldir. Aileni teşvik etmeyi unutma!":
      "A family member asking \"Have you prayed?\" is the most sincere hand extended to one another on the path to Paradise. Don't forget to encourage your family!",
  "Kaza Borcu Dağ Değildir":
      "Missed Prayers Are Not a Mountain",
  "Kılınan her bir kaza namazı, ruhun üzerindeki bir yükü hafifletir. Küçük adımların istikrarı, büyük engelleri aşmanın en kutlu yoludur.":
      "Every missed prayer you make up lightens a burden on the soul. Steady small steps are the most blessed way to overcome big obstacles.",
  "Secdenin Kıymeti":
      "The Value of Prostration",
  "Secde, yere fısıldayıp göklerin ötesinden işitildiğin en yakın ve en samimi makamdır.":
      "Prostration is the closest and most sincere station, where you whisper to the earth and are heard beyond the heavens.",
  "Gönül Dünyasından Hikmet Damlaları":
      "Drops of Wisdom from the Heart",
  "Vaktin Bereketi":
      "The Blessing of Time",
  "Zamanın efendisi olmak istiyorsan, vaktini namazla tanzim et; çünkü namaz ömrün nizamıdır.":
      "If you want to be the master of your time, order your day by prayer; for prayer is the order of life.",
  "İslami Tefekkür ve Hikmet":
      "Islamic Reflection and Wisdom",
  "Vakit Namazı Tebriki":
      "Prayer Congratulations",
  "Tebrik":
      "Congrats",
  "Allah kabul etsin, kıldığın namazlar kalbine nur, ömrüne huzur ve bereket olsun kardeşim.":
      "May Allah accept it; may your prayers be light for your heart and peace and blessing for your life, my dear.",
  "Samimi Kabul Duası":
      "Sincere Dua for Acceptance",
  "Dua":
      "Dua",
  "Rabbim kıldığın namazları, ettiğin duaları dergâh-ı izzetinde en güzel şekilde makbul eylesin.":
      "May my Lord accept your prayers and supplications in His exalted presence in the most beautiful way.",
  "İstikrar ve Gayret Takdiri":
      "Appreciation for Consistency and Effort",
  "İstikrar":
      "Consistency",
  "Namaz dinin direğidir. Birlikte hayırda yarışarak istikrarımızı koruduğumuz için Elhamdülillah!":
      "Prayer is the pillar of the religion. Alhamdulillah that we keep our consistency by competing together in good deeds!",
  "Hayırlı ve Huzurlu Gün":
      "A Blessed and Peaceful Day",
  "Rabbim sana ve ailene afiyet, kalbine inşirah, hanene bereket ihsan eylesin.":
      "May my Lord grant you and your family well-being, ease to your heart and blessing to your home.",
  "Kaza Namazı Teşviki":
      "Encouragement for Kaza Prayers",
  "Kaza":
      "Kaza",
  "Kaza namazlarını eritmeye devam; Rabbim azmini, gayretini ve sevabını kat kat artırsın.":
      "Keep making up your missed prayers; may my Lord multiply your resolve, your effort and your reward.",
  "Günün Tamamlanma Şükrü":
      "Gratitude for a Completed Day",
  "Günün farzlarını tamamlayarak huzurla geceye kavuşturan Yüce Allah'a hamdolsun.":
      "Praise be to Allah the Exalted, who let us complete the day's obligatory prayers and reach the night in peace.",
  "Kim önemsemeyerek üç cumayı terk ederse, Allah onun kalbini mühürler.":
      "Whoever neglects three Friday prayers out of indifference, Allah seals his heart.",
  "Ebû Dâvûd, Salât 210 · Tirmizî, Cum'a 7 · Nesâî, Cum'a 2":
      "Abu Dawud, Salat 210 · Tirmidhi, Jumu'ah 7 · Nasa'i, Jumu'ah 2",
  "İnsanlar ya cumaları terk etmekten vazgeçerler ya da Allah onların kalplerini mühürler, sonra gafillerden olurlar.":
      "People will either stop abandoning the Friday prayers, or Allah will seal their hearts and then they will be among the heedless.",
  "Müslim, Cum'a 40":
      "Muslim, Jumu'ah 40",
  "Beş vakit namaz ve cumadan cumaya kılınan namaz, büyük günahlardan kaçınıldıkça aralarındaki günahlara kefarettir.":
      "The five daily prayers and from one Friday prayer to the next are an expiation for the sins between them, as long as major sins are avoided.",
  "Müslim, Tahâret 14":
      "Muslim, Taharah 14",
  "Diyanet · Hadis-i Şerif & Sabah Niyazı":
      "Diyanet · Hadith & Morning Supplication",
  "Sabah Namazının Fazileti":
      "The Virtue of the Fajr Prayer",
  "Kim sabah namazını kılarsa, o kimse Allah'ın güvencesi ve himayesi altındadır.":
      "Whoever prays the Fajr prayer is under the security and protection of Allah.",
  "Müslim, Mesâcid, 262 (Diyanet Hadislerle İslam)":
      "Muslim, Masajid, 262 (Diyanet, Islam Through Hadiths)",
  "Diyanet · Hadis-i Şerif & Sabah Bereketi":
      "Diyanet · Hadith & Morning Blessing",
  "Dünyadan Hayırlı İki Rekât":
      "Two Rak'ahs Better Than the World",
  "Sabah namazının iki rekât sünneti, dünyadan ve dünyadaki her şeyden daha hayırlıdır.":
      "The two sunnah rak'ahs of Fajr are better than the world and everything in it.",
  "Müslim, Müsâfirîn, 96 (Diyanet İşleri Başkanlığı)":
      "Muslim, Musafirin, 96 (Diyanet)",
  "Diyanet Meali · Âyet-i Kerime & Sabah":
      "Diyanet Translation · Verse & Morning",
  "Şahitli Sabah Namazı":
      "The Witnessed Fajr Prayer",
  "Gündüzün güneş dönüp batmaya meylettiği andan gecenin karanlığına kadar namaz kıl; bir de sabah namazını. Çünkü sabah namazı meleklerin şahit olduğu bir namazdır.":
      "Establish prayer from the decline of the sun until the darkness of the night, and also the Fajr prayer. For the Fajr prayer is witnessed by the angels.",
  "İsrâ Sûresi, 78. Âyet (Diyanet Meali)":
      "Surah al-Isra, 17:78 (translated from the Diyanet Turkish meal)",
  "Diyanet · Sabah Duası ve İltica":
      "Diyanet · Morning Dua and Refuge",
  "Sabahın Nuru ve Afiyeti":
      "The Light and Well-being of the Morning",
  "Allah'ım! Sabahın bereketini, hayrını, nurunu ve hidayetini Sen'den niyaz ederiz. Bizi ve ailemizi sabah namazının nurlu iklimiyle bereketlendir.":
      "O Allah! We ask You for the blessing, goodness, light and guidance of this morning. Bless us and our family with the radiant atmosphere of the Fajr prayer.",
  "Ebû Dâvûd, Edeb, 101 & Diyanet Niyaz":
      "Abu Dawud, Adab, 101 & Diyanet supplication",
  "Diyanet · Hadis-i Şerif & Meleklerin Şahitliği":
      "Diyanet · Hadith & The Witness of the Angels",
  "Meleklerin Buluşma Vakti":
      "When the Angels Meet",
  "Gece ve gündüz melekleri sabah namazında toplanırlar. Sabah namazı ibadetin ve günün en bereketli anahtarıdır.":
      "The angels of the night and the day gather at the Fajr prayer. The Fajr prayer is the most blessed key to worship and to the day.",
  "Buhârî, Mevâkît, 16 (Diyanet Hadislerle İslam)":
      "Bukhari, Mawaqit, 16 (Diyanet, Islam Through Hadiths)",
  "Diyanet · Manevi Niyaz & Seher Vakti":
      "Diyanet · Supplication & Pre-dawn",
  "Seherde Huzura Durmak":
      "Standing Before Allah at Pre-dawn",
  "Ey Rabbim! Seher vaktinde uyanıp huzuruna yöneldik. Bizi gaflet uykusundan uyandır, kalbimizi namazla aydınlat, dualarımızı kabul eyle.":
      "My Lord! We woke at pre-dawn and turned to You. Awaken us from the sleep of heedlessness, illuminate our hearts with prayer, and accept our supplications.",
  "Diyanet Manevi Dua ve İltica":
      "Diyanet Supplication and Refuge",
  "Diyanet · Cuma Sûresi & Cuma Namazı Vakti 🕌":
      "Diyanet · Surah al-Jumu'ah & Friday Prayer Time 🕌",
  "Hayırlı Cumalar · Cuma Namazı Vakti":
      "Jumu'ah Mubarak · Friday Prayer Time",
  "Ey iman edenler! Cuma günü namaza çağrıldığınızda Allah'ı anmaya koşun ve alışverişi bırakın. Eğer bilirseniz bu sizin için daha hayırlıdır.":
      "O you who believe! When the call to prayer is made on Friday, hasten to the remembrance of Allah and leave off trade. That is better for you, if only you knew.",
  "Cuma Sûresi, 9. Âyet (Diyanet İşleri Başkanlığı)":
      "Surah al-Jumu'ah, 62:9 (translated from the Diyanet Turkish meal)",
  "Diyanet · Hadis-i Şerif & Cuma Müjdesi":
      "Diyanet · Hadith & Good News of Friday",
  "Haftanın En Hayırlı Günü":
      "The Best Day of the Week",
  "Üzerine güneşin doğduğu en hayırlı gün Cuma günüdür. O günde öyle mübarek bir icabet saati vardır ki, Müslüman kul o anda dua ederse Allah duasını kabul buyurur.":
      "The best day on which the sun rises is Friday. On that day there is a blessed hour in which, if a Muslim servant supplicates, Allah answers his prayer.",
  "Müslim, Cum'a, 18 (Diyanet Hadislerle İslam)":
      "Muslim, Jumu'ah, 18 (Diyanet, Islam Through Hadiths)",
  "Diyanet · Hadis-i Şerif & Cuma Namazı Fazileti":
      "Diyanet · Hadith & The Virtue of the Friday Prayer",
  "Cuma Namazı ve Bağışlanma":
      "The Friday Prayer and Forgiveness",
  "Cuma namazına güzelce hazırlanıp huşû ile camiye giden kimsenin iki cuma arasındaki kusurları bağışlanır.":
      "Whoever prepares well for the Friday prayer and goes to the mosque with humility, his faults between the two Fridays are forgiven.",
  "Buhârî, Cum'a, 6; Müslim, Cum'a, 27":
      "Bukhari, Jumu'ah, 6; Muslim, Jumu'ah, 27",
  "Diyanet · Hadis-i Şerif & Peygamberimize Salavat":
      "Diyanet · Hadith & Salawat Upon the Prophet",
  "Cuma Salavatı ve Selam":
      "Friday Salawat and Greetings",
  "Cuma günü bana çokça salavat getiriniz; çünkü sizin salavatlarınız bana arz olunur. Allahümme salli alâ seyyidinâ Muhammedin ve alâ âli seyyidinâ Muhammed.":
      "Send abundant salawat upon me on Friday, for your salawat are presented to me. Allahumma salli 'ala sayyidina Muhammadin wa 'ala ali sayyidina Muhammad.",
  "Ebû Dâvûd, Salât, 201 (Diyanet İşleri Başkanlığı)":
      "Abu Dawud, Salat, 201 (Diyanet)",
  "Diyanet · Cuma Niyazı ve Rahmet":
      "Diyanet · Friday Supplication and Mercy",
  "Cuma Bereketi ve Aile Duası":
      "Friday Blessing and a Dua for the Family",
  "Rabbimiz! Bu mübarek Cuma gününde hürmetine ailemizi koru, dualarımızı ve tevbelerimizi makbul eyle, hanelerimize huzur ve bereket ihsan buyur.":
      "Our Lord! For the sake of this blessed Friday, protect our family, accept our supplications and repentance, and grant peace and blessing to our homes.",
  "Diyanet Cuma Duası":
      "Diyanet Friday Dua",
  "Diyanet · Hadis-i Şerif & Öğle Vakti":
      "Diyanet · Hadith & Dhuhr Time",
  "Gök Kapılarının Açıldığı An":
      "When the Gates of Heaven Open",
  "Öğle vakti, sema kapılarının açıldığı ve salih amellerin Allah Teâlâ'ya yükseldiği mübarek bir vakittir.":
      "Dhuhr time is a blessed time when the gates of heaven open and righteous deeds rise to Allah the Exalted.",
  "Tirmizî, Vitir, 15 (Diyanet İşleri Başkanlığı)":
      "Tirmidhi, Witr, 15 (Diyanet)",
  "Diyanet · Hadis-i Şerif & Günün Telaşı":
      "Diyanet · Hadith & The Rush of the Day",
  "Dünya Meşgalesinde Tevekkül":
      "Trust in Allah Amid Worldly Busyness",
  "Günün ortasındaki dünya telaşından sıyrılıp Rabbin huzuruna durmak, kalbin yorgunluğunu dindirir ve ömrü bereketlendirir.":
      "Stepping away from the midday rush of the world to stand before your Lord soothes the weariness of the heart and blesses your life.",
  "Diyanet Hadislerle İslam":
      "Diyanet, Islam Through Hadiths",
  "Diyanet Meali · Âyet-i Kerime & Öğle":
      "Diyanet Translation · Verse & Dhuhr",
  "Namaz Vakitli Bir Farzdır":
      "Prayer Is an Obligation at Fixed Times",
  "Şüphesiz namaz, mü’minler üzerine belirli vakitlerde farz kılınmıştır. Vaktinde kılınan namaz Allah katında en sevimli ameldir.":
      "Indeed, prayer has been made obligatory upon the believers at fixed times. Prayer performed on time is the deed most beloved to Allah.",
  "Nisâ Sûresi, 103. Âyet (Diyanet Meali)":
      "Surah an-Nisa, 4:103 (translated from the Diyanet Turkish meal)",
  "Diyanet · Öğle Niyazı ve Dua":
      "Diyanet · Dhuhr Supplication and Dua",
  "Günün İkramı ve Şükür":
      "The Day's Gifts and Gratitude",
  "Allah'ım! Günün yarısına ulaştık, bize lütfettiğin nimetlerin şükrünü eda edebilmeyi ve huzurunda samimiyetle secdeye varmayı nasip eyle.":
      "O Allah! We have reached the middle of the day; grant us the ability to give thanks for the blessings You bestowed and to prostrate sincerely before You.",
  "Diyanet Manevi İltica":
      "Diyanet Supplication",
  "Diyanet · Hadis-i Şerif & Öğle Sünneti":
      "Diyanet · Hadith & The Dhuhr Sunnah",
  "Öğle Namazının Fazileti":
      "The Virtue of the Dhuhr Prayer",
  "Öğle namazından önce kılınan dört rekât sünnet, sema kapılarının aralandığı kıymetli bir ibadettir.":
      "The four rak'ahs of sunnah before Dhuhr are a precious act of worship at the time the gates of heaven open.",
  "Tirmizî, Salât, 192 (Diyanet Hadislerle İslam)":
      "Tirmidhi, Salat, 192 (Diyanet, Islam Through Hadiths)",
  "Diyanet Meali · Âyet-i Kerime & İkindi":
      "Diyanet Translation · Verse & Asr",
  "Orta Namaza Dikkat Edin":
      "Guard the Middle Prayer",
  "Namazlara ve orta namaza (ikindi namazına) devam edin; gönülden boyun eğerek Allah'ın huzurunda durun.":
      "Be steadfast in the prayers and the middle prayer (the Asr prayer); stand before Allah in humble devotion.",
  "Bakara Sûresi, 238. Âyet (Diyanet İşleri Başkanlığı Meali)":
      "Surah al-Baqarah, 2:238 (translated from the Diyanet Turkish meal)",
  "Diyanet · Hadis-i Şerif & İkindi Müjdesi":
      "Diyanet · Hadith & Good News of Asr",
  "Cennet Müjdesi":
      "Good News of Paradise",
  "Kim sabah ve ikindi namazlarını aksatmadan huşû ile kılarsa cennete girer.":
      "Whoever prays the Fajr and Asr prayers with humility, without neglecting them, will enter Paradise.",
  "Buhârî, Mevâkît, 17; Müslim, Mesâcid, 215":
      "Bukhari, Mawaqit, 17; Muslim, Masajid, 215",
  "Diyanet · Hadis-i Şerif & İkindi Vaktinin Kıymeti":
      "Diyanet · Hadith & The Value of Asr Time",
  "Meleklerin Hüsn-ü Şahitliği":
      "The Good Testimony of the Angels",
  "İkindi namazını vaktinde kılan kimse, o vaktin meleklerinin Rablerine sunacağı güzel şahitliğe nail olur.":
      "Whoever prays Asr on time receives the good testimony that the angels of that time present to their Lord.",
  "Buhârî, Ezân, 31 (Diyanet Hadislerle İslam)":
      "Bukhari, Adhan, 31 (Diyanet, Islam Through Hadiths)",
  "Diyanet · İkindi Duası ve İltica":
      "Diyanet · Asr Dua and Refuge",
  "Günün Hitamında İstiğfar":
      "Seeking Forgiveness as the Day Ends",
  "Rabbimiz! Gün batımına doğru ilerlerken huzurundayız; günahlarımızı bağışla, kalan ömrümüzü ve amellerimizi rızanla taçlandır.":
      "Our Lord! As the day moves toward sunset we stand before You; forgive our sins and crown the rest of our lives and our deeds with Your pleasure.",
  "Diyanet Manevi Niyaz":
      "Diyanet Supplication",
  "Diyanet · Hikmet ve İbadet & İkindi":
      "Diyanet · Wisdom and Worship & Asr",
  "Vaktin Kıymetini Bilmek":
      "Knowing the Value of Time",
  "Asr vaktinde ikindi namazı, zamanın hızla akıp gittiğini hatırlatan ve kulun Rabbine sadakatini tazeleyen mukaddes bir kalkandır.":
      "The Asr prayer is a sacred shield that reminds us how quickly time passes and renews the servant's loyalty to his Lord.",
  "Diyanet Hadislerle İslam Tefekkürü":
      "Reflections from Diyanet, Islam Through Hadiths",
  "Diyanet · Hadis-i Şerif & Akşam Niyazı":
      "Diyanet · Hadith & Evening Supplication",
  "Dua ve İltica Vakti":
      "A Time for Dua and Refuge",
  "Akşam vakti girdiğinde dualarınıza sarılın; günün yorgunluğunu huzur ve şükür secdesiyle taçlandırın.":
      "When the evening comes, hold on to your supplications; crown the weariness of the day with a prostration of peace and gratitude.",
  "Ebû Dâvûd, Salât, 9 (Diyanet İşleri Başkanlığı)":
      "Abu Dawud, Salat, 9 (Diyanet)",
  "Diyanet · Hadis-i Şerif & Akşam Ezanı Duası":
      "Diyanet · Hadith & Dua at the Maghrib Adhan",
  "Akşam Ezanı İlticası":
      "Refuge at the Maghrib Adhan",
  "Akşam ezanı okunurken: 'Allah'ım! Bu Senin gecenin gelişi, gündüzünün çekilişi ve kullarının davet sesleridir. Beni ve sevdiklerimi bağışla' diye dua ediniz.":
      "While the Maghrib adhan is being called, supplicate: 'O Allah! This is the coming of Your night, the departure of Your day and the voices of those calling to You. Forgive me and my loved ones.'",
  "Tirmizî, De'avât, 85 (Diyanet İşleri Başkanlığı)":
      "Tirmidhi, Da'awat, 85 (Diyanet)",
  "Diyanet Meali · Âyet-i Kerime & Akşam":
      "Diyanet Translation · Verse & Maghrib",
  "İyilikler Kötülükleri Giderir":
      "Good Deeds Remove Bad Deeds",
  "Gündüzün iki tarafında ve gecenin gündüze yakın vakitlerinde namaz kıl. Çünkü iyilikler kötülükleri giderir.":
      "Establish prayer at the two ends of the day and in the hours of the night close to the day. Indeed, good deeds remove bad deeds.",
  "Hûd Sûresi, 114. Âyet (Diyanet Meali)":
      "Surah Hud, 11:114 (translated from the Diyanet Turkish meal)",
  "Diyanet · Akşam Duası ve İstiğfar":
      "Diyanet · Evening Dua and Seeking Forgiveness",
  "Günün Şükrü ve Huzur":
      "Gratitude for the Day and Peace",
  "Allah'ım! Akşama erdik, mülk de Sana ait olarak akşama erdi. Bizi bu gecenin şerrinden koru, hayrını ve affını üzerimize yağdır.":
      "O Allah! We have reached the evening, and the dominion has reached the evening belonging to You. Protect us from the evil of this night and shower its good and Your forgiveness upon us.",
  "Müslim, Zikir, 75 & Diyanet Niyaz":
      "Muslim, Dhikr, 75 & Diyanet supplication",
  "Diyanet · Hadis-i Şerif & Akşam Namazı":
      "Diyanet · Hadith & The Maghrib Prayer",
  "Akşam Namazının Bereketli Ecri":
      "The Blessed Reward of the Maghrib Prayer",
  "Akşam namazından sonra yapılan samimi tevbe ve dualar, gün boyunca işlenen küçük kusurlara kefaret olur.":
      "Sincere repentance and supplications after the Maghrib prayer become an expiation for the small faults committed during the day.",
  "Tirmizî, De'avât, 108 (Diyanet Hadislerle İslam)":
      "Tirmidhi, Da'awat, 108 (Diyanet, Islam Through Hadiths)",
  "Diyanet · Hadis-i Şerif & Yatsı ve Gece":
      "Diyanet · Hadith & Isha and the Night",
  "Yatsı Namazının Müjdesi":
      "Good News of the Isha Prayer",
  "Yatsı namazını cemaatle kılan kimse, gecenin yarısını ibadet ve namazla ihya etmiş gibi ecir kazanır.":
      "Whoever prays Isha in congregation earns the reward as if he had spent half the night in worship and prayer.",
  "Müslim, Mesâcid, 260 (Diyanet İşleri Başkanlığı Hadislerle İslam)":
      "Muslim, Masajid, 260 (Diyanet, Islam Through Hadiths)",
  "Diyanet · Gece İbadeti & Vitir Bereketi":
      "Diyanet · Night Worship & The Blessing of Witr",
  "Günü İbadetle Mühürlemek":
      "Sealing the Day with Worship",
  "Günü yatsı ve vitir namazıyla tamamlamak, kabir gecesini aydınlatmanın ve huzurlu bir uykunun en yüce vesilesidir.":
      "Completing the day with the Isha and Witr prayers is the noblest means of illuminating the night of the grave and of a peaceful sleep.",
  "Diyanet Meali · Âyet-i Kerime & Gece Secdesi":
      "Diyanet Translation · Verse & Night Prostration",
  "Gece Vakti Huşû":
      "Humility at Night",
  "Gecenin bir kısmında da O'na secde et ve geceleyin O'nu uzun uzun tesbih et.":
      "And prostrate to Him during part of the night, and glorify Him through the long night.",
  "İnsan Sûresi, 26. Âyet (Diyanet Meali)":
      "Surah al-Insan, 76:26 (translated from the Diyanet Turkish meal)",
  "Diyanet · Yatsı Duası ve Tevekkül":
      "Diyanet · Isha Dua and Trust in Allah",
  "Geceye Giriş Duası":
      "Dua for Entering the Night",
  "Allah'ım! Günün beş vaktini huzurunda tamamlamayı nasip eyledin, hamdolsun. Uykumuzu ibadet, uyanışımızı şükür ve afiyet kıl.":
      "O Allah! You granted us to complete the five prayers of the day before You; praise be to You. Make our sleep worship and our waking gratitude and well-being.",
  "Diyanet · Hadis-i Şerif & Vitir Namazı":
      "Diyanet · Hadith & The Witr Prayer",
  "Vitir Namazının Önemi":
      "The Importance of the Witr Prayer",
  "Şüphesiz Allah tektir (vitr), teki sever. Ey Kur'an ehli! Siz de vitir namazını kılınız.":
      "Indeed, Allah is One (witr) and loves what is odd. O people of the Qur'an, pray the Witr prayer.",
  "Tirmizî, Vitir, 2; Ebû Dâvûd, Vitir, 1":
      "Tirmidhi, Witr, 2; Abu Dawud, Witr, 1",
};
