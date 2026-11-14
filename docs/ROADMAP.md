# Gez roadmap

Agreed with the owner in session 2 (12 November 2026). Each phase builds on
the ones before it. Work top to bottom; inside a phase, follow the order
given. When a phase is finished, tick it here and update `docs/HANDOFF.md`.

Rules that apply to every phase: keep `GezCore` pure Swift and
deterministic (multiplayer depends on it), test every system, check visuals
via the `ci-snapshots` branch, and ask the owner multiple-choice questions
(recommended option first) when a design or history choice comes up.

## Build names

Decided by the owner on 13 November 2026 (session 6, on claude.ai).
- **Alpha** (the build once all 20 phases are done): **"Kayser"**, after
  *Kayser-i Rûm* ("Caesar of Rome"), the title Mehmed II took in 1453.
- **Beta builds**: each iteration gets its own name; theme not chosen yet
  (ideas offered: years after 1453 such as Belgrade 1456, Granada 1492,
  Calicut 1498; market cities; rivers). Ask the owner when a beta comes.
- These are build names, not the store title. The game is still called Gez.

## Feature decisions (owner's picks)

| # | Feature | Decision |
|---|---|---|
| 1 | Interface art (fonts, parchment panels, icons) | **Last phase (Phase 20)**, EU-style gold frames, medallions, painted art (decided session 6) |
| 2 | Coats of arms | **Real 1453 arms/banners** from Wikimedia Commons (changed: generated ones were rejected) |
| 3 | 3D map (relief, tilting camera) | **After core gameplay** |
| 4 | Things on the map (cities, forts, ports, armies) | **2D icons first, 3D later** |
| 5 | Economy | **EU5-style goods and markets** |
| 6 | Trade | **Routes between markets** (Silk Road, spice routes, Hansa, Mediterranean) |
| 7 | Buildings | **Build time and cost** |
| 8 | Estates | **Tied to the pops** |
| 9 | Rulers | **Full CK-style characters** (courts, councils, relationships), **starting with the real people of 1453** |
| 10 | Government | **Laws + reforms** |
| 11 | Diplomacy | **Full** (alliances, marriages, guarantees, vassals, embargoes, opinions, coalitions) |
| 12 | War and peace | **EU-style casus belli, war score, peace treaties** |
| 13 | Armies | **Regiments by type and origin** (levies from pops, professionals, mercenaries, special units) |
| 14 | Logistics | **Supply limits, attrition, roads**; rivers and mountains slow movement |
| 15 | Battle look | **2D first, 3D later** |
| 16 | Battle controls | **Real-time with pause**, formations, touch and Pencil friendly |
| 17 | Sieges | **Map sieges plus playable assaults** in the battle view |
| 18 | Navies | **Fleets, sea zones, naval battles auto-resolved on the map**, blockades, transport |
| 19 | Religion | **Full system** (conversion, holy sites, heresies, Reformation, Safaviyya, Hussites) |
| 20 | Culture | **Assimilation and migration** |
| 21 | Plague and famine | **Spreading plague (trade routes, armies) and famine** |
| 22 | Rebellion | **Rebels from pops and estates** with real causes |
| 23 | Technology | **EU4-style tech levels** |
| 24 | Events | **Historical events with choices + country missions** |
| 25 | AI | **Setting in game setup: historical or free** |
| 26 | Saves | **Local saves only** (no iCloud) |
| 27 | Map size | **Split India first** (about 95 to about 250 provinces), then other thin areas if needed |
| 28 | Audio | **Sound effects and ambience only, no music or instruments** |
| 29 | Multiplayer | **Epic Online Services (EOS) with join codes** (changed session 6, replacing Game Center); own free server as backup. Host chooses per game what happens when someone fights a battle manually |
| 30 | Windows | **Decide later**; keep the simulation portable |
| + | Help | **Tooltips only** (no guided tutorial) |
| + | Chronicle | **History book, graphs and timelapse near the end** |

## Build order

### Phase 0: Foundation ✅ (session 1)
Calendar and speeds, pure-Swift simulation, 1,189 provinces, borders along
rivers and mountains, 247 countries with tribes and subjects, cultures,
religions and pops with classes, Metal map with real terrain. See
`docs/HANDOFF.md`.

