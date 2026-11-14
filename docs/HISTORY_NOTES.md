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

Real people are in `data/characters/people_*.txt` (rulers in
`people_1453.txt`; whole families, dead parents and great vassals by region
in `people_2_west.txt` … `people_5_south.txt`). Only people history records
are added; invented people fill gaps only. Which provinces each great vassal
holds is simplified to the map's provinces (e.g. Hunyadi: Temesvár, Szörény,
Szeben). These facts are uncertain (mostly birth years, some 1453
office-holders and lordships). Countries with no
recorded ruler got an invented ruler and an invented sibling heir (owner's
rule); they are marked "invented" in the game.

| Country | Person | What is uncertain |
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
| BAD | Catherine of Lorraine | birth year? |
| BAD | Markus of Baden | birth year? |
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
| ENG | Owen Tudor | second husband of Catherine of Valois; birth year? |
| ENG | Edmund Beaufort | birth year? |
| ENG | John Beaufort | birth year? |
| ENG | Margaret Beauchamp of Bletso | birth year? |
| ENG | Thomas Neville | birth year? |
| ENG | Eleanor Neville | birth year? |
| ENG | Ralph Percy | birth year? |
| ENG | Anne Neville, Duchess of Buckingham | birth year? |
| ENG | Humphrey Stafford, Earl of Stafford | birth year? |
| ENG | Margaret Beaufort, Countess of Devon | birth year? |
| SCO | Isabella Stewart | widow of Francis I of Brittany; birth year? |
| SCO | Joan Stewart | deaf; birth year? |
| SCO | Annabella Stewart | birth year? |
| SCO | Archibald Douglas, Earl of Moray | brother of the 9th Earl; birth year? |
| SCO | Alexander Gordon, Earl of Huntly | birth year? |
| SCO | William Crichton | Lord Chancellor; birth year? |
| FRA | Charles II of Albret | birth year? |
| BUR | John of Burgundy, Count of Nevers | cousin; birth year? |
| BUR | Cornelius of Burgundy | killed 1452? |
| POR | Afonso, Count of Ourém | birth year? |
| POR | John of Coimbra | husband of Charlotte of Cyprus later; birth year? |
| CAS | Juan Ponce de León | Count of Arcos; birth year? |
| CAS | Beltrán de la Cueva | Henry's favourite; birth year? |
| ARA | Alfonso of Aragon | later Duke of Villahermosa; birth year? |
| ARA | Juan of Aragon | later archbishop of Zaragoza; birth year? |
| ARA | Joan Ramon Folc of Cardona | Count of Cardona; birth year? |
| NAP | Maria of Aragon | wife of Lionello d'Este (widowed); birth year? |
| NAP | Eleanor of Aragon | birth year? |
| NAP | Marino Marzano | Prince of Rossano; birth year? |
| NAP | Tristan of Clermont | birth year? |
| MLO | Tristano Sforza | birth year? |
| MLO | Sforza Secondo | birth year? |
| MLO | Elisabetta Sforza | birth year? |
| FLO | Ginevra degli Alessandri | birth year? |
| FLO | Carlo de' Medici | birth year? |
| SAV | Aimon of Savoy | birth year? |
| HUN | Michael Szilágyi | brother of Elizabeth; birth year? |
| HUN | János Rozgonyi | voivode of Transylvania?; birth year? |
| HUN | Dénes Szécsi | archbishop of Esztergom; birth year? |
| BOH | Johana of Rožmitál | birth year? |
| BOH | Bolko V the Hussite | Duke of Opole-Głogówek; birth year? |
| BRA | Margaret of Brandenburg | birth year? |
| GEL | Margaret of Egmond | birth year? |
| GEL | Catherine of Egmond | birth year? |
| DAN | Maurice of Oldenburg | birth year? |
| SWE | Sten Sture | nephew of Charles VIII?; later regent |
| SWE | Erik Axelsson Tott | birth year? |
| POL | Jan Tęczyński | castellan; birth year? |
| POL | Piotr Odrowąż | voivode of Ruthenia?; birth year? |
| LIT | Semen Olelkovich | birth year? |
| LIT | Mikhail Olelkovich | birth year? |
| LIT | Jonas Goštautas | birth year? |
| MAZ | Barbara Olelkovna | birth year? |
| MAZ | Konrad III the Red | birth year? |
| MAZ | Kazimierz III | birth year? |
| MAZ | Bolesław V | birth year? |
| MOS | Ivan Andreyevich of Mozhaysk | flees to Lithuania 1454; birth year? |
| MOS | Mikhail Andreyevich of Vereya | birth year? |
| MOS | Vasily Yaroslavich of Serpukhov | jailed by Vasily II in 1456; birth year? |
| NOV | Sophia of Zaozerye | birth year? |
| NOV | Ivan Dmitrievich | birth year? |
| NOV | Isaak Boretsky | posadnik; birth year? |
| NOV | Marfa Boretskaya | Marfa the Posadnitsa; birth year? |
| TUR | Hüma Hatun | origin disputed? |
| TUR | Fatma Hatun | daughter of Murad II, wife of Zağanos?; birth year? |
| TUR | Şehzade Hatun | birth year? |
| TUR | Evrenosoğlu Ali Bey | march lord; seat at Yenice-i Vardar?; birth year? |
| TUR | Mihaloğlu Ali Bey | raider lord; birth year? |
| TUR | Ömer Bey | birth year? |
| TUR | İshak Bey | march lord of Skopje; birth year? |
| TUR | Isa-Beg Ishaković | founder of Sarajevo; birth year? |
| SER | Jelena Branković | later Queen of Bosnia; birth year? |
| SER | Milica Branković | birth year? |
| SER | Irina Branković | birth year? |
| SER | Vuk Grgurević | "Vuk the Fiery Dragon"; birth year? |
| SER | Mihailo Anđelović | brother of Mahmud Pasha; birth year? |
| BOS | Vojača | first wife of Stephen Thomas, set aside 1445; birth year? |
| BOS | Catherine Tomašević | birth year? |
| HER | Jelena Balšić | dies late 1453?; birth year? |
| HER | Katarina Hercegović | birth year? |
| ALB | Voisava | origin disputed; death date unknown? |
| ALB | Mamica Kastrioti | sister of Skanderbeg; birth year? |
| WAL | Radu the Fair | hostage at the Ottoman court; birth year? |
| WAL | Vlad the Monk | birth year? |
| MOL | Oltea | mother of Stephen; birth year? |
| KAR | Sultan Hatun | daughter of Mehmed I; birth year? |
| KAR | İshak Bey | eldest son, mother not Sultan Hatun?; birth year? |
| DUL | Şah Budak | birth year? |
| DUL | Şehsuvar Bey | birth year? |
| TRE | Helena Kantakouzene | birth year? |
| TRE | Basil Megas Komnenos | birth year? |
| TRE | Manuel Megas Komnenos | birth year? |
| AKK | Seljuk Shah Begum | birth year? |
| AKK | Ughurlu Muhammad | birth year? |
| QAR | Bigim Khatun | birth year? |
| GEO | Nestan-Darejan | birth year? |
| GEO | Alexander | birth year? |
| GEO | Liparit I Dadiani | prince of Mingrelia; birth year? |
| GEO | Mamia Gurieli | prince of Guria; dates uncertain? |
| MAM | Khawand Zaynab | wife of Inal; birth year? |
| ETH | Seyon Mogesa | mother of Baeda Maryam; birth year? |
| DEL | Daria Khan Lodi | governor of Sambhal?; birth year? |
| DEL | Ahmad Khan Mewati | Khanzada chief of Mewat?; birth year? |
| DEL | Qutb Khan Lodi | cousin of Bahlul; birth year? |
| JNP | Bibi Raji | birth year? |
| GUJ | Bibi Mughli | mother of Fath Khan; birth year? |
| MEW | Ramabai | birth year? |
| MAR | Satal | birth year? |
| MAR | Suja | birth year? |

