# Florida Ride-Hailing Launch — Go-To-Market, Brand & Website Strategy

**Working product codename:** RideVela (internal only — *not* the public brand; see §6)
**Prepared:** August 2026 · **Audience:** Founder + future website-build team · **Status:** Master strategy doc

---

## How to read this document

This is the single source of truth for launching a new Florida ride-hailing brand and building its marketing website. Three labeling systems run through it. Respect all three.

**1. Product-reality tags** — every claim about what the app can *do* is tagged so nobody markets vapor:

- **✅ HAVE** — real, working code today (many vendor integrations are "real-when-keyed, mock-by-default" — production-shaped, not yet live-keyed).
- **🔧 BUILD-BEFORE-LAUNCH** — thin, mocked, or absent, and required (legally or operationally) before we can honestly claim it or, in some cases, launch at all.
- **🔮 FUTURE** — real but nuanced, or a later ambition. Read the nuance before quoting it.

> **The three hardest honesty rules, stated once, up front:**
> 1. **Insurance is absent in code and is LEGALLY MANDATORY under Florida TNC law (F.S. 627.748). It is a hard launch blocker. NEVER put an insurance claim on the website until it is real.** (🔧)
> 2. **The in-app "SOS/emergency" feature is an audit-log entry only** — no 911 dispatch, no emergency-contact notification, no trip-share delivery. **Do not market "SOS," "emergency button," or "we call 911."** (🔧)
> 3. **The in-app "price comparison" is our own internal fare *model*, self-disclaimed — not live Uber/Lyft quotes. Never present it as real competitor pricing.** (🔮)

**2. Priority ranking** — for recommendations:
- 🔴 **Critical** — launch-blocking or legally required. Do first.
- 🟡 **Important** — materially moves the outcome; schedule deliberately.
- 🟢 **Nice-to-have** — do when capacity allows.

**3. FACT vs. RECOMMENDATION** — sourced facts carry an inline `(source: URL)`. Where the research flagged something as ESTIMATE, unverified, or a data gap, that honesty is preserved here — do not "clean it up." Everything not sourced is analysis or recommendation and is labeled as such.

---

## 1. Executive Summary

