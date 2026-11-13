# 1453 map: judgment calls and open questions

The start date is **30 May 1453**. These are the places where the history is
unclear, sources disagree, or the map simplifies things. Each item says what
the map currently does. Change the data in `data/map/` (or tell Claude) to
decide differently.

## Simplifications (on purpose)

1. **Holy Roman Empire.** Hundreds of small counties, abbeys, imperial
   knights and free cities are merged into about 45 states. Examples:
   Anhalt is part of Magdeburg; Osnabrück and Paderborn are part of Münster;
   Fulda is part of Hesse; Konstanz is grouped with Ulm; Basel, St Gallen
   and Valais are counted as Swiss.
2. **French great vassals.** Anjou, Maine, Bourbon, Orléans, Alençon,
   Armagnac and Albret are inside France. Only Brittany, Burgundy, Provence
   and Foix-Béarn are separate.
3. **Ireland.** Gaelic and Anglo-Irish lordships are reduced to nine
   (Kildare, Leinster, Ormond, Desmond, Thomond, Clanricarde, Tyrconnell,
   Tyrone, plus English Dublin, Meath, Waterford and Ulster towns).
4. **Rajput, Gond and Himalayan states.** Only the larger ones are
   separate. Smaller chiefdoms (Sirohi, Dungarpur, Jammu, Jumla and others)
   are unclaimed or merged.
5. **Kurdish emirates and Arab tribes.** Only Bitlis is a separate Kurdish
   state; Hakkari is unclaimed. Najd, Qatar and the Hejaz interior are
   unclaimed tribal land.
6. **Steppe.** The central Kazakh steppe, the Wild Fields of Ukraine and
   Bashkiria are unclaimed land or loosely held by hordes.