## Government in 1453 (Phase 5)

Laws, reforms and stability on 30 May 1453 are set in
`data/government/laws_1453.txt`. Most countries get defaults by government
and religion (feudal crown, customary taxes, levies; Christian realms
"state faith only", Muslim and Hindu realms "protected minorities"). These
are judgment calls, change them freely:

| Country | Choice | Why / doubt |
|---|---|---|
| TUR | Centralised crown, royal tax collectors, standing army (Janissaries), serfdom | Timar land is close to serfdom only loosely? |
| MAM | Standing army, tax collectors; Mamluk emirs 35% power | |
| FRA | Standing army, tax collectors, royal domain | Compagnies d'ordonnance 1445, taille permanente |
| ENG, CAS, ARA, POL, FRA | "Diet of the estates" reform | Parliament, Cortes, Sejm, Estates-General |
| HUN, BOH | "Elective crown" reform | Both elected kings in practice |
| VEN | Sound money, free markets, chartered towns, Great Council, State arsenal | |
| LIT, MOS | Serfdom | Serfdom tightens later (15th–16th c.)? |
| ETH | Serfdom | gult land tenure is not quite serfdom? |
| KSH, VIJ | Open tolerance | Zain-ul-Abidin's and Vijayanagara's tolerance |
| Stability | TUR +2, FRA +2, VEN +2, KSH +2; MOE, MOL, NAV −2; WAL, MOR −1; ENG, CAS, TRE, HUN, BOH, MOS 0; others +1 | Morea: Albanian revolt of 1453; Moldavia and Navarre: civil wars |
| Cossacks | Not an estate | They appear decades after 1453 |