### Phase 1: Finish the map ✅ (session 3)
Everything later attaches to provinces and sea zones, so their shape must
be final first. Done: India split (1,373 provinces total), 79 sea zones
with straits and coasts, real coats of arms, town/capital/fort/port
icons (SwiftUI overlay for now; move to Metal or 3D models in Phase 17).
1. **Split India** into about 250 provinces (new towns in
   `data/map/provinces/08_india.txt`, states regrouped, pops re-split,
   population check). Then review Persia, Anatolia, the Maghreb and
   Central Asia for oversized provinces.
2. **Sea zones**: water split into named zones (Aegean, Adriatic, Black
   Sea, Bay of Bengal...), with adjacency to coastal provinces and ports.
   Needed by navies, trade and plague.
3. **Coats of arms**: real arms, banners and tamgas as used c.1453, from
   Wikimedia Commons (credited), shown in panels and the top bar. Rules and
   workflow in HANDOFF "Heraldry workflow". Done: 200 real, 9 invented (owner
   asked), 57 plain banners where nothing is known.
4. **2D map icons**: towns that grow with development, forts by level,
   ports, capitals; drawn by the Metal renderer.

### Phase 2: Economy ✅ (session 4)
Owner's choices: ~60 goods (EU5-like), supply-and-demand prices, "you build,
pops work", ducats + loans + debasement, ~40 markets that can grow,
needs by class, building slots limited by size and terrain.
Done: steps 1–3 (goods, markets, needs, prices, taxes, satisfaction; Goods
and Markets map modes; market panel) and step 4 buildings (owner: levels
1–5, months-to-years build time, ducats + goods, all four kinds).
and step 5 (owner: named banking houses, default with penalties, debasement
once and ongoing, tax sliders by class).
1. **Goods**: each province produces goods from its terrain and pops
   (grain, wine, wool, cloth, iron, salt, fish, timber, spices, silk,
   horses...). Data file of goods and where they come from.
2. **Markets**: market centres (Venice, Bruges, Constantinople, Cairo,
   Tabriz, Samarkand, Delhi, Calicut...), each with supply, demand and
   prices; provinces belong to a market.
3. **Pop needs and income**: pops buy goods; taxes come from pops by
   class; burghers drive trade.
4. **Buildings** with build time and cost (workshops, markets, temples,
   docks, roads, forts, barracks); each changes production or capacity.
5. **Budget screen**: income, expenses, loans.

### Phase 3: Trade routes ✅ (session 4)
Owner's choices: player-drawn routes (plus the historical 1453 routes),
merchants + tolls, capacity per route/link, embargoes and closed markets.
Merchants move goods between markets along land and sea routes (Silk Road,
spice route through the Red Sea and the Gulf, Hanseatic Baltic,
Mediterranean). Control of routes earns money. Needs sea zones (Phase 1).

### Phase 4: Characters and dynasties (CK-style) ✅ (session 4)
Owner's choices: real rulers, heirs, spouses and key figures; invented
sibling heirs (and rulers) where history records no one; CK-style traits
and skills; court, council and marriages (plots later). Done: all of steps
1–5. Owner then asked for whole real families ("fully like CK3") and real
landed great vassals: done (session 5), with tax shares, inheritance,
grant/revoke, tax refusal and murder plots. Vassal revolts with armies
wait for Phase 6.
1. **Real 1453 people** as starting data: rulers, heirs, spouses, key
   nobles and generals (Mehmed II, Hunyadi, Skanderbeg, Ladislaus,
   Frederick III, Charles VII, Zara Yaqob, Jahan Shah, Abu Sa'id,
   Bahlul Lodi, Rana Kumbha...). Record uncertain facts in
   `HISTORY_NOTES.md` and ask the owner.
2. **Characters**: traits, skills, age, health, death; dynasties and
   houses; marriages and children.
3. **Courts and councils**: chancellor, marshal, steward and so on, with
   effects.
4. **Relationships**: opinion, friends and rivals, plots (simple at first).
5. **Succession**: laws per government; regencies, pretenders, personal
   unions forming and breaking (the Ladislaus union should end at his
   death in 1457 unless the player changes history).

### Phase 5: Government, laws and estates ✅ (session 5)
Owner's choices: EU5-style law areas; core + regional estates; power,
loyalty and privileges; a reform tree per government type. Done: all
three steps plus stability. Cossacks left out (they appear after 1453).
1. **Laws** with trade-offs (tax, conscription, tolerance, succession).
2. **Government reforms** over time.
3. **Estates tied to pops**: nobles, clergy, burghers plus regional
   estates (Janissaries, Cossacks, Rajputs, Mamluks); power from pop size
   and wealth; loyalty and privileges.