7. **Religion is set per state, not per town.** Mixed areas (Bosnia, Albania,
   Transylvania, Lebanon, Egypt's Copts, Armenia) show the majority or the
   ruler's religion.

8. **Borders follow geography, not surveyed frontiers.** Province shapes stop
   at 73 rivers, 20 mountain ridges and three hand-drawn frontier lines (the
   Granada frontier, the 1422 Melno line between Prussia and Lithuania, and
   the Prussia–Mazovia frontier). Elsewhere a border lies between
   neighbouring towns. River and ridge lines are hand-drawn and accurate to
   roughly 10–30 km.
9. **1453 coastlines.** The Zuiderzee and the enlarged Dollart are open
   water; the Aral Sea is at its full size. Smaller changes (deltas, lagoons)
   are not modelled.

## Population and religion estimates

- **All population mixes are estimates.** No censuses exist for 1453. Shares
  for cities and frontier zones are educated guesses from later Ottoman
  registers, travellers and modern scholarship.
- **Region totals** (`data/map/population_1453.txt`) are middle estimates;
  sources disagree by 20–40%. India is about 100 million, Europe (with
  Russia) about 65 million.
- **India was split into about 280 provinces** (session 3, owner's choice),
  adding small states the first map left out: Kangra, Chamba, Kullu, Doti,
  Palpa, Lamjung, the Kirat tribes, Dungarpur, Sirohi, Jalore, Karauli,
  Rajpipla, Deogarh, Mallabhum, Chandradwip, the Bhuyan chiefs of Assam,
  the Chutia kingdom, the Khasi chiefs and Jaintia. Their 1453 status is
  approximate; most were local dynasties paying tribute to bigger neighbours.
- **City provinces include their countryside.** Konstantiniyye shows about
  300,000 people, though the city itself had perhaps 50,000 after the siege.
- **Persia is shown as mostly Sunni (Shafi'i)** with Twelver pockets, as it
  was before the Safavids.
- **Bohemia's ruler is counted as Hussite** because the kingdom was run by
  Utraquists under George of Poděbrady, though King Ladislaus was Catholic.
- **Bosnia** is split between the Bosnian Church, Catholics and Orthodox
  Vlachs; King Stephen Thomas had converted to Catholicism.

## Decisions made by the owner (settled; don't change without asking)

Blank land: **tribal countries** (government type `tribal`) now hold land
that had no single ruler in 1453: Baloch Tribes, Pashtun Tribes, Hazara
Tribes, Najdi Tribes, Shammar, Asir Tribes, Yam Tribes (Najran),
Cyrenaican Bedouin, Fezzan, Sous Confederation, Zenata Tribes, Ja'alin
Arabs, Beja Tribes, Somali Clans, Hakkari Emirate, Mordvins, Komi, Sami,
Oirats, Turkmen Tribes, Khokhars, Dard Tribes, Jat Tribes, Guanche Tribes,
Kabarda, Alania, Vainakh Tribes (Circassia itself is now tribal). The Wild
Fields went to Crimea (Zaporizhia, Azov Steppe) and the Great Horde
(Kharkiv, Voronezh); Samara to the Nogai; the central steppe to the Uzbeks,
Oirats and Moghulistan. No province is unclaimed any more.

| # | Question | Decision |
|---|---|---|
| 1 | Bordeaux and Guyenne | **England** (lost after Castillon, July 1453) |
| 2 | Mandore | **Rao Jodha (Marwar)** |
| 3 | Timurids | **Two states; Balkh and Kunduz to Samarkand** (Abu Sa'id); Kabul to Herat; Khwarazm to Samarkand |
| 4 | Otrar | **Timurids (Samarkand)** |
| 5 | Qara Qoyunlu | **Hold all of it** (Iraq, Azerbaijan, Isfahan, Fars, Kerman, Yazd) |
| 6 | Aq Qoyunlu | **As drawn** (Diyarbakır, Mardin, Urfa, Harput, Erzincan, Bayburt, Erzurum) |
| 7 | Kayseri and Kırşehir | **Kayseri to Dulkadir**, Kırşehir stays Karaman |
| 8 | Niš and Vrhbosna | **Niš Serbian**, Vrhbosna Ottoman |
| 9 | Upper Hungary | **Jiskra's Brotherhood** as a Hussite state (Kassa, Bártfa, Besztercebánya) |
| 10 | Kilia | **Hungary** (its garrison) |
| 11 | Ochakiv coast | **Crimea** |
| 12 | Lower Lusatia | **Brandenburg** |
| 13 | Velikiye Luki | **Lithuania** |
| 14 | Marrakesh | **Hintata Emirate, a vassal of Morocco** (Marrakesh, Mogador) |
| 15 | Algiers | **Tlemcen** |
| 16 | Cyrenaica and Fezzan | **Tribal countries** |
| 17 | Yemen | **Zaydi imams hold the highlands** (Sanaa, Sadah, Marib); **the Tahirid Sultanate holds the rest it held then** (Aden, Taizz, Zabid, Jizan); Najran (Yam) and Asir tribal |
| 18 | Al-Hasa, Qatif, Bahrain | **Jabrids hold Bahrain too** (and Qatar) |
| 19 | Dhofar | **Kathiri** |
| 20 | Dongola | **Dotawo**, a Christian Nubian kingdom |
| 21 | Ethiopian south | **Tributaries of Ethiopia**: Hadiya, Bali, Dawaro, Ifat, Ennarea, Damot |
| 22 | Somali coast | **As drawn** (Ajuran, separate Mogadishu) |
| 23 | Rajahmundry | **Orissa** |
| 24 | Goa | **Vijayanagara** |
| 25 | Chittagong | **Bengal** |
| 26 | Etawah, Kannauj, Kalpi | **Jaunpur** |
| 27 | Ranthambore | **Mewar** |
| 28 | Kaffa | **As drawn** (independent, folk religion) |
| 29 | North Caucasus | **Split into tribal states**: Circassia, Kabarda, Alania, Vainakh |
| 30 | Armenia | **Armenian Christian majority (about 70%)** |
| + | Ladislaus the Posthumous | **Personal union**: Austria and Bohemia under the King of Hungary |

Subject countries at the start are listed in `data/map/subjects.txt`
(personal unions, vassals, tributaries), including well-known ones the
owner didn't have to decide: Aragon–Naples and Denmark–Norway unions;
Ottoman vassal Serbia and tributaries Wallachia, Morea, Athens, Lesbos;
Mamluk vassals Mecca, Dulkadir, Ramadanids; Polish vassals Mazovia and
Moldavia; French vassals Brittany and Foix; Muscovite vassal Kasimov.

## Other notes

- **Constantinople** is Ottoman (taken 29 May). Galata/Pera surrendered
  within days and is merged into Konstantiniyye.
- **Genoese colonies:** Kaffa, Cembalo, Matrega, Chios (the Maona) and
  Famagusta are Genoese. Corsica went to the Bank of St George in 1453 and
  is shown as Genoa.
- **Kalmar Union:** Denmark and Norway share King Christian I but are
  separate countries; Sweden is under Charles VIII Knutsson.
- **Ladislaus the Posthumous** is King of Hungary and Bohemia and Duke of
  Austria at once. The map shows Hungary, Bohemia and Austria as separate
  countries. Inner Austria (Frederick III, the Emperor) and Tyrol are also
  separate. A personal-union mechanic can link them later.
- **Novgorod, Pskov and Vyatka** are independent republics; Yaroslavl, Tver
  and Ryazan are independent but close to Moscow.


## People of 1453 (Phase 4)

Real people are in `data/characters/people_1453.txt`. These facts are
uncertain (mostly birth years, some 1453 office-holders). Countries with no
recorded ruler got an invented ruler and an invented sibling heir (owner's
rule); they are marked "invented" in the game.

| Country | Person | Doubt |
|---|---|---|
| TUR | Gülbahar Hatun | origin disputed? |
| TUR | Sitti Şah Hatun | birth year? |
| TUR | Zağanos Pasha | birth year? |
| TUR | Turahan Bey | birth year? |
| TUR | İshak Pasha | birth year? |
| MOE | Catherine Zaccaria | birth year? |
| MOE | Theodora Asanina | birth year? |
| TRE | John IV Megas Komnenos | birth year? |
| TRE | Theodora Komnene | later wife of Uzun Hasan; birth year? |
| CYP | James the Bastard | illegitimate; birth year? |
| KNI | Jacques de Milly | birth year? |
| NAX | Giacomo II Crispo | died 1453; birth year? |
| LES | Dorino I Gattilusio | birth year? |
| LES | Domenico Gattilusio | birth year? |
| TOC | Leonardo III Tocco | birth year? |
| ATH | Francesco I Acciaioli | child duke, mother Chiara Zorzi regent? |
| ATH | Chiara Zorzi | regent? |
| ZET | Stefan Crnojević | birth year? |
| ZET | Ivan Crnojević | birth year? |
| ALB | Donika Arianiti | birth year? |
| ALB | Hamza Kastrioti | nephew; defected 1456; birth year? |
| ALB | Moisi Golemi | birth year? |
| ALB | Lekë Dukagjini | birth year? |
| HUN | Elizabeth Szilágyi | birth year? |
| HUN | Ladislaus Garai | palatine; birth year? |
| JIS | Jan Jiskra | birth year? |
| WAL | Vladislav II | birth year? |
| WAL | Vlad Dracula | in exile; birth year? |
| MOL | Alexăndrel | birth year? |
| MOL | Peter Aron | rival claimant; birth year? |
| MOL | Stephen of Moldavia | in exile; later Stephen the Great; birth year? |
| SAL | Sigismund of Volkersdorf | archbishop; birth year? |
| POM | Eric II of Pomerania | birth year? |
| UTR | Rudolf van Diepholt | bishop; birth year? |
| GEN | Pietro di Campofregoso | Doge; birth year? |
| GRA | Muhammad XI | 1453 rulers of Granada uncertain? |
| GRA | Sa'd of Granada | rival, king 1454; birth year? |
| ENG | Richard of York | heir presumptive? |
| TYR | Eoghan Ó Néill | birth year? |
| TYR | Énrí Ó Néill | birth year? |
| TMN | Toirdhealbhach Bóg Ó Briain | birth year? |
| DAN | Knud of Denmark | birth year? |
| MAZ | Bolesław IV of Warsaw | birth year? |
| TVE | Mikhail of Tver | birth date? |
| RYA | Ivan Fyodorovich | dies 1456; birth year? |
| KAS | Qasim Khan | birth year? |
| KAZ | Mahmud of Kazan | birth year? |
| CRI | Nur Devlet | birth year? |
| CRI | Meñli Giray | birth year? |
| GRH | Küchük Muhammad | birth year? |
| GRH | Mahmud of the Great Horde | birth year? |
| GRH | Akhmat Khan | birth year? |
| UZB | Shah Budaq | birth year? |
| MGH | Esen Buqa II | birth year? |
| AKK | Khalil Mirza | birth year? |
| AKK | Jahangir Mirza | elder brother, deposed? |
| QAR | Hasan Ali | birth year? |
| QAR | Pir Budaq | birth year? |
| KAR | İbrahim II of Karaman | birth year? |
| KAR | Pir Ahmed | birth year? |
| KAR | Kasım Bey | birth year? |
| CND | İsmail Bey | birth year? |
| DUL | Süleyman Bey | birth year? |
| DUL | Malik Arslan | birth year? |
| SHI | Khalilullah I | birth year? |
| SHI | Farrukh Yasar | birth year? |
| SAM | Kaikhosro Jaqeli | birth year? |
| MAM | Ahmad ibn Inal | Mamluk succession is not hereditary in practice? |
| ZAY | Al-Mutawakkil al-Mutahhar | imam; birth year? |
| MSH | Muhammad ibn Falah | founder; birth year? |
| MOR | Yahya al-Wattasi | vizier; birth year? |
| ETH | Eleni | birth year? |
| ADA | Muhammad ibn Badlay | birth year? |
| DEL | Barbak Shah | birth year? |
| JNP | Mahmud Shah Sharqi | birth year? |
| JNP | Muhammad Shah Sharqi | birth year? |
| JNP | Husain Shah Sharqi | birth year? |
| KSH | Adam Khan | birth year? |
| KSH | Haji Khan | birth year? |
| MUL | Rai Sahra Langah | birth year? |
| GUJ | Qutb-ud-din Ahmad Shah II | birth year? |
| MLW | Ghiyath Shah | birth year? |
| KHA | Miran Mubarak Khan | birth year? |
| BNG | Nasiruddin Mahmud Shah | birth year? |
| BNG | Rukunuddin Barbak Shah | birth year? |
| BAH | Ala-ud-din Ahmad Shah II | birth year? |
| BAH | Humayun Shah | birth year? |
| ORI | Kapilendra Deva | birth year? |
| ORI | Hamvira | birth year? |
| ORI | Purushottama Deva | birth year? |
| VIJ | Mallikarjuna Raya | birth year? |
| VIJ | Virupaksha Raya | cousin; birth year? |
| MEW | Rana Kumbha | birth year? |
| MEW | Udai Singh | birth year? |
| MEW | Raimal | birth year? |
| AHO | Susenphaa | birth year? |
| TPR | Dharma Manikya I | birth year? |