## Standing armies on 30 May 1453 (Phase 6)

Starting standing armies live in `data/military/armies_1453.txt` (built into
`military1453.json` by `tools/military/milgen.py`). Seasonal feudal and
tribal levies stay unraised in their home provinces at game start; only
standing professional forces, household guards, and active campaign hosts of
May 1453 start on the map:

| Country | Army & Location | Commander | Notes / judgment calls |
|---|---|---|---|
| TUR | Imperial Army of Constantinople (`Konstantiniyye`), Army of Rumelia (`Edirne`) | Mehmed II, Zağanos Pasha | Day after the fall of Constantinople (29 May 1453); Janissaries, sipahi cavalry, azab infantry, handgunners and Urban's bombards |
| FRA | Compagnies d'Ordonnance (`Paris`), Army of Normandy (`Rouen`) | Jean de Dunois, Jean Bureau | Charles VII's standing *Compagnies d'Ordonnance* (1445) and Bureau's artillery train preparing for the final Castillon campaign |
| ENG | Army of Aquitaine (`Bordeaux`), Royal Retinue (`London`) | John Talbot, Edmund Beaufort | Talbot's Gascon expedition (fought at Castillon in July 1453) and the royal household retinue |
| MAM | Royal Mamluks of Cairo (`Cairo`), Army of Damascus (`Aleppo`) | Sultan Inal, Khushqadam | Purchased *julban* and veteran *qarani* Mamluk household cavalry |
| HUN, BOH, JIS | Royal Banderium (`Buda`), Landfrieden Host (`Prague`), Black Brethren (`Kassa`) | John Hunyadi, George of Poděbrady, Jan Jiskra | Hunyadi's banderium, Hussite *vozová hradba* war wagons, and Jiskra's Czech mercenaries in Upper Hungary |
| ALB | League of Lezhë (`Kruje`) | Skanderbeg | Standing mountain retinue of the League of Lezhë |
| QAR, AKK, TIM, HRT | Tabriz, Diyarbakir, Samarkand, Herat | Jahan Shah, Uzun Hasan, Abu Sa'id Mirza, Abul-Qasim Babur | Turkmen and Timurid standing household *nöker* horse-archer hosts |
| DEL, VIJ, ORI, MEW, BAH, BNG, GUJ | Delhi, Vijayanagara, Cuttack, Chittor, Bidar, Gaur, Ahmedabad | Bahlul Lodi, Saluva Narasimha, Kapilendra Deva, Rana Kumbha, Humayun Shah, Nasiruddin Mahmud, Qutb-ud-din Ahmad | Standing sultanate, Rajput and Gajapati hosts with war elephants (`pil-khana`) |
| ETH | Chewa Regiments (`Debre Berhan`) | Zara Yaqob | Zara Yaqob's royal *chewa* military colonies |