### Phase 6: Armies and logistics ✅ (session 6)
Owner's choices: three regiment origins tied to pops and markets (levies from pops, standing professionals from national manpower + market goods, mercenaries for gold); 5 core unit types + 10 historical 1453 regional units; 39 historical standing armies on the map on 30 May 1453 led by real commanders; daily movement by distance/terrain/rivers/roads/unit speed, province supply & attrition, and open revolts by disloyal great vassals.
1. **Regiments by type and origin**: infantry, cavalry, archers,
   handgunners, artillery; levies raised from pops (reducing them),
   professionals, mercenaries; special units. ✅
2. **Army movement** along province neighbours; river crossings and
   mountains slow armies; roads speed them. ✅
3. **Supply and attrition**: supply limit from province population and
   farmland; disease and starvation. ✅
4. **Basic AI** for raising and moving armies. AI grows with every phase
   from here on. ✅

### Phase 7: Diplomacy, war and peace ✅
Owner's choices:
- **Diplomacy**: Full 1453 treaties (alliances, guarantees, non-aggression pacts, military access, truces), opinion & trust (-100 to +100), diplomatic relation slots (scaled by Diplomacy skill & Chancellery), Aggressive Expansion & coalitions (at 50+ AE with 4+ outraged countries), plus starting historical 1453 alliances and truces.
- **Casus belli & wars**: Full CBs (Province Claim, Reconquest, Holy War, Subjugation/Tribute, Throne Claim from royal marriage, Coalition punitive war, or No-CB with -2 stability & high AE), ticking war score up to ±25% for holding the war goal, ally/subject call-ins based on trust/opinion/debt/truces, plus active 30 May 1453 wars (e.g., final phase of the Hundred Years' War in Gascony, Thirteen Years' War / Prussian Confederation tension).
- **War score & peace treaties**: War score (-100% to +100% from battles up to ±40%, province/capital occupation, and ±25% ticking war goal) + multi-demand peace treaties up to 100% cost (cede provinces, return cores, ducat indemnity, war reparations of 10% income for 10 years, make vassal/tributary, annul treaties, or release nations), scaling truce length (5–15 years) and AE by peace cost.
- **Auto-resolved battles & occupation**: Multi-day alternating Fire (artillery, handgunners, archers) and Shock (infantry, cavalry, elephants) phases using real regiment stats, commander Martial rolls (`GameRandom`), terrain/river crossing penalties, cavalry flanking, morale & discipline; levy casualties permanently reduce home-province peasant/tribal pops; shattered retreat; short takeover for unfortified enemy provinces.
1. **Diplomacy**: alliances, royal marriages (linked to characters),
   guarantees, vassals and tributaries (already in data), embargoes,
   opinion and trust, coalitions against aggressive expanders. ✅
2. **Casus belli and war goals**: claims, holy wars, succession claims,
   rebellion support. ✅
3. **War score** from battles, sieges and occupation; **peace treaties**
   (provinces, money, subjects, release of nations). ✅
4. **Auto-resolved battles** on the map using the same unit stats the
   battle view will use. ✅

### Phase 8: Sieges and the first playable game ✅ (session 6; play-test with the owner next)
Owner's choices:
- **Sieges & forts**: Fort levels 1–5 project Zone of Control into adjacent friendly provinces (blocking hostile movement past the fort until besieged); 1,000 garrison per level and at least 1,000 besiegers required per level; monthly siege roll (-7 to +7+) modified by artillery/Bombards, commander Martial, naval blockade status, and wall breaches (supplies holding, food/water shortage, defender desertion, disease outbreak, wall breach, surrender); once breached, the besieger can order a high-casualty Storm Assault.
- **Local save, load & autosave**: Versioned deterministic snapshots of all mutable `World` state (including `GameRandom` seed state), stored locally in Application Support/Documents with manual named saves, quick-save, and a **single-file autosave** (overwriting/deleting the old autosave each time) with player-selectable frequency: **Monthly, Every 3 Months, Every 6 Months, Every Year, or Never**.
- **First playable milestone**: Full nation-picker & campaign loop (playable country selection on the map for any of the 266 countries + featured 1453 powers), tag-switching / New Game / Load Game menu, active alerts banner (at war, besieged provinces, disloyal estates/vassals, loans due, low stability, idle diplomats), and a 10-year headless balance test suite.
1. **Sieges on the map**: forts block movement and need sieges; time
   depends on fort level, artillery, supply and disease; starve or storm.