**The opportunity.** Florida is the third-most-populous, most-tourism-dependent state in the U.S. — **143.3 million visitors in 2025** (a record; source: https://www.wctv.tv/2026/02/20/florida-tourism-breaks-records-with-1433-million-visitors-2025/), **~21.9 million cruise passengers** across PortMiami, Port Canaveral (now the *world's busiest* cruise port), and Port Everglades (all three set records in 2025; sources: https://www.royalcaribbeanblog.com/2025/12/02/port-canaveral-portmiami-set-yearly-records-cruise-passengers, https://www.seatrade-cruise.com/ports-destinations/port-everglades-confirms-2025-record-4-77m-cruise-moves), and ~170M+ annual airport passengers across MCO, MIA, FLL and TPA. Yet **no analyst has ever published a Florida-specific ride-hailing market size** (FACT / data gap — see §2). That absence is itself the wedge: the biggest, most mobility-hungry state in the country has no dedicated challenger telling a Florida story.

**The wedge.** We do not win by being "cheaper than Uber" — that is the one lane where Uber and Lyft's density and price-war-honed economics are hardest to beat, and every credible "anti-Uber" brand studied (Alto, Curb, Wingz, Empower, inDrive) *re-segments* rather than competing head-on (source: niche-competitor analysis, §3). We win on **trust + price-certainty + local-first execution**, anchored to real product capabilities we already have: **favorite-driver priority dispatch (✅), a surge engine with a hard admin ceiling (✅), cash-or-card payment (✅), and transparent, itemized driver pay (✅).**

**Recommended positioning (RECOMMENDATION).** *"The Florida ride that treats you fairly — pick a driver you trust, pay a price with no surprises, cash or card."* One thing a user should remember: **"No surge surprises. A driver you trust."**

**Recommended first launch city (RECOMMENDATION).** **Tampa.** It is the best proving ground — a balanced, growing 3.42M metro with real airport (TPA), cruise (Port Tampa Bay), business and local-commuter demand, but *far* less incumbent/challenger saturation than Miami (where inDrive is HQ'd, Empower is live, and Waymo launched robotaxis in Jan 2026) and *far* less surge chaos than Miami's nightlife market. Prove unit economics in Tampa, then attack Orlando (the $7-airport-fee grievance) and Miami (the biggest prize) in Phase 6. (Details and the Jacksonville alternative in §2.)

**The 5 biggest risks.**

| # | Risk | Why it's existential | Mitigation |
|---|---|---|---|
| 1 | **🔴 Insurance not in product** | Absent in code; **legally mandatory** under F.S. 627.748 (Period 3 = **$1M**). Launching without it is illegal and uninsurable. | Bind the post-7/1/2025 three-tier policy *before* any live ride or marketing claim (§14, §20). |
| 2 | **🔴 Airport permitting** | Every FL airport requires its *own* TNC permit + fee + geofence + trade dress; state law lets them (source: MIA OD 18-03, https://www.miami-airport.com/library/ODs/18-03%20Operating%20Policy%20for%20Transportation%20Network%20Company%20Permits.pdf). Airports are our highest-value segment. | Treat each airport as a separate GTM project; don't advertise airport service until permitted. |
| 3 | **🟡 Safety over-claim** | "SOS" is audit-log-only (🔧); doc-upload is a manual admin toggle (🔧); rider identity verification is absent (🔧). Over-claiming safety is both a trust and a legal-exposure risk. | Ship the "we can honestly say today" trust page (§14) and *build before you claim* the rest. |
| 4 | **🟡 Entrenched + emerging competition** | Uber ~71% U.S. share (source: https://www.zippia.com/advice/ridesharing-industry-statistics/); Waymo live in Miami since Jan 22 2026 (source: https://www.cnbc.com/2026/01/22/waymo-launches-robotaxi-service-in-miami-extending-us-lead.html); inDrive + Empower already in FL. | Launch where they're thin (Tampa/Jax), win on trust not price, move fast while Waymo is Miami-only. |
| 5 | **🟡 Growth engine not built** | The **referral program is absent** (🔧 — only generic promo codes exist), yet driver-referral is the single most realistic early-stage growth lever (source: growth research §16). | Build referral infra pre-launch; it is a 🔴 in the action plan. |

---

## 2. Florida Market Analysis

### Market size — with an honest data gap

**FACT (national/global).** Global ride-hailing was ~$47.6B in 2025 → ~$55.1B projected 2026 (~18.6% CAGR toward $181.5B by 2033) (source: https://www.grandviewresearch.com/industry-analysis/ride-hailing-services-market). The **U.S.** market was $23.43B in 2025 → $27.97B projected 2026 (source: https://www.marketdataforecast.com/market-reports/united-states-ride-hailing-market). Uber holds ~71% U.S. share vs. Lyft ~29% (source: https://www.zippia.com/advice/ridesharing-industry-statistics/).

**DATA GAP (preserve this honesty).** **No published state-level Florida ride-hailing market size, ridership, or YoY figure exists** — every industry report found is national or global only. Do not fabricate one.

**ESTIMATE (label it every time you use it).** Florida ≈ 6.7–6.8% of U.S. population; a naïve population-share proxy against the $23.43B U.S. figure implies a **~$1.5–1.6B Florida TAM (2025)** — but this is a back-of-envelope proxy, *not* a researched number, and Florida's outsized tourism/airport/cruise ridership means true demand is likely *higher* (source: florida-market brief). **The absence of published Florida sizing is itself a PR/SEO opportunity** — publish the first-ever Florida ride-hailing market narrative as content (§12, §17).

### Metros ranked as launch targets

| Metro | 2025 pop | Why attractive | Why hard |
|---|---|---|---|
| **Miami–Ft. Lauderdale–WPB** | 6,391,072 (source: https://statranker.org/population/u-s-metro-areas-by-population-2026-snapshot-based-on-2025-census-estimates/) | Highest-density tourist/nightlife/cruise/convention demand in the state | Deepest incumbent entrenchment; Waymo live since Jan 2026; inDrive HQ + Empower live; Miami-Dade **lost >10,000 residents 2024→2025** (source: https://www.islandernews.com/news/florida/miami-dade-growth-slows-as-census-shows-recent-population-dip/article_93cf5a2a-f4ec-4bed-b55c-c4fa19857392.html) — opportunity here is visitor-driven, not resident-driven |
| **Orlando–Kissimmee–Sanford** | 2,957,672 (source: https://news.orlando.org/blog/orlando-population-growth-again-among-highest-in-nation/) | Single largest tourism draw (Disney/Universal/OCCC — 2M+ convention attendees/yr, source: https://www.visitorlando.org/about/corporate-blog/post/how-citywide-events-impact-our-community/); strong population growth | **MCO's $7 rideshare pickup fee is the highest in the U.S.** — structurally taxes new-entrant economics from day one |
| **Tampa–St. Pete–Clearwater** | 3.42M (source: https://statranker.org/population/u-s-metro-areas-by-population-2026-snapshot-based-on-2025-census-estimates/) | Balanced local/business market, growing, less surge chaos than Miami, real airport + cruise demand | Smaller tourist volume than Orlando/Miami; TPA reportedly adding a **$6.50 pickup fee + $20 minimum** (source, unverified/conflicting — see §4) |
| **Jacksonville** | ~1.36M metro; **city proper 1,009,833 = largest FL city** (source: https://en.wikipedia.org/wiki/Jacksonville_metropolitan_area) | Strong in-migration (~31,700 net, 2024), GDP ~$130B; least saturated; easiest entry | Least tourism-dense; smallest ceiling; event-surge upside is low |

### RECOMMENDED FIRST CITY: **Tampa** (RECOMMENDATION)

Sequence entry by **regulatory/competitive difficulty, not raw size** (source takeaway #5, florida-market brief). Tampa is the sweet spot: enough real, year-round demand (business travel, a growing 3.42M local base, TPA airport, Port Tampa Bay cruise, Busch Gardens tourism) to prove the model, but without Miami's incumbent + challenger + robotaxi pile-up or its extreme nightlife surge. **Jacksonville** is the lower-risk alternative (least saturated, easiest regulatory/competitive entry) but has the smallest ceiling — a reasonable choice if the priority is de-risking over upside. **Miami and Orlando are Phase-6 prizes**, not launch cities: Miami for visitor density, Orlando for the marketable $7-fee grievance.

### Demand is tri-modal — design for three riders, not one (FACT + ANALYSIS)

1. **Snowbirds/seasonal residents** — ~1M migrate Nov–April, staying 4–5 months; winter population rises >5% (source: https://www.floridasmart.com/articles/snowbird-season-florida). Steady, price-sensitive, longer trips (medical/grocery/dining). *(2019 figure: snowbirds contributed $95B+ — treat as dated, source: https://floridafinanceblog.com/how-snowbirds-impact-floridas-economy/.)*
2. **Event/nightlife spikes** — Spring Break (Miami Beach, Feb–Mar), Art Basel, Miami Boat Show, MegaCon (~180K attendees, source: https://www.clickorlando.com/news/local/2025/02/08/thousands-head-to-orange-county-convention-center-for-megacon-2025/), IAAPA Expo (38,520 verified, source: https://iaapa.org/about/press-room/press-release-iaapa-expo-2025-conclues-with-record-breaking-attendance). Short, extreme-surge, safety-sensitive windows.
3. **Constant tourist/cruise/airport base layer** — effectively year-round given record cruise volumes.

### Airports (FACT)

| Airport | 2025 pax | Rideshare pickup fee | Note |
|---|---|---|---|
| **MCO** (Orlando) | 57.7M (7th busiest U.S.) | **$7.00** — highest of any U.S. city where Uber operates | Escalated $5.80→$6.35→$7.00 in 2023; active fee-parity dispute (taxi $4 vs. TNC $7) (sources: https://www.businesstraveller.com/news/orlando-international-airport-uber-pickup-fee/, https://www.fox35orlando.com/news/orlando-airport-cracking-down-unpermitted-drivers-rideshare-drivers-users-lament-pricing-model) |
| **MIA** (Miami) | 55.3M+ (8th busiest U.S.) | ~$3.00 (secondary/unverified — confirm with MDAD) | Governed by OD 18-03, eff. Dec 8 2025; geofence + real-time pings + mandatory trade dress + 5-yr records |
| **FLL** (Ft. Lauderdale) | 32.2M (**−8.5% YoY**, source: https://www.broward.org/Airport/Business/about/Documents/FLLstats_august2025.pdf) | Not confirmed current | Rare *decline*; documented Dec-2025 wait-time breakdown (see below) |
| **TPA** (Tampa) | 25M+ | **$6.50 + $20 minimum** "eff. July 1 2026" (conflicting/unverified) | Waiting lot: 2402 N Westshore Blvd |

**🔴 Do not quote MIA/FLL/TPA per-trip fees in marketing or to investors** — only MCO's $7 is reliably verified; the other three conflict across secondary sources (source: florida-regulation §4). Each airport requires its own permit (see §1, §14).

### Cruise + theme parks (FACT)

- **~21.9M cruise passengers in 2025** across Port Canaveral (8.60M, world's #1, +13.3% YoY), PortMiami (8.56M, world's #2; single-day record 75,201 on Nov 30 2025), Port Everglades (4.77M, world's #3) (sources: https://www.upi.com/Top_News/US/2025/12/02/port-canaveral-miami-busiest-cruise-port/5321764708143/, https://www.seatrade-cruise.com/ports-destinations/port-everglades-confirms-2025-record-4-77m-cruise-moves). **This is arguably the single most underexploited high-density mobility segment in the country** — predictable embarkation/debarkation windows, not airport chaos.
- Theme parks are well-served by incumbents — **Uber is Universal Orlando's official rideshare partner** with a dedicated Uber Zone (source: https://www.uber.com/blog/orlando/universal-orlando-resort/). A real competitive moat at that property; our edge there is price-transparency, not access. (Disney's "Minnie Van"/Lyft partnership is dated 2017 and unconfirmed for 2025–26 — treat as unverified.)

### Local pain points with Uber/Lyft (the best-sourced ones)

1. **MCO's uniquely high, disputed $7 fee** — a recurring consumer/press talking point since 2023 (multiple sources §4).
2. **FLL December-2025 wait-time breakdown** — named travelers, real quotes: *"It says like 22, then it says 18, then it goes back to 30... normally it is a pretty good system, but this year it is not"* — Abbigail Baumstark (source: https://www.local10.com/traffic/2025/12/29/travelers-experience-long-waits-for-ride-share-services-at-fll/). Citable, current, emotionally resonant evidence of incumbent failure at peak holiday demand.
3. **Structural airport-geofence surge** — drivers hold back near geofences until surge triggers, producing 1.5–3x "captive-market" fares at TPA/MIA/MCO (source: https://gridwise.io/blog/are-airport-queues-worth-it-rideshare-drivers-2026).

> **HONESTY CAVEAT to carry forward:** Florida "rideshare accident/assault" statistics found in research come from **personal-injury-law marketing blogs** with no primary NHTSA/FLHSMV citation (e.g., https://hirejared.com/accidents/are-uber-or-lyft-accidents-common-in-florida/). **Do not use these as headline facts.** They are labeled unverified in the source material and must stay that way.

**Regulatory tailwind (FACT).** F.S. 627.748 gives Florida a *single statewide* TNC framework that preempts local TNC licensing (source: https://law.justia.com/codes/florida/title-xxxvii/chapter-627/part-xi/section-627-748/) — a structural advantage vs. states with fragmented city-by-city rules. Airport/seaport permits are the main surviving local lever.

---

## 3. Competitor Analysis

### Uber / Lyft / Waymo teardown (FACT — all fetched 2026-08-12)

| Dimension | Uber | Lyft | Waymo |
|---|---|---|---|
| Hero register | Transactional (booking form *is* the hero); "Go anywhere with Uber" | Emotional/lifestyle ("The world awaits" / A/B "One app. All the rides.") | Mission/emotional ("Because they're everything") |
| Primary CTA | "See prices" | "Sign up to ride" | "Find your autonomous ride" |
| Pricing shown pre-signup | None until address entered | One illustrative fare ($14.61) | None — "know your cost before you book" promise only |
| Safety framing | Feature-list (8 sections), one hard number ($1M liability) | Feature-list + named advocacy partners, **zero statistics** | **Statistics-first** + third-party audits (Swiss Re, FIA 3-star) |
| Homepage testimonials | None | None | 4 rider quotes |
| Referral $ on owned page | None current (only a 2015 post) | Explicitly withheld ("estimates only," $2,000/wk cap) | N/A |
| FL airports | MIA/MCO/TPA/FLL listed generically | 23 FL airports; **$100-credit on-time-to-airport guarantee** | None yet; MIA "in the near future," no date |
| FL ground status | Live statewide | Live statewide | **Live in Miami since Jan 22 2026; expanding to Orlando** |

Sources: https://www.uber.com/us/en/ride/, https://www.uber.com/us/en/safety/, https://www.lyft.com/, https://www.lyft.com/airports, https://www.lyft.com/safety, https://waymo.com/, https://waymo.com/safety/, https://www.cnbc.com/2026/01/22/waymo-launches-robotaxi-service-in-miami-extending-us-lead.html.

### What each does great

- **Uber:** homepage *is* the transaction (booking form as hero, minimal clicks-to-convert); scale-as-trust in concrete numbers ("700+ airports," "15,000+ cities"); one hard safety number ($1M liability).
- **Lyft:** the **$100 on-time-to-airport guarantee** turns reliability into a refundable dollar commitment; Lyft Pink quantifies its own value ("save avg $23/month"); Safety Advisory Council names *real, checkable* outside orgs (It's On Us, National Sheriffs' Assn, NOBLE, NAWLEE, HRC).
- **Waymo:** the **edge-case video carousel** (red-light runner, street fight, skateboarder) shows the failure mode *being handled* instead of asserting safety in prose — the single most effective trust mechanic reviewed; leads with third-party-audited stats; genuinely local Miami launch copy (Wynwood, Brickell, I-95, SR-836).

### Exploitable gaps a Florida challenger can attack (FACT-grounded)

1. **None of the three shows a Florida-specific price, safety stat, or promo anywhere.** Uber/Lyft list FL airports as generic directory entries — no "Miami traffic," no hurricane season, no FL insurance specifics. A Florida-native brand can own hyper-local trust signals a templated national page structurally cannot produce.
2. **Neither Uber nor Lyft publishes a current referral dollar figure on its own site** — a concrete, honored, non-expiring number is a cheap differentiator (once we've *built* referral — 🔧).
3. **No incumbent shows real testimonials/star ratings** on the pages fetched; all rely on off-platform App Store scores that diverge sharply from Trustpilot/BBB (Uber 4.9★ App Store vs. 1.04★ BBB) — a *smaller but verifiable* review base can out-credibility them on trust.
4. **Waymo has zero rider-facing pricing transparency** and **is not at any FL airport yet** — a live, time-boxed window to be the human-driven, bookable, airport-serving local alternative while Waymo is capped to ~60–150 sq mi of Miami urban core.
5. **All three safety pages talk past each other** — adopting Waymo's *evidentiary* format (state-specific, named FL safety partner à la Lyft's Council) would out-position Uber's and Lyft's own weaker safety pages, not just Waymo's.

### Niche / regional players — the real "anti-Uber" field (FACT)

| Player | Model | FL status | Takeaway for us |
|---|---|---|---|
| **Alto** | Premium, owned fleet, W-2 employee drivers | **Launched Miami Sept 2021, SHUT DOWN Feb–Apr 2024** (source: https://www.axios.com/2024/02/21/alto-shrinks) | The premium-employee-driver model **already failed once in Florida** — do NOT copy it (§7) |
| **Curb** | Licensed-taxi aggregator; "Professional drivers, fair fares" | Miami/Ft. Lauderdale; Curb Flow in Miami-Dade + Palm Beach; **Lyft distributes through Curb in NYC** (source: https://www.lyft.com/blog/posts/lyft-and-curb-expand-partnership-to-nyc) | Regulatory-legitimacy lane is defensible but thin outside Miami-Dade |
| **Empower** | Zero-commission; driver pays ~$30/mo subscription, keeps 100%; **live in South FL + Tampa/Orlando** (source: https://faq.driveempower.com/hc/en-us/articles/23432490803085) | **Active FL competitor today** | Direct threat on driver-economics; but **sued by NYC TLC** (source: https://www.nbcnewyork.com/news/local/empower-new-york-city-lawsuit/6483354/) — the subscription model carries legal risk |
| **inDrive** | Name-your-price negotiated fares; **Miami is its U.S. hub** (341% driver / 44% rider growth) (source: https://refreshmiami.com/news/how-indrive-is-shaking-up-miamis-rideshare-scene-by-putting-drivers-first/) | Active, aggressive in Miami | Proof a driver-first non-Uber brand gains real FL traction — but crowds the Miami driver-acquisition lane |
| **Wingz** | Flat-rate, no-surge, pre-scheduled airport/favorite-driver | Lists Miami/Orlando/Tampa (primary site unreachable — thin execution?) | The flat-rate/no-surge airport lane is **contestable, not owned** |
| **Veyo / ModivCare** | Medicaid NEMT (B2B2G) | Active FL; **ModivCare in Ch. 11 since Aug 2025** (source: https://en.wikipedia.org/wiki/ModivCare) | A future B2G revenue line, not our core consumer product |

**Cross-cutting insight (ANALYSIS):** almost no credible challenger competes head-on with Uber/Lyft on raw price for a spontaneous point-to-point city ride. Every one re-segments (by use-case, rider type, driver economics, or regulatory status). **We should too** — trust + price-certainty + favorite-driver + local, not "cheaper."

---

## 4. US vs. China Analysis

DiDi, Meituan, and the WeChat/Alipay super-app playbooks, with verdicts for a capital-constrained Florida launch.

| Tactic (China) | What it is | Verdict | Reason |
|---|---|---|---|
| Two-sided referral vouchers + **visible leaderboard** | DiDi: referrer ~$10 / new rider ~$20 after first ride, plus a rider/driver referral leaderboard (source: https://web.didiglobal.com/au/help-center/refer-a-friend/) | **ADAPT** | The voucher itself is already U.S. norm; the *visible-rank social-proof layer* is underused by Uber/Lyft and cheap to add. (Our referral is 🔧 — must be built first.) |
| Tiered driver commission ("DiDi Advance": lower take-rate at higher tiers) | Silver/Gold/Platinum/Diamond, weekly quests | **APPLICABLE** | Legal under F.S. 627.748's IC framework (source: https://www.hunton.com/hunton-employment-labor-perspectives/florida-legislation-establishes-ride-sharing-drivers-independent-contractors-not-employees); funded by margin, not subsidy — ideal for a startup |
| **Blanket subsidy wars** (DiDi/Kuaidi ~$700M; Uber China lost >$1B in 2015) | Multi-billion cash burn | **DO NOT COPY** | Capital-scale mismatch *and* U.S. predatory-pricing litigation exposure (cf. *SC Innovations v. Uber*, source: https://www.theantitrustattorney.com/predatory-pricing-rarely-but-not-never-successful-under-us-antitrust-laws/) |
| Targeted, **capped** welcome credits | Fixed-$, time-boxed first-ride/first-week vouchers | **APPLICABLE** | The legal, affordable version of the subsidy instinct — standard U.S. growth practice |
| Cross-brand loyalty partnership (DiDi × Tims China: ride → free bagel, ~20K new loyalty members in 2 weeks) | Points-toward-an-item tie-in | **APPLICABLE** | Directly portable — partner a Tampa/FL SMB (coffee, QSR, venue) for "ride with us, get a reward there." Low cash cost, taps their audience |
| Cross-vertical membership tiers (Meituan Black Diamond spanning delivery/travel/mobility) | Super-app loyalty ladder | **ADAPT the shell only** | The cross-vertical version needs a super-app we shouldn't build; a single-vertical rides-only points ladder is fine |
| Lightweight gamification (spin-the-wheel, streak badges) | Engagement loops | **ADAPT** | Discount reveals + ride-streak badges translate fine. **Skip Pinduoduo-style "recruit a friend to unlock" forced-sharing** — reads as a dark pattern, invites FTC/AG scrutiny |
| Behavioral personalization (Meituan: movie after dinner) | AI cross-sell | **ADAPT (single-vertical only)** | Surface a promo at a rider's commute window; build with opt-in from day one (FDBR treats precise geolocation as sensitive, source: https://usercentrics.com/knowledge-hub/florida-digital-bill-of-rights-fdbr/ — FDBR's $1B trigger doesn't bind us yet, but build privacy-first anyway) |
| Daily mandatory biometric driver verification (DiDi facial scan) | Anti-account-sharing | **ADAPT lighter** | Goal is sound; daily persistent biometrics carry BIPA/FDBR risk. Use an occasional **shift-start selfie-match, stored transiently** — captures most of the benefit, far less exposure |
| **Social ride-matching** (DiDi Hitch: browse profiles to pick a ride partner) | Community feature | **DO NOT COPY** | Directly enabled two 2018 rape-murders; China itself abandoned it. Non-negotiable |
| Live trip-share / SOS suite (DiDi post-2018) | Safety features | **APPLICABLE** | Standard, low-risk — but note **our SOS is audit-log-only today (🔧)**; build the real thing before claiming it |
| **Super-app / mini-program ecosystem** (WeChat 1.1B MAU) | Everything-app | **DO NOT COPY (ambition)** | No U.S. host platform; X's failed "everything app" is the cautionary tale (source: https://www.forbes.com/sites/ronshevlin/2026/04/17/musks-x-money-how-it-could-win-and-why-it-wont/). **Redirected insight:** get *discovered inside* Google/Apple Maps trip-planning (the U.S. analog to Amap aggregation), don't become the platform |

**Bottom line (ANALYSIS):** import the *cheap, legal, margin-funded* mechanics (tiered driver commission, capped welcome credits, cross-brand local partnership, leaderboard referral, visible safety) and hard-refuse the *capital-scale* and *unsafe* ones (subsidy wars, social ride-matching, super-app).

---

## 5. Target Personas

Compact template per persona: **Problem · Uses now · Why switch · Winning message · Features they care about · Objection.** All feature references carry ✅/🔧/🔮.

### Riders

**1. Daily commuter**
- Problem: unpredictable morning pricing, no continuity of driver.
- Uses now: Uber/Lyft, sometimes transit.
- Why switch: favorite-driver priority dispatch (✅) + scheduled rides (✅) = the same trusted driver for the 7:40 commute.
- Message: *"Your driver. Your time. Every workday."*
- Features: favorite drivers (✅), scheduled rides (✅), saved places (✅), surge ceiling (✅).
- Objection: "Will a car actually be there at launch density?" → sell honesty on ETAs + presence-heartbeat matching (✅).

**2. Tourist (domestic/international)**
- Problem: surge shock, pricing opacity, unfamiliarity.
- Uses now: Uber/Lyft, hotel taxis.
- Why switch: price with a published ceiling (✅), cash-or-card (✅ — huge for international visitors without U.S. cards), local route knowledge.
- Message: *"Honest fares from the airport — cash or card, no surge surprises."*
- Features: surge ceiling (✅), cash mode (✅), fare estimate (✅), receipts (✅).
- Objection: "Never heard of you." → local trust signals, reviews, airport landing pages (§19).

**3. Airport traveler**
- Problem: the $7 MCO fee, geofence surge, the FLL wait-time breakdown.
- Uses now: Uber/Lyft, shuttles.
- Why switch: transparent airport pricing, scheduled airport pickup (✅), no runaway surge (✅).
- Message: *"Land, ride, done — a fair price you saw before you booked."*
- Features: scheduled rides (✅), surge ceiling (✅), tiers (✅). **(Airport service requires per-airport permit — 🔴, §14.)**
- Objection: "Can I count on pickup?" → be honest; consider a Lyft-style on-time promise *only once supply supports it* (🔮).

**4. Students**
- Problem: cost-sensitive, safety-conscious, often unbanked/thin-credit.
- Uses now: Uber/Lyft splits, transit, walking.
- Why switch: cash mode (✅), promo codes (✅), fair pricing.
- Message: *"Get home safe without blowing your budget."*
- Features: cash (✅), promos (✅), bidirectional ratings (✅), in-trip chat (✅).
- Objection: price → capped first-ride promo + student-partnership codes (§13).

**5. Families**
- Problem: capacity, trust, car-seat needs.
- Uses now: Uber XL, own car.
- Why switch: XL tier (✅), favorite-driver continuity (✅), transparent price.
- Message: *"Room for everyone, a driver you already trust."*
- Features: XL tier (✅), favorite drivers (✅). *(Car-seat availability is not in code — do NOT claim it; 🔧/absent.)*
- Objection: safety → show what's real (OTP start ✅, ratings ✅, tracking ✅); do not overclaim.

**6. Nightlife**
- Problem: extreme late-night surge, safety, availability.
- Uses now: Uber/Lyft.
- Why switch: surge ceiling (✅) is the killer feature exactly when incumbents gouge.
- Message: *"No 3 a.m. surge shock. Get home for what it should cost."*
- Features: surge ceiling (✅), real-time tracking (✅), share-trip *(honest: trip tracking exists ✅; automated emergency delivery does not — 🔧)*.
- Objection: "Will I get a ride at bar close?" → driver incentives on event nights (§13).

**7. Business travelers**
- Problem: reliability, receipts, professionalism.
- Uses now: Uber, black car, Blacklane.
- Why switch: comfort/premium tiers (✅), scheduled rides (✅), clean receipts (✅), favorite driver (✅).
- Message: *"Reserve the ride, keep the receipt, skip the surprises."*
- Features: comfort/premium tiers (✅), scheduled (✅), receipts (✅). *(No dedicated corporate billing yet — 🔮/🔧.)*
- Objection: "Is it professional-grade?" → premium tier + favorite-driver consistency.

**8. Seniors / snowbirds**
- Problem: card-first apps, tech friction, longer steady trips (medical/grocery).
- Uses now: family, taxis, Uber with help.
- Why switch: **cash mode (✅)**, favorite-driver continuity (✅), scheduled rides (✅), simple UX.
- Message: *"The same friendly driver, cash or card, whenever you need to go."*
- Features: cash (✅), favorite drivers (✅), scheduled (✅), large-type accessible UI (§15).
- Objection: "Too complicated." → accessibility-first design, phone-OTP simplicity (✅).

**9. Price-sensitive**
- Problem: surge, opaque fees.
- Uses now: whoever's cheapest that minute; Empower/inDrive in FL.
- Why switch: surge ceiling (✅), transparent fare model (🔮 — internal estimate, self-disclaimed; never present as competitor quotes).
- Message: *"See the price. No surge games."*
- Features: surge ceiling (✅), promos (✅), cash (✅).
- Objection: "Are you actually cheaper?" → **do not claim to undercut Uber/Lyft with the internal price model**; compete on *certainty*, not a cheapness claim.

**10. Safety-conscious**
- Problem: stranger-danger, incident-response doubt.
- Uses now: Uber/Lyft, texts to family.
- Why switch: favorite-driver (✅), OTP ride-start (✅), ratings (✅), Checkr background checks (✅ real-when-keyed), real-time tracking (✅).
- Message: *"Start every ride with a code. Ride with drivers you choose."*
- Features: OTP start (✅), favorite drivers (✅), background checks (✅ when keyed), tracking (✅). **Honesty:** SOS/911 is 🔧 — do not claim it; rider ID verification is absent (🔧).
- Objection: "How do I know it's safe?" → the §14 "we can honestly say today" list, nothing more.

### Drivers

**D1. Full-time / primary-income driver**
- Problem: rising take-rate (independent estimates 44–52%+, source: https://www.nelp.org/insights-research/unpacking-uber-and-lyfts-predatory-take-rates/), deactivation with no appeal, opaque pay.
- Uses now: Uber + Lyft (multi-apping — 41–53% do, earning 20–40% more, source: Gridwise).
- Why switch: transparent itemized pay ledger (✅), fair fixed commission, published appeal rights.
- Message: *"See every dollar on every receipt. Keep more. Real appeal rights."*
- Features: earnings ledger (✅), instant/fast payouts via Stripe Connect (✅ real-when-keyed), favorite-driver priority (✅).
- Objection: "Enough rides to matter?" → *"Add us alongside Uber/Lyft — most drivers run 2+ apps."*

**D2. Part-time / side-income driver**
- Problem: wants flexibility (77% prefer it, source: https://atr.org/survey-77-app-based-drivers-prefer-flexibility-receiving-employment-benefits/) + fast pay.
- Why switch: online/offline control (✅), accept/decline (✅), fast payout (✅).
- Message: *"Drive when you want. Get paid fast. No exclusivity."*
- Features: presence heartbeat (✅), payouts (✅), promos.
- Objection: signup friction → honest, fast onboarding **(note: doc-upload pipeline is a manual admin toggle today — 🔧, must build before real onboarding).**

**D3. Empower/inDrive-curious driver**
- Problem: already chose a driver-first brand for take-home %.
- Why switch: our fixed-percentage transparency with **clean FL regulatory standing** (vs. Empower's NYC legal exposure).
- Message: *"Driver-first, and built to comply — no legal cloud over your income."*
- Features: transparent ledger (✅), tiered commission (🔮 — build per §4), local human support (🔧 — must staff).
- Objection: "You're new." → be honest about density; sell additive multi-app + transparency.

---

## 6. Brand Positioning

### Brand-name exploration (RECOMMENDATION — all pending USPTO/Florida trademark clearance)

"RideVela" is an internal codename and **cannot** be the public brand (uses the "Uber" mark). Recommended shortlist, chosen to be ownable, Florida-resonant, and pairable with a warm-coral identity (§15):

| Name | Rationale | Watch-out |
|---|---|---|
| **Vamos** *(recommended)* | "Let's go" — action-forward, works in English *and* Spanish (Miami-Dade is majority-Hispanic; Tampa ~25%+); memorable, short | Common word — needs strong trademark strategy in the mobility class |
| Cabana | Warm, Florida-leisure, distinctive ("your Cabana is arriving") | May read leisure over serious-tech |
| Sunroute | Descriptive, Florida-sun + routing; SEO-friendly | Less emotionally distinctive |
| Palma | Palm imagery, clean, bilingual-friendly | Generic-adjacent |
| Verano | "Summer" (Spanish) — warm, year-round-Florida feel | Existing auto-model association (Buick Verano) |

**Recommended: "Vamos"** — the action verb doubles as the app's whole promise (*let's go, honestly*), carries in both languages that matter in Florida, and pairs cleanly with the coral/sun identity. **Clear trademark before committing.** (This doc uses "**Vamos**" as a placeholder brand below; substitute the final chosen name.)

### Positioning directions (comparison)

| Direction | Emotional core | Pros | Cons | Risk |
|---|---|---|---|---|
| **A. Local-first Florida-native** | Belonging / "built for here" | No incumbent owns it; ties to real market gap (§3 gap #1); durable | Softer on why-switch alone | Low |
| **B. Price-certainty / no-surge** | Relief from surge anxiety | Ties to surge-ceiling (✅) + MCO-fee grievance; concrete | Wingz partly holds the flat-rate niche | Med |
| **C. Trust / favorite-driver** | Safety + human continuity | Ties to favorite-driver dispatch (✅) — genuinely differentiated | Needs real safety substance (much is 🔧) | Med |
| **D. Driver-first economics** | Fairness | Rides FL momentum (inDrive/Empower) | Crowded + legally fraught lane; risks under-selling rider value | Med-High |
| **E. Premium / quality (Alto-style)** | Status | Clear | **Alto's exact model already FAILED in Miami** | High |

### RECOMMENDATION: a synthesis of A + B + C (reject D-as-lead and E)

**Positioning line:** *"The Florida ride that treats you fairly — pick a driver you trust, pay a price with no surprises, cash or card."*

- **Emotional message:** ride-hailing today runs on low-grade anxiety — surge shock, a stranger every time, fees you can't predict. **Vamos removes the anxiety:** a driver you chose, a price you saw, paid the way you want, from a company that's actually *from here.*
- **The one thing to remember:** **"No surge surprises. A driver you trust."**
- Driver-first economics (D) is a powerful *driver-side* pitch (§11) but should **not** be the master brand promise — riders don't buy a company's labor policy, and the lane is legally fraught. Lead rider-side with trust + certainty + local; carry driver fairness as the supply-side story.

---

## 7. Unique Differentiators

Defensible, tied to real capability where possible. **Not "cheaper."**

| # | Differentiator | Backed by | Why defensible | Build flag |
|---|---|---|---|---|
| 1 | **Favorite-Driver Priority Dispatch** — request the driver you trust, on-demand (not just pre-scheduled like Wingz) | ✅ favorite drivers + priority dispatch + presence heartbeat (a parked favorite stays matchable) | Requires real dispatch engineering (Redis GEO expanding-ring, per-driver locks, favorite priority) — hard to fast-follow; Wingz only does it for scheduled | ✅ HAVE |
| 2 | **Surge With a Published Ceiling** — fares can rise with demand but never past a stated cap | ✅ live surge engine (demand/supply grid) + admin ceiling | Directly answers the #1 sourced FL pain point (MCO $7, airport geofence 1.5–3x, nightlife) | ✅ HAVE |
| 3 | **Cash or Card** — ride without a credit card | ✅ cash mode supported | Unlocks international tourists, unbanked students, seniors — segments Uber/Lyft's card-first flow underserves | ✅ HAVE |
| 4 | **Transparent, Fair Driver Pay** — itemized ledger, visible fixed commission, published appeal rights | ✅ driver earnings ledger + Stripe Connect payouts | Neutralizes the #1 driver grievance (take-rate opacity) *structurally*, with cleaner FL standing than Empower | ✅ HAVE (tiered commission + formal appeal SLA are 🔧) |
| 5 | **Florida-Native, Local-First** — built for FL airports, cruise ports, snowbirds, events; local support | Brand/ops + ✅ scheduled rides, saved places | No national incumbent produces genuinely local content (§3 gap #1); durable brand moat | Brand ✅ / local support staffing 🔧 |

**Secondary support:** OTP ride-start (✅), bidirectional ratings (✅), real-time tracking via Socket.IO multi-node fan-out (✅), scheduled rides (✅) for snowbirds/commuters.

**Explicitly NOT differentiators (honesty):** "SOS/emergency" (🔧 audit-log only), "verified riders" (🔧 absent), live re-routing / turn-by-turn (🔧 absent — route computed once at booking via OSRM), and the internal "price comparison" (🔮 — a self-disclaimed model, never "real Uber/Lyft pricing"). **Referral** (a growth lever, §16) is **absent — 🔧.**

---

## 8. Website Architecture

| Page | Purpose | Primary CTA |
|---|---|---|
| `/` Homepage | Convert cold traffic; establish trust + wedge | **See your price** |
| `/ride/` How it works | Explain the rider product | Download the app |
| `/ride/florida/` State hub | SEO state rollup + local story | See prices in your city |
| `/ride/florida/tampa/` (+ orlando, miami, jacksonville, fort-lauderdale) | City commercial pages (unique local content) | See prices in {city} |
| `/ride/florida/tampa/{district}/` | Neighborhood pages (post-launch, once city ranks) | See prices |
| `/airports/tpa/` (+ mco, mia, fll, jax) | Highest-intent airport hubs | Book your airport ride |
| `/airports/{code}/terminal-{x}/`, `/pickup/` | Terminal + pickup instructions | Book your pickup |
| `/routes/{origin}-to-{destination}/` | Airport↔landmark/cruise-port route pages | See this route's price |
| `/drive/` Driver home | Recruit drivers | Apply to drive |
| `/drive/florida/{city}/` | City driver landing pages | Start earning |
| `/safety/` | Communicate *honest* trust elements (§14) | See how we keep rides safe |
| `/pricing/` | Explain surge ceiling + fare model | See your price |
| `/cities/` | Where we operate (SAB-honest) | Pick your city |
| `/vs/uber/{city}/`, `/vs/lyft/{city}/`, `/vs/indrive/miami/` | Comparison hubs (factually rigorous) | Try {brand} |
| `/blog/{slug}/` | SEO/content engine (§12, §17) | Contextual to post |
| `/help/`, `/legal/`, `/privacy/` | Support + compliance | Contact us |

---

## 9. Detailed Homepage Strategy (top → bottom)

Real copy, not placeholders. Brand = **Vamos** (placeholder).

**Section 1 — Live-map hero**
- Objective: answer "does this actually work *here*?" in 2 seconds.
- Content: live/animated map centered on the launch market (Tampa) with an animated pickup pin + a pickup/destination input overlay (Uber's proven pattern), one primary CTA. Powered by our self-hosted OSRM/Nominatim stack (🔮 — Google provider takes precedence if keyed) or a Mapbox-class map.
- Headline: **"Florida rides, minus the surprises."**
- Supporting copy: *"Pick a driver you trust. See your price before you book. Pay cash or card. Vamos is built for Florida — airports, cruise ports, and everywhere in between."*
- CTA: **See your price** (secondary: *Get the app*, with QR).
- Visual: real Florida street/map, not a stock illustration or AI render (§15).
- Conversion purpose: transaction-first, like Uber, but leads with the trust promise incumbents don't.

**Section 2 — The three-promise strip**
- Objective: state the wedge fast.
- Content: three cards — **No surge surprises** (surge with a published ceiling, ✅) · **A driver you trust** (favorite-driver priority dispatch, ✅) · **Cash or card** (✅).
- Headline: **"Three things every Florida ride should be."**
- CTA: *See how it works.*
- Conversion purpose: differentiate in one scroll.

**Section 3 — Price-certainty explainer (the surge-ceiling proof)**
- Objective: make "no surprises" concrete.
- Content: a simple fare-anatomy graphic — base + time + distance, with a **capped** surge band highlighted in coral.
- Headline: **"Surge with a ceiling — not a blank check."**
- Supporting copy: *"When it's busy, prices can rise — but never past a cap we publish. No $65 rides to the airport."* *(Do NOT cite the internal price-comparison model as competitor quotes — 🔮.)*
- CTA: *See your price.*
- Visual: annotated fare bar.
- Conversion purpose: neutralize the surge-shock objection.

**Section 4 — Favorite-driver / trust**
- Objective: sell human continuity.
- Content: illustration of "re-request your driver," plus what's *real* — OTP ride-start (✅), ratings (✅), background checks via Checkr (✅ when keyed), live tracking (✅).
- Headline: **"Ride with someone you've ridden with before."**
- Supporting copy: *"Favorite a driver, and Vamos gives them priority to pick you up again. Every ride starts with a verification code."*
- CTA: *Meet our drivers.*
- Conversion purpose: trust differentiation vs. "a stranger every time."

**Section 5 — Built for Florida**
- Objective: own local.
- Content: named airports (TPA/MCO/MIA/FLL/JAX), cruise ports (Port Tampa Bay, PortMiami, Port Canaveral, Port Everglades), snowbird + event use-cases.
- Headline: **"From the terminal to the ship to your front door."**
- Supporting copy: *"Vamos knows Florida — record airport traffic, three of the world's busiest cruise ports, snowbird season, and every event weekend in between."*
- CTA: *Find your city.*
- Conversion purpose: the local moat incumbents can't template.

**Section 6 — Social proof (honest)**
- Objective: credibility without fake scale.
- Content: real, verifiable early reviews with source attribution; a *smaller-but-real* review base beats borrowed App Store numbers (§3 gap #3). Pre-launch: waitlist counter + founding-driver quotes.
- Headline: **"Real riders. Real drivers. Real Florida."**
- Conversion purpose: trust via transparency.

**Section 7 — First-ride offer**
- Objective: reduce first-purchase risk.
- Content: capped first-ride promo (✅ promo codes exist).
- Headline: **"Your first ride's on us — up to $10 off."** *(final $ set at launch)*
- CTA: **Claim your first-ride credit.**
- Conversion purpose: direct answer to "does this actually work."

**Section 8 — Driver cross-sell**
- Objective: recruit supply.
- Headline: **"Drive with Vamos — keep more of every fare."**
- CTA: **Apply to drive** → `/drive/`.

**Section 9 — App download + QR**
- Headline: **"Get Vamos. Get going."**
- CTA: App Store / Google Play badges + QR.

**Section 10 — Footer**
- 3–4 columns: Product · Company · Legal · Cities we serve. Include the honest safety link (§14), not an over-claim.

---

## 10. Customer Conversion Funnel

| Stage | Likely drop-off cause | On-site fix |
|---|---|---|
| **Ad** (Google/Meta/TikTok) | Generic "another Uber" | Lead creative with the wedge: *"No surge surprises. Cash or card."* + city name |
| **Landing** | Mismatch to ad | City/airport-specific landing pages (§8) matching ad intent 1:1 |
| **Value** | "Why not just Uber?" | Three-promise strip (§9.2) above the fold |
| **Trust** | Unknown brand anxiety | Honest safety elements (§14): OTP start, background checks (when keyed), ratings — nothing fake |
| **Benefits** | Not concrete | Surge-ceiling graphic + favorite-driver explainer |
| **Social proof** | No reviews yet | Verifiable early reviews + waitlist counter; founding-driver quotes |
| **Offer** | No urgency | Capped first-ride credit with a visible expiry |
| **Download** | Friction / "will I remember?" | QR in hero + footer; SMS-me-the-link |
| **Registration** | Form fatigue / no card | Phone-OTP auth (✅); **surface cash option early** (✅) so card-less users don't bounce |
| **First ride** | Low density / long ETA | Honest ETAs; launch-market supply incentives (§13); scheduled-ride option (✅) |
| **Repeat** | No reason to return | Favorite-driver re-request (✅); saved places (✅); ride-streak nudge |
| **Referral** | **No program exists (🔧)** | **Build referral first** (§16); then two-sided credit + visible leaderboard |

---

## 11. Driver Acquisition Strategy

### FL driver economics + grievances (FACT)

- Statewide avg **~$38,667/yr ($19.57/hr)**; **Miami/Ft. Lauderdale ~$55,952/yr ($28.32/hr)**; **Orlando ~$38,302/yr ($17/hr)** — modeled aggregator data, not company-disclosed, and *not* net of vehicle expense (sources: https://www.talent.com/salary?job=uber+driver&location=florida, https://www.talent.com/salary?job=uber+driver&location=miami%2C+fl, https://www.salary.com/research/salary/alternate/uber-driver-salary/orlando-fl).
- A Central FL driver's rate fell **99¢→68¢/mile**; got **$15 of a $37 airport fare** (source: https://finance.yahoo.com/news/uber-drivers-quitting-over-reduced-154348189.html). Independent take-rate estimates: **44% Uber / 52% Lyft** (source: https://www.nelp.org/insights-research/unpacking-uber-and-lyfts-predatory-take-rates/); Uber counters 21% worldwide (different accounting).
- Grievances: **take-rate opacity**, **deactivation with no appeal** (majority got no notice, source: https://documentedny.com/2025/10/29/majority-uber-lyft-drivers-deactivated-report-aaldef/), Orlando cited on UberPeople.net as "the worst" (low pay, no surge).
- Switching motivators: **instant/fast pay** (top retention lever), **transparency > more money**, **multi-apping is the norm** (41–53%; +20–40% earnings). Drivers already have flexibility — the unmet need is **earnings certainty**.

### Earnings message (RECOMMENDATION)

Lead with the **structural** claim, not a disputable average: *"See every dollar on every receipt."* Our real ✅ assets: itemized earnings **ledger**, Stripe Connect **payouts** (fast pay when keyed), favorite-driver priority (more repeat riders). Avoid quoting a specific "average earnings" number — every such number is contested and invites the same skepticism drivers have for Uber's.

### Requirements (de-facto FL floor — set as company policy, not "the law")

21+, valid U.S. license ≥1 yr, vehicle inspection, background check (F.S. 627.748 mandates multi-state criminal + national sex-offender registry + MVR, recheck every 3 yrs; **21+/inspection is insurer/industry floor, not statutory** — source: florida-regulation §6). **🔴 Our doc-upload pipeline is absent — `docsVerified` is a manual admin toggle today (🔧). Build it before onboarding real drivers.**

### Incentives + retention

- **Driver referral** (highest-realism early lever) — pay **after** N completed trips (e.g., $50–150 after 20–30 trips; ANALYSIS/estimate, sized well below Uber's ~$2,175 / Lyft's $400–2,500). **Requires the referral build (🔧).**
- **Fast/free instant payout** (✅ when keyed) — the single strongest retention lever.
- **Tiered commission ladder** (DiDi-Advance-style, §4) — lower take-rate for volume; margin-funded (🔮 build).
- **Transparent itemized pay** (✅) + **published appeal SLA with a human step** (🔧 — build the workflow; F.S. 627.748 already requires deactivation-reevaluation for protected-characteristic claims).
- **Local human support** (🔧 — must staff; a real differentiator vs. bot-routed incumbents).

### Driver landing page spec (`/drive/florida/tampa/`)

- **Hero headline:** **"Florida drivers, keep more of every fare. No mystery math."**
  (City-swap variant for paid search: *"Drive Tampa. Keep more of every fare."*)
- **Subhead:** *"See your pay itemized on every ride. Get paid fast. Add Vamos alongside Uber and Lyft — most drivers run more than one app."*
- **Primary CTA:** **Apply to drive** (honest, fast flow: phone + basic info → doc upload → background check via named vendor → approval).
- **Objection-busters:**
  - *"Will I get enough rides?"* — *"We're new in Tampa, so drive us alongside Uber/Lyft, not instead. No exclusivity, ever."* (honest — don't over-promise density)
  - *"How fast do I get paid?"* — fast/instant payout (✅ when keyed).
  - *"What if I'm deactivated?"* — published appeal process with a human review step **(build the SLA first — 🔧).**
  - *"Is this legal in Florida?"* — yes; we operate under F.S. 627.748 as a compliant TNC. *(State only what counsel confirms.)*
  - *"What does it cost me?"* — one transparent, fixed commission shown on every receipt — no subscription surprise, no hidden take.
- **Proof block:** itemized-receipt graphic ("$18 fare → you see exactly what you keep"), average approval-time indicator (transparency incumbents don't surface).

---

## 12. SEO Strategy

**Keyword clusters (intent-ranked; no volume asserted — validate per below):**
- **City (core commercial):** `Tampa rideshare`, `Miami rideshare`, `Orlando rideshare`, `book a ride {city}`, `taxi {city}`.
- **Airport (highest intent):** `TPA airport ride`, `MCO airport ride`, `MIA airport taxi`, `{code} rideshare pickup terminal`, `Orlando airport to Disney rideshare`.
- **Tourist/route:** `Miami airport to South Beach taxi`, `MCO to Disney Springs Uber cost`, `FLL to Port Everglades ride`, `Tampa airport to Busch Gardens`.
- **Competitor-alternative (BOFU):** `Uber alternative Miami`, `cheaper than Uber Orlando`, `apps like Uber Florida` (name inDrive/Curb/Empower honestly).
- **Long-tail (easy wins):** `how much is an Uber from MCO to Disney World 2026`, `how to avoid surge pricing Fort Lauderdale airport`, `Uber driver requirements Florida`, `wheelchair accessible ride Orlando airport`.
- **Category (long-term authority):** `rideshare app Florida`, `Uber vs Lyft Florida`.

**Validation method (no live volume tool this session):** Google Keyword Planner (free baseline) + one paid tool (Ahrefs from ~$29/mo, or Semrush for competitor-gap); Google Trends for seasonality; Search Console post-launch. Tools disagree 5–9x on the same term (source: https://www.practicalecommerce.com/keyword-volume-google-vs-semrush-vs-ahrefs) — cross-check top ~30 terms across two tools before spending.

**Scalable URL architecture (city→metro→state→new-states):**
```
/ride/florida/                         ← state hub
/ride/florida/tampa/                    ← metro
/ride/florida/tampa/downtown/           ← district (generalizes to /ride/texas/austin/downtown/)
/airports/tpa/  /airports/mco/          ← IATA codes are globally unique → zero prefix needed
/airports/mco/terminal-a/  /airports/mco/pickup/
/routes/mco-to-disney-world/            ← combinatorial: every airport × every landmark
/vs/uber/miami/                          ← comparison, isolated for its own audit cadence
/drive/florida/tampa/                    ← driver mirror
```
This mirrors Uber's *live production* pattern (`uber.com/global/en/r/airports/mco/pickup/`, `.../routes/mia-to-south-beach/`) — proven at scale. Flat 3-level depth keeps link equity near the root.

**🔴 Doorway-page guardrail (FACT):** Google penalizes near-identical city pages that differ only by a swapped city name — post–March-2024, such sites saw **80%+ of those pages lose rankings, up to 63% traffic drop** (source: https://outreachmonks.com/doorway-pages/). **The architecture scales; the per-page unique content does not.** Mandatory per page: dated local fare *ranges*, ≥1 locally-specific FAQ, real named landmarks, unique title/meta/H1, and **no auto-generated pages for cities with zero real driver supply.**

**15+ blog topics mapped to funnel** (from research §4): MCO→Disney cost (TOFU/MOFU), MIA→South Beach ranked (MOFU), FLL→Port Everglades taxi-vs-rideshare (MOFU), "Florida's Rideshare Law §627.748 Explained" (E-E-A-T), "Uber Alternatives in Miami: inDrive, Curb, Empower & Vamos" (BOFU), "How to Avoid Surge at FL Airports" (MOFU), "MCO Terminal-by-Terminal Pickup Guide" (BOFU), "Spring Break Rideshare Costs on South Beach" (seasonal), "Rideshare Driver Requirements in Florida" (driver TOFU), "Snowbird's Guide to Rideshare" (demographic), "Cruise Port Transportation: PortMiami/Everglades/Canaveral" (MOFU), "Hurricane Season & Rideshare in Florida" (trust), "Wheelchair-Accessible Rides City-by-City" (accessibility), "Miami→Orlando: Rideshare vs. Brightline vs. Rental" (comparison), "NYE on South Beach: Prices & Waits" (seasonal BOFU), "Rideshare with Kids in Florida: Car-Seat Rules" (TOFU).

**Local SEO + schema (FACT):** Use `TaxiService` schema (subtype of `Service`) with a `LocalBusiness`/`Organization` provider and `areaServed`/`GeoCircle`; configure Google Business Profile as a **service-area business** (don't fake a storefront). **FAQ caveat (2026):** Google **removed FAQ rich results entirely on May 7 2026** (source: https://www.searchenginejournal.com/google-drops-faq-rich-results-from-search/574429/) — do NOT build the plan around FAQ SERP snippets, but **keep FAQPage markup** (pages with it are ~3.2x more likely to appear in AI Overviews). Date-stamp every fare figure.

---

## 13. Marketing Channel Strategy

Prioritized across phases (channels tied to realism ratings from growth research §16).

| Channel | Pre-launch | Launch | Post-launch |
|---|---|---|---|
| **Driver referral** (🔧 build) | Build infra; seed founding drivers | **Primary supply lever** — pay after N trips | Scale, add tiers |
| **Google Search (SEM + SEO)** | Stand up airport/city pages | Bid city+airport+"Uber alternative" terms | Expand routes/districts |
| **Meta (FB/IG)** | Waitlist + lookalikes | City-targeted wedge creative | Retarget, referral push |
| **TikTok** | Teasers, founder story | UGC: "no surge surprise" reactions, airport hacks | Creator seeding |
| **YouTube** | — | Short pre-roll on FL-travel/how-to-Uber content | Explainers, driver stories |
| **Influencer/creator codes** (🟢, unverified ROI) | Line up FL micro-creators | Local Tampa/FL creators w/ tracked codes | Expand by city |
| **Local partnerships (SMB)** | Line up coffee/QSR/venue tie-in (DiDi×Tims model) | "5 rides = free coffee" co-marketing | Rotate partners |
| **Hotels** | Concierge outreach | Front-desk cards, QR at check-in | Preferred-partner deals |
| **Airports** (🔴 permit first) | Secure permits | Curbside signage where permitted | Terminal-level SEO/route pages |
| **Universities (USF, UCF, UF)** | Ambassador recruiting | Student codes, safe-ride-home push | Semester campaigns |
| **Events/nightlife** | Map the event calendar | Event-night driver incentives + venue codes (Art Basel/MegaCon/Spring Break) | Own the event calendar |
| **Cruise ports** | Terminal/port outreach | Embarkation-window supply + port route pages | Cruise-line concierge tie-ins |
| **Email/SMS** (email = 🔧 absent in code) | Collect waitlist (SMS via Twilio when keyed) | First-ride nudges | Lifecycle (build email channel first) |
| **Referral (rider, two-sided)** (🔧) | Build | Turn on *after* organic signal; hard A/B cap | Leaderboard layer |
| **Content/blog** | Publish law + market-gap pieces | MOFU/BOFU posts linking to live pages | Weekly cadence |

**City-launch playbook (FACT-grounded):** stealth entry → founding-driver ambassadors (solve supply first, inDrive's proven FL pattern) → flyering + bar/venue promo codes (Uber's launch playbook: 3M+ flyers outperformed digital for years) → capped first-ride promo → local PR (the "first Florida market sizing" angle). **Defer municipal-subsidy partnerships** (Uber's 2017 SunRail-discount model) until there's a track record.

---

## 14. Trust & Safety Strategy

The website must split trust into two columns and **never blur them.**

### ✅ We can honestly say today (real code, real-when-keyed)
- **Every ride starts with a verification code (OTP ride-start).** (✅)
- **Two-way ratings** on every trip. (✅)
- **Background checks via Checkr** — *only claim this once keyed*; today it's real-when-keyed, auto-clearing mock by default (✅/gated). Copy: *"Drivers pass a background check before their first ride"* — true only once the key is live.
- **Real-time GPS trip tracking** you can watch in-app (Socket.IO multi-node). (✅)
- **Driver photo + vehicle + plate shown before you get in** (statute-required, ✅).
- **Electronic receipt** with route, time, distance, fare (statute-required, ✅).
- **Favorite drivers** — ride with people you've vetted yourself. (✅)

### 🔧 Build before we can claim it (DO NOT put on the site yet)
- **🔴 Insurance.** Absent in code; **legally mandatory** (F.S. 627.748: Period 1 & 2 = $50k/$100k/$25k; **Period 3 = $1M**, limousine-level PIP; post-7/1/2025 three-tier structure, source: https://www.flsenate.gov/Session/Bill/2025/1206/Analyses/2025s01206.pre.bi.PDF). **No insurance claim of any kind on the website until the policy is bound.** This is the single hardest launch blocker.
- **🔴 Real SOS / emergency.** Today = **audit-log entry only** — no 911, no emergency-contact notification, no trip-share delivery, no emergency-contact model. **Never market "SOS," "emergency button," "we call 911," or "share your trip with a contact"** until built.
- **Rider identity verification** — none today (🔧).
- **Driver document-upload pipeline** — absent; `docsVerified` is a manual admin toggle (🔧). Build before real onboarding.
- **Live per-driver ETA countdown / live re-routing / turn-by-turn** — absent (🔧); route computed once at booking via OSRM.

**RECOMMENDATION (safety page format):** borrow Waymo's *evidentiary* approach — but with only what's real. State F.S. 627.748's mandated safety floor (background checks, $1M active-trip coverage *once insurance is bound*), name a real FL safety partner (à la Lyft's Council) once secured, and make the already-mandated checks *visible in-app* (the cheap, legal, China-inspired "make safety legible" move, §4). **Under-claim and over-deliver.**

---

## 15. Visual / UX Direction (2026)

**The dominant 2026 convention (FACT, across Uber/Lyft/Waymo/Robinhood/Ramp/Wise/Bolt):** near-monochrome base + **exactly one saturated accent used functionally** + a proprietary/semi-custom display face + flat, hairline-bordered, shadow-free components (sources: https://robinhood.com/us/en/newsroom/a-new-visual-identity/, https://www.narrowlabs.design/website-inspiration/ramp, https://superdesign.dev/blog/uber-design-system).

- **Color (RECOMMENDATION):** warm off-white canvas (`#FAFAF8`–`#F5F4F0`), near-black text (`#141414`, not pure black), neutral-gray hairlines (`#E5E3DE`), and **one accent uncontested by the majors** — a **warm coral/amber (`#FF5A36`-range)**. Blue is Uber/Waymo, pink is Lyft, green is Wise, yellow/chartreuse is Ramp/Bolt. Coral is uncontested *and* on-brand for Florida sun. Reserve the accent for CTAs, live/active states, and money-or-motion moments only. **Full light + dark tokens** (dark mode is structural in 2026, not optional). Do **not** use a rainbow "friendly taxi" palette — reads small-scale.
- **Typography:** Inter (or a licensed grotesque) as the free UI/body workhorse (what Wise uses for body); reserve **one distinctive variable display face** for hero headlines only (tight ~1.0–1.1 leading, oversized, confident) to buy the "proprietary type" signal without commissioning a face.
- **Photo vs. 3D/AI:** **lead with real photography** — real Florida cars, drivers, streets. A rideshare's core anxiety ("is this real, will a real car come?") is answered by real imagery, not AI/3D renders. Reserve 3D/illustration for abstract secondary concepts (surge mechanics, earnings).
- **Animation:** functional, not decorative — (1) the **live-map hero** is the single highest-value animation for a mobility product; (2) subtle scroll-reveal on stat/trust sections; (3) avoid scroll-jacking/parallax (perf + accessibility backlash). Respect `prefers-reduced-motion`.
- **Live-map hero:** OSRM/Mapbox-class live map of the actual Tampa service area + animated pickup pin + pickup/destination overlay (Uber's input pattern) — *not* a stock map graphic. (Our OSRM/Nominatim stack already exists — 🔮.)
- **Mobile-first + CTA:** single unambiguous verb CTA repeated at every scroll depth ("See your price"); nav split **Rider / Driver / (later) Business**; QR for app download in hero + footer.
- **Design-system starter:** flat hairline-bordered cards (12–16px radius), no drop shadows (border-not-shadow depth), simple ~6–8px-radius buttons.
- **Accessibility:** **build to WCAG 2.2 AA from day one** (courts reference 2.1 AA as the ADA benchmark; 3,117 federal web-accessibility suits in 2025, +27% YoY — source: https://www.levelaccess.com/blog/2024-u-s-web-accessibility-litigation-key-trends-and-strategies-for-mitigating-risk/). 4.5:1 body-text contrast; check any glassmorphism against AA.

---

## 16. Growth & Referral Strategy

> **🔧 Referral is ABSENT in code — only generic promo codes exist. It must be built.** It is the backbone of the highest-realism levers below and a 🔴 in the action plan.

| Mechanic | Real-$ reference | Two-sided? | First-ride/loyalty | Realism (early-stage) |
|---|---|---|---|---|
| **Driver referral** | Uber ~$2,175 / Lyft $400–$2,500 per referred driver, after trip thresholds (sources: growth §16) — we size to **$50–150 after 20–30 trips** (ANALYSIS/estimate) | Driver→driver | — | **High** — solve supply first; existing drivers are best recruiters; cost capped to post-trip |
| **First-ride promo** | Uber: 30% off, up to $8, 14-day expiry (source: https://www.uber.com/us/en/promo/) | No | First-ride | **High** — cheapest, most controllable lever |
| **Invite-a-friend layer** | Waze Carpool: $20 + $20/referral, capped 10 ($200) | Distribution surface | — | **High** — near-zero marginal cost once referral infra exists |
| **Two-sided rider referral** | DiDi ~$10 referrer / ~$20 new rider; Lyft caps $2,000/wk platform-wide; PayPal $20/$20 ceiling burned $60–70M | Rider↔rider | — | **Medium** — turn on *after* organic signal; hard A/B cap; don't stack with first-ride promo (makes CAC unmeasurable) |
| **Visible referral leaderboard** (DiDi) | — | Social-proof layer | — | **Medium** — cheap add on referral infra; the differentiator Uber/Lyft lack |
| **Local cross-brand partnership** (DiDi×Tims: ~20K members/2wks) | Points-to-item | — | Loyalty-ish | **Medium** — piggyback a FL SMB's audience |
| **Corporate referral / employer** | — | — | — | **Low** — needs B2B sales + billing; defer |
| **Loyalty/points program** | Uber shut Uber Rewards down as uneconomical | — | Loyalty | **Low** — do not build pre-launch |
| **Gamification (spin/streak)** | — | — | — | **Low-Med** — light streak badges OK; skip forced-sharing dark patterns |

**City-launch playbook (repeatable):** seed drivers (referral) → founding-rider waitlist → capped first-ride promo → local PR (market-gap story) → SMB/venue tie-ins → *then* two-sided rider referral once organic word-of-mouth is measurable. **Corporate referral is a Phase-6 line, not a launch lever.**

---

## 17. 90-Day Content Plan

**Month 1 — Pre-launch / awareness (Tampa focus)**
- **Website:** publish `/airports/tpa/`, `/ride/florida/tampa/`, `/safety/` (honest), waitlist landing.
- **Blog:** "Florida's Rideshare Law §627.748, Explained" (E-E-A-T); "The First-Ever Look at Florida's Ride-Hailing Market" (the data-gap PR play — label the ESTIMATE honestly).
- **Instagram:** founder story, "why we're building a Florida ride," coral-brand teasers.
- **TikTok:** "POV: your airport ride didn't surge" concept teasers; behind-the-scenes founding drivers.
- **LinkedIn:** founder POV on driver transparency + FL market gap; driver-recruiting posts.
- **Email/SMS:** waitlist capture (SMS via Twilio when keyed; email channel is 🔧).
- **Local SEO:** GBP as SAB; Tampa city + TPA airport pages indexed.

**Month 2 — Launch (Tampa live)**
- **Website:** first-ride offer live; `/routes/tpa-to-downtown-tampa/`, `/routes/tpa-to-busch-gardens/`; `/drive/florida/tampa/`.
- **Blog:** "TPA Airport Rideshare Pickup Guide"; "Tampa Airport to Downtown: Rideshare vs. Taxi vs. Shuttle."
- **Instagram/TikTok:** UGC "no surge surprise" reactions; favorite-driver stories; student safe-ride content (USF).
- **YouTube:** 30–60s explainer + pre-roll on FL-travel content.
- **Email/SMS:** first-ride nudge sequence to waitlist.
- **Local:** SMB "5 rides = free coffee" partner launch; bar/venue codes; USF ambassador push.

**Month 3 — Early growth**
- **Website:** `/vs/uber/tampa/` (rigorous, dated); neighborhood pages once city ranks.
- **Blog:** "Cruise Port Transportation from Tampa"; "Snowbird's Guide to Rideshare" (timed for Nov season ramp); "How to Avoid Surge at Florida Airports."
- **Instagram/TikTok:** referral-launch campaign + leaderboard (once referral built); driver-earnings-transparency reels.
- **LinkedIn:** launch-metrics recap; driver testimonials.
- **Email/SMS:** referral invite + lapsed-rider re-engagement.
- **Local SEO:** weekly Search Console near-miss optimization; expand to a second metro's airport hub (MCO or JAX) prep.

---

## 18. Launch Roadmap (6 phases)

**Phase 1 — Research & Positioning**
- Objectives: lock positioning, brand name, first city.
- Deliverables: this doc; trademark clearance for "Vamos"; final positioning + color/type.
- Marketing: none external.
- KPIs: decisions locked; brand cleared.
- Budget: legal (TM search), design discovery.
- Dependencies: none.

**Phase 2 — Brand & Website**
- Objectives: ship the marketing site + design system.
- Deliverables: homepage, `/ride`, `/drive`, `/safety` (honest), TPA + Tampa pages, WCAG 2.2 AA, live-map hero.
- Marketing: waitlist capture.
- KPIs: site live, Lighthouse/CWV green, waitlist signups.
- Budget: web build, design system, map tooling.
- Dependencies: brand locked.

**Phase 3 — Pre-launch (🔴 compliance gate)**
- Objectives: **make it legal and real.**
- Deliverables: **bind three-tier insurance (🔴)**; **build doc-upload pipeline (🔴)**; **build referral infra (🔴 for growth)**; key live vendors (Stripe/Twilio/Checkr/FCM/Maps); **build real trip-share + emergency flow before any safety claim (🔴)**; TPA airport permit; registered agent filed.
- Marketing: founding-driver recruiting; waitlist nurture.
- KPIs: insurance bound; drivers onboarded via real pipeline; permit in hand.
- Budget: insurance premium (~$10k/vehicle/yr airport-grade reference, source: https://www.clickorlando.com/news/local/2024/09/30/), vendor keys, dev.
- Dependencies: legal counsel; insurer.

**Phase 4 — Florida (Tampa) Launch**
- Objectives: first real rides; prove unit economics.
- Deliverables: apps live; first-ride promo; driver referral live.
- Marketing: §13 launch column; local PR.
- KPIs: rides/day, driver liquidity, ETA, CAC, first-ride→repeat rate, surge-ceiling adherence.
- Budget: promo credits (capped), local marketing, driver incentives.
- Dependencies: Phase 3 gate cleared.

**Phase 5 — Growth**
- Objectives: retention + density in Tampa; add a second metro's airport.
- Deliverables: two-sided rider referral (post-signal), leaderboard, tiered driver commission, SMB partnerships; MCO or JAX prep.
- Marketing: full §13 post-launch column; content cadence.
- KPIs: repeat rate, referral incrementality (A/B), driver retention, CAC trend.
- Budget: scaled incentives, content.
- Dependencies: Tampa unit economics validated.

**Phase 6 — Expansion**
- Objectives: Orlando (the $7-fee grievance) + Miami (biggest prize, but Waymo/inDrive/Empower live); replicate URL/content architecture to a second state.
- Deliverables: per-airport permits (MCO/MIA/FLL), city + route pages, corporate referral line, possible NEMT/B2G exploration (ModivCare's Ch. 11 opening).
- Marketing: metro-specific campaigns; event-calendar ownership.
- KPIs: multi-market liquidity, blended CAC/LTV, market share signals.
- Budget: multi-market ops, permits, insurance scale.
- Dependencies: repeatable, profitable city playbook.

---

## 19. Website Wireframes (text)

**Homepage**
```
┌─────────────────────────────────────────────────────────┐
│ VAMOS      Rider  Driver  Safety  Cities     [See price] │
├─────────────────────────────────────────────────────────┤
│  ██ LIVE MAP OF TAMPA — animated pickup pin ██           │
│  ┌───────────────────────────┐                           │
│  │ Pickup ▸  Destination ▸   │  "Florida rides, minus    │
│  │        [ See your price ] │   the surprises."         │
│  └───────────────────────────┘        [Get the app ▸QR]  │
├─────────────────────────────────────────────────────────┤
│ [No surge surprises] [A driver you trust] [Cash or card] │
├─────────────────────────────────────────────────────────┤
│  SURGE-CEILING FARE BAR ▓▓▓▓░ (cap highlighted in coral) │
│  "Surge with a ceiling — not a blank check."   [See price]│
├─────────────────────────────────────────────────────────┤
│  FAVORITE DRIVER  |  OTP code · ratings · live tracking  │
├─────────────────────────────────────────────────────────┤
│  BUILT FOR FLORIDA: TPA·MCO·MIA·FLL·JAX + cruise ports   │
├─────────────────────────────────────────────────────────┤
│  REAL REVIEWS (verifiable)    |   FIRST RIDE up to $10   │
├─────────────────────────────────────────────────────────┤
│  Drive with Vamos — keep more of every fare [Apply ▸]    │
├─────────────────────────────────────────────────────────┤
│  Product | Company | Legal | Cities we serve   [badges]  │
└─────────────────────────────────────────────────────────┘
```

**For Riders (`/ride/`)**
```
┌──────────────────────────────────────────────┐
│ HERO: "Every ride should feel fair."  [App ▸] │
├──────────────────────────────────────────────┤
│ HOW IT WORKS: estimate ▸ tier ▸ confirm ▸     │
│   OTP-start ▸ track ▸ receipt   (all ✅)       │
├──────────────────────────────────────────────┤
│ TIERS: Economy · Comfort · XL · Premium (✅)  │
├──────────────────────────────────────────────┤
│ WHY VAMOS: surge ceiling · favorite driver ·  │
│   cash or card · scheduled rides (all ✅)      │
├──────────────────────────────────────────────┤
│ SAFETY (honest link) · FAQ · [See your price] │
└──────────────────────────────────────────────┘
```

**For Drivers (`/drive/`)**
```
┌───────────────────────────────────────────────┐
│ HERO: "Keep more of every fare. No mystery     │
│   math."                       [Apply to drive]│
├───────────────────────────────────────────────┤
│ ITEMIZED-RECEIPT GRAPHIC: $18 fare → you keep… │
├───────────────────────────────────────────────┤
│ FAST PAY (✅) · TRANSPARENT LEDGER (✅) ·       │
│   FAVORITE-DRIVER REPEAT RIDERS (✅)            │
├───────────────────────────────────────────────┤
│ REQUIREMENTS: 21+ · license 1yr · inspection · │
│   background check (named vendor)              │
├───────────────────────────────────────────────┤
│ "Add us alongside Uber/Lyft — no exclusivity"  │
├───────────────────────────────────────────────┤
│ OBJECTION FAQ · avg approval time · [Apply ▸]  │
└───────────────────────────────────────────────┘
```

**Safety (`/safety/`)**
```
┌────────────────────────────────────────────────┐
│ HERO: "Safety you can actually verify."         │
├────────────────────────────────────────────────┤
│ ✅ WHAT'S REAL TODAY:                            │
│   OTP ride-start · two-way ratings ·            │
│   live GPS tracking · driver+plate shown ·      │
│   background checks (when keyed) · receipts     │
├────────────────────────────────────────────────┤
│ FLORIDA LAW: F.S. 627.748 mandated floor        │
│   ($1M active-trip coverage — once bound)       │
├────────────────────────────────────────────────┤
│ NAMED FL SAFETY PARTNER (once secured)          │
├────────────────────────────────────────────────┤
│ (NO "SOS/911" claims until built — 🔧)          │
└────────────────────────────────────────────────┘
```

**City landing page (`/ride/florida/tampa/`)**
```
┌────────────────────────────────────────────────┐
│ H1: "Rideshare in Tampa" + [See your price]     │
├────────────────────────────────────────────────┤
│ LOCAL TRIP METRICS: avg time / price range /    │
│   distance (dated "as of Aug 2026")             │
├────────────────────────────────────────────────┤
│ POPULAR TAMPA ROUTES (internal links):          │
│   TPA↔downtown · TPA↔Busch Gardens · ↔cruise    │
├────────────────────────────────────────────────┤
│ WHY VAMOS IN TAMPA: surge ceiling · cash · local│
├────────────────────────────────────────────────┤
│ LOCAL FAQ (unique, schema-marked) · TNC-compliance│
│ LAST-UPDATED stamp · [See your price]           │
└────────────────────────────────────────────────┘
```

**Airport landing page (`/airports/tpa/`)**
```
┌────────────────────────────────────────────────┐
│ H1: "Tampa Airport (TPA) Rides" [Book pickup]   │
├────────────────────────────────────────────────┤
│ TRIP METRICS: TPA→downtown ~15 min, $range      │
│   (dated) — NO unverified airport-fee claim     │
├────────────────────────────────────────────────┤
│ PICKUP INSTRUCTIONS by terminal/level ·         │
│   waiting-lot note                              │
├────────────────────────────────────────────────┤
│ SCHEDULE YOUR AIRPORT RIDE (✅ scheduled rides)  │
├────────────────────────────────────────────────┤
│ SURGE-CEILING reassurance · popular routes ·    │
│   local FAQ · compliance · last-updated         │
└────────────────────────────────────────────────┘
```
*(Airport pages go live only once that airport's TNC permit is secured — 🔴.)*

---

## 20. Prioritized Action Plan

Single ranked list. Owner-type: **LEG** legal, **INS** insurance, **ENG** engineering, **DES** design, **MKT** marketing, **OPS** ops, **FDR** founder.

| # | Action | Tag | Owner | Depends on |
|---|---|---|---|---|
| 1 | **Bind post-7/1/2025 three-tier insurance ($50k/$100k/$25k P1&P2; $1M P3); no site insurance claim until bound** | 🔴 | INS/LEG | — |
| 2 | **Secure first-city (TPA) TNC airport permit; file registered agent** | 🔴 | LEG/OPS | — |
| 3 | **Build driver document-upload pipeline** (replace manual `docsVerified` toggle) | 🔴 | ENG | — |
| 4 | **Stand up statutory background-check pipeline + calendared 3-yr recheck; key Checkr live** | 🔴 | ENG/LEG | — |
| 5 | **Build referral program** (rider + driver + leaderboard) — absent today | 🔴 | ENG | — |
| 6 | **Build real trip-share + emergency flow before ANY SOS/safety claim** | 🔴 | ENG | — |
| 7 | **Key live vendors** (Stripe/Twilio/FCM/Maps) for prod | 🔴 | ENG | — |
| 8 | **Trademark-clear + lock brand name** ("Vamos" recommended) | 🔴 | LEG/FDR | — |
| 9 | **Lock positioning + coral/off-white/near-black + Inter+display; live-map hero** | 🔴 | DES/FDR | 8 |
| 10 | **Ship marketing site to WCAG 2.2 AA** (home, ride, drive, safety-honest, TPA+Tampa pages) | 🔴 | DES/ENG | 9 |
| 11 | **Lock scalable URL architecture before indexing**; TaxiService/LocalBusiness schema; SAB GBP | 🔴 | ENG/MKT | 10 |
| 12 | **Recruit founding drivers** (solve supply first) | 🔴 | OPS/MKT | 1,3,4 |
| 13 | **Capped first-ride promo** (promo codes ✅) | 🟡 | MKT | 10 |
| 14 | **Driver-referral payout** (after N trips) | 🟡 | MKT/OPS | 5,12 |
| 15 | **Publish airport/city/route pages** with dated unique local content (doorway-safe) | 🟡 | MKT | 11 |
| 16 | **Build email channel** (absent in code) for lifecycle | 🟡 | ENG | — |
| 17 | **Publish driver appeal SLA + deactivation-reevaluation workflow** | 🟡 | LEG/ENG | — |
| 18 | **Confirm airport fees directly** (only MCO $7 verified; don't quote MIA/FLL/TPA) | 🟡 | OPS | — |
| 19 | **Local SMB partnership** ("rides = reward") + student/venue codes | 🟡 | MKT | 12 |
| 20 | **Two-sided rider referral + leaderboard** (turn on after organic signal, A/B-capped) | 🟡 | MKT | 5,14 |
| 21 | **Tiered driver commission ladder** (margin-funded) | 🟢 | ENG/OPS | 4 |
| 22 | **Content cadence** (15+ blog topics), weekly Search Console optimization | 🟢 | MKT | 15 |
| 23 | **Publish "first Florida market sizing" PR** (label ESTIMATE honestly) | 🟢 | MKT | 10 |
| 24 | **Confirm local business-tax-receipt + WAV-claim posture with counsel** | 🟢 | LEG | — |
| 25 | **Phase-6: per-airport permits (MCO/MIA/FLL) + corporate/NEMT lines** | 🟢 | LEG/OPS | Tampa proven |

---

*End of master strategy. Honesty caveats preserved throughout: no Florida TAM exists (only an ESTIMATE); insurance and real SOS are build-first and unmarketable until real; only MCO's $7 airport fee is verified; the in-app price comparison is an internal model, never a competitor quote; referral is unbuilt. Update the fare figures, driver payout amounts, and airport fees against live/primary sources before any of them appear in published copy.*