2. **Local save and load**, autosave.
3. **First playable milestone**: a complete game loop (economy, armies,
   war, peace, sieges) as any country. Play-test with the owner and fix
   balance before going on.

### Phase 9: Battle view (2D, real-time with pause)
Owner's choices:
- **Battlefield & deployment**: "Lead Battle in Person" vs "Auto-Resolve" modal when the player's army fights or storms a breached fort; 2D battlefield generates elevation contours, woods, hills, and river crossings from the province's real terrain and border data, with a pre-battle Deployment Phase in each side's deployment zone (skipped if ambushed during a river crossing).
- **Tactical controls & formations**: Real-time with pause & speed controls (0.5x/1x/2x), drag-box or tap selection, draw-path / drag-frontline orders (touch, Apple Pencil, mouse & keyboard), formations (Line, Column, Wedge, Square/Wagon-Laager, Skirmish), tactical stances (Hold, Advance, Charge, Volley/Hold Fire, Retreat), plus directional flanking/rear morale penalties, fatigue, and ammunition tracking.
- **Playable siege assaults & write-back**: Fort assaults render walls, towers, gates, and pre-existing artillery breaches from the map siege; attackers can bombard walls/gates with artillery, send infantry with scaling ladders or battering rams, or storm through breaches to capture the inner keep; exact regiment survivors, morale, breaches, and levy pop losses feed directly back into the campaign `World`.
1. "Fight or auto-resolve" choice when armies meet.
2. Battlefield from the real location's terrain (elevation, forest,
   river); deployment phase.
3. Real-time control with pause: select units, move, formations, charge,
   fire; morale, fatigue, flanking; touch, Pencil, mouse and keyboard.
4. **Playable siege assaults**: walls, gates, breaches, ladders.
5. Results feed back to the campaign map.

### Phase 10: Navies
Owner's choices:
- **Ships, docks & 1453 fleets**: 4 core ship classes (Cogs for transport, Galleys for inland-sea oar combat in Med/Black Sea/Baltic/Red Sea, Carracks as heavy ocean warships, Light Ships/Caravels/Dhows for trade protection & scouting) + regional ships (Venetian Great Galleys, Ottoman galleys, Indian Ocean dhows and ghurabs via tech); built in coastal provinces with Docks using `timber`, `naval_supplies`, `cloth`, and `cannons`, drawing Sailors from coastal peasant/burgher pops, plus historical 30 May 1453 starting fleets.
- **Naval operations**: Multi-day auto-resolved naval battles (cannon fire & boarding phases, galley bonus in inland seas, admiral Martial rolls, ship capture chance), port blockades (removing the -2 coastal fort siege penalty, cutting sea trade capacity, and adding war score), strait blocking (hostile fleets block enemy armies from crossing a strait unless they control both shores), and amphibious army transport (1 Cog/transport per 1,000 troops, with amphibious landing penalties in combat).
Fleets (galleys, cogs, carracks, dhows), naval battles auto-resolved on the
map, blockades of ports, transporting armies across sea zones.

### Phase 11: Religion and culture in motion
Owner's choices:
- **Religion**: Pop-level missionary conversion over time (scaled by Clergy loyalty, temples, and Religious Tolerance laws; blocked by Dhimmi/Millet or Hussite Compacts privileges); Holy Sites (Rome, Constantinople, Jerusalem, Mecca, Medina, Najaf, Karbala, Varanasi, Bodh Gaya, Axum, etc.) granting prestige & clergy loyalty; dynamic historical movements (Hussite Utraquist/Taborite question in 1453 Bohemia, Sufi orders & Safaviyya Qizilbash rise in Ardabil/Persia, and the Protestant & Reformed Reformation from ~1517 with Centres of Reformation).
- **Culture**: Primary Culture plus Accepted Culture slots (scaled by government rank & laws; non-accepted cultures suffer tax, manpower, and satisfaction penalties); gradual pop assimilation when same-religion, well-satisfied, and adjacent to same-culture provinces; dynamic pop migration along neighbor provinces and trade routes driven by war devastation, religious persecution, famine, and plague.
1. **Religion**: conversion of pops over time, missionaries, holy sites,
   tolerance, religious unrest, heresies; the Reformation (1517), the
   Safaviyya's rise, the Hussite question; Sufi orders gaining influence.
2. **Culture**: assimilation, accepted cultures, migration after war,
   famine and plague.

### Phase 12: Plague, famine and rebellion
Owner's choices:
- **Plague, famine & earthquakes**: Plagues (bubonic plague, typhus/camp fever, smallpox) ignite in crowded hubs or besieged camps and spread along active Trade Routes, Ports, and marching Armies, killing pops by class with local immunity recovery and Port Quarantine / Cordon responses; Famine triggers when staple food supply falls below pop need (from bad harvest rolls, war devastation, siege looting, or peasant levies kept raised during harvest); occasional Earthquakes strike historical fault zones (Anatolia, Aegean, Italy, Persia, Lisbon, Himalayas), damaging buildings and forts.
- **Rebellions**: Cause-driven rebel factions tied to real pops & estates (Peasant Rebels, Religious Zealots, Cultural Separatists, Noble/Estate Rebels, Dynasty Pretenders); at 100% progress they raise a real army on the map from those pops and enforce their political demands if victorious.
1. **Plague** spreading along trade routes and with armies; **famine**
   after bad harvests and war; occasional earthquakes.
2. **Unrest and rebels** from real causes (taxes, religion, culture,
   estates, succession, pretenders).

### Phase 13: Technology
Owner's choices: 3 EU4-style tech tracks (Administrative, Diplomatic, Military, levels 1–20 starting at level 3–4 in 1453); monthly research from Ruler skills + Council advisors + Paper/Books supply in the capital market + University/Library buildings; unlocks advanced units, higher fort & building tiers, trade range, and administrative efficiency; -5% per level Neighbor Bonus plus historical Institutions (Renaissance, Printing Press, Global Trade, Manufactories) spreading along trade routes and literate burgher pops.
EU4-style tech levels (administrative, diplomatic, military), unlocking
units, buildings, forts and ship types; neighbours ahead make it cheaper.

### Phase 14: Events and missions
Owner's choices: Condition-triggered historical events with multi-choice outcomes (firing when historical conditions & date windows are met) plus dedicated branching Mission Trees for major 1453 powers (Ottomans, France, England, Castile, Portugal, Austria, Hungary, Venice, Mamluks, Aq Qoyunlu/Persia, Timurids/Mughals, Delhi/Vijayanagara) and regional mission trees for all other nations.
Historical events with choices (Fall of Granada, Columbus, Vasco da Gama
at Calicut, Babur, the Reformation, the Safavid rise...) and mission trees
for major countries.

### Phase 15: AI behaviour setting
Owner's choices: Weighted AI goal & mission evaluation (never hard-scripted railroading): in **Historical AI** mode, AI countries prioritize their historical mission tree targets, traditional rivals/allies, and historically plausible event choices while still checking real army strength, treasury, and truces; in **Free AI** mode, AI countries evaluate all opportunities purely by strategic value, border weakness, trade wealth, and ruler personality traits.
Game-setup option: **historical** AI (pursues real goals, like the Ottomans
in the Balkans or Castile at Granada) or **free** AI. Builds on the AI
grown since Phase 6.

### Phase 16: Sound effects and tooltips
Owner's choices: Strictly zero music or musical instruments: procedural/recorded non-musical sound effects and environmental ambience only (UI parchment/wood clicks, coin clinks, marching boots, hoofbeats, hammer/construction, siege cannon thuds, sword/musket battle sounds, and camera-zoomed ocean/wind/city ambience) plus rich math-breakdown tooltips everywhere (hover on Mac, long-press on iPad).
1. **Sound effects only**: interface clicks, map sounds (marching,
   building, sieges), battle sounds, ambience (sea, city, wind). **No
   music or instruments.**
2. **Tooltips everywhere** (hover on Mac, long-press on iPad). No guided
   tutorial.

### Phase 17: Going 3D
Owner's choices: Vertex-displaced 3D Metal terrain mesh from the heightmap with smooth camera pitch tilt as you zoom in (reusing existing map mode shaders); 3D instanced Metal models on the map for growing towns, tiered forts, ports/ships, and marching army figures in regional styles (European, Islamic, Indian, East Asian, Steppe); and upgrading the Phase 9 battle view to 3D instanced soldier formations, walls, and siege engines using CC0 low-poly meshes.
1. **3D map**: terrain mesh from the elevation data, camera tilts as you
   zoom in; the current shader shading is reused.
2. **3D cities, forts, ports and army figures** replacing the 2D icons.
3. **3D battle view** upgrade (free CC0 soldier models such as
   Quaternius), keeping the battle rules from Phase 9.

### Phase 18: Chronicle and stats
Owner's choices: Full regnal Chronicle book recording wars, major battles, peace treaties, laws, plagues, and dynastic events in period prose; a Ledger & Graphs screen comparing nations over time (population, GDP/income, army & navy size, technology, religion/culture pie charts); and an interactive Map Timelapse player recording yearly province-owner & religion snapshots from 1453 onward.
History book of the game (wars, rulers, borders), graphs, and a
world-history timelapse.

### Phase 19: Multiplayer (on hold for now, per the owner)
Owner's choice (session 6): **Epic Online Services (EOS)**, not Game
Center. Game Center only works for App Store apps and needs Apple's
$99/year account; EOS is free, works with the free website download, and
covers Mac, iPad and a possible Windows version.
1. **EOS peer-to-peer**: players sign in anonymously per device (EOS
   Connect device ID, no Epic account); EOS does NAT punching and falls
   back to Epic's relays. Lockstep sync of player orders (the simulation
   is deterministic).
2. **Join codes** instead of friend lists: the host opens an EOS lobby,
   Gez shows a short code (like `KZ7-QM4`), friends type it to join.
3. Host picks per game what happens when a player fights a battle
   manually (pause with a time limit, auto-resolve only, or watch).
4. Owner's one-time setup: free Epic developer account, a "Gez" product,
   download the EOS SDK, store the product IDs as GitHub secrets (never in
   chat). The website needs a short privacy policy mentioning Epic.
5. **Backups**: if Epic's terms change, our own small relay on a free host
   (Cloudflare Durable Objects first; Oracle or Google Cloud free VMs);
   free local Wi-Fi play between nearby devices as a bonus.
Note: the iPad version still needs Apple's paid account to install at all.

### Phase 20: Interface and art (the EU look)
Decided by the owner in session 6: the very last phase, once everything
else is done. Until then, keep panels functional and don't style them.
Reference: the owner's concept canvas on claude.ai ("Gez interface
concept": today vs. after, main screen and court panel). Its art pieces
were made in code (height maps lit as metal, leather and enamel) by a
script saved in the claude.ai Project as `claude/ui-art-concept.py`; move
it to `tools/uiart/` when this phase starts. Never use Paradox art.
1. **Style kit**: tooled leather top bar between gold mouldings, gold
   frames with rope moulding and corner rosettes (nine-slice), parchment
   panels, red cloth title banners, bevelled gold buttons, domed gold
   medallions with engraved icons for every button and indicator, wax
   seals for traits, period fonts (Cinzel titles, EB Garamond text; both
   free to ship).
2. **Painted goods and building icons** (Gemini, an art pack or an
   artist; owner to decide then).
3. **Portraits**: painted ones for the real people of 1453, plus a
   layered generator (face, beard, headwear, clothing by culture, age,
   rank) for everyone else.
4. **Shields by culture**: heater shields for Latin Europe, round for the
   Islamic world, other shapes for India and the steppe, all in gold frames.
5. **Alerts row**: glowing medallions under the top bar (unhappy vassal,
   stability can be raised, building finished...).
6. **Rich tooltips**: framed parchment cards that break down every number.
7. **Motion**: panels unroll like scrolls, medallions press in, hover glow.
8. **Map polish**: curved country names; a painted-chart look when zoomed
   out (drawn mountains, sea creatures, blank parchment for unknown lands);
   forests, towns and animated water where Phase 17 has not already done it.
9. **Main menu and loading screen** with a painted Constantinople, 1453,
   and paintings for the event pop-ups from Phase 14.

After Phase 20: the **alpha build "Kayser"** (see "Build names" above).

### Backlog (decide later)
- **Windows** version: decide later; the simulation stays portable.
- Playable naval battles, iCloud saves, guided tutorial, music: not wanted
  for now.
