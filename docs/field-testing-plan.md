# RideVela — Field & Dispatch Testing Plan

**Version 1.0** · Rider app, driver app, dispatch, pricing, network resilience

| | |
|---|---|
| **Equipment** | 2 driver phones, 2 rider phones, one vehicle, live SIM data on all devices |
| **Total cases** | 23 — **13 must be executed in a moving vehicle** (marked *Field only*) |
| **Instructions** | Execute in order. Mark **P** / **F** for every case. Record a note for every failure. **A failure in Section 1 blocks launch.** |

Tester: ________________  Date: __________  Build / Version: __________

---

## 1. Background — Geofence

A driver only receives a ride request within **9 km** of the pickup point. The
search starts at a 3 km radius, expands to 9 km, and ranks candidate drivers by
road ETA on the closest ring. A driver in another city is never offered the
ride. This matches the industry standard (~5 km in dense urban areas,
ETA-ranked, expanding on failure to match).

Each case records the intended behaviour **and the reason it exists**, so the
purpose of every check is explicit during execution and during review.

---

## 2. Priority 1 — Network and Matching (must pass)

| ID | Test case | Steps | Expected result | P | F |
|---|---|---|---|---|---|
| **1.1** | Full ride over mobile data only · *Field only* | WiFi off on both phones. Book a normal ride to completion (accept, OTP, drive, complete). | All steps work on cellular: offer arrives, car moves live, OTP and complete succeed, receipt displays.<br>*Proves the app is usable on cellular, the real-world default. If it only works on WiFi, almost every real ride fails.* | ☐ | ☐ |
| **1.2** | WiFi → cellular handoff mid-ride · *Field only* | Start the trip on WiFi, then leave WiFi range so the phone switches to mobile data mid-trip. | A brief reconnecting state at most, then live updates resume. No stuck screen, no lost trip.<br>*Proves the live socket survives a network switch — happens whenever a rider leaves home or office mid-ride.* | ☐ | ☐ |
| **1.3** | Dead zone / tunnel — signal lost mid-ride · *Field only* | During a live trip remove signal (tunnel, basement, or airplane mode ~20 s), then restore. | Reconnecting banner appears, then the trip resynchronises to the correct state once signal returns.<br>*Proves resilience. Recovering a live trip instead of freezing is the most common real-world failure.* | ☐ | ☐ |
| **1.4** | Two drivers, one rider | Two driver phones online nearby. Book once from a rider phone. | Only the nearest driver receives the offer. The second stays idle. No double assignment.<br>*Proves the per-driver lock: one ride is never sent to two drivers — the classic dispatch defect.* | ☐ | ☐ |
| **1.5** | No drivers available | All drivers offline or none nearby. Book a ride. | Clear "No drivers nearby — try again", selected tier retained, retry allowed. Not stuck on "finding".<br>*Proves graceful failure, so riders retry instead of abandoning the app.* | ☐ | ☐ |
| **1.6** | Driver comes online after booking | Book with no driver online. Within ~60 s bring a driver online near the pickup. | The 90-second re-sweep detects the ride and the newly online driver receives the waiting request.<br>*Proves late-arriving supply is captured — more completed rides, fewer dead ends.* | ☐ | ☐ |

---

## 3. Priority 2 — Money and Cancellation Edges (should pass)

| ID | Test case | Steps | Expected result | P | F |
|---|---|---|---|---|---|
| **2.1** | Cancel before pickup (free) vs after driver commits (fee) | Ride A: cancel while finding or just matched. Ride B: cancel after the driver is en route. | Early cancellation: no fee. Late: fee shown clearly with the exact amount.<br>*Proves cancellation is fair and transparent — no silent charges.* | ☐ | ☐ |
| **2.2** | Driver declines or lets the offer time out | On the driver phone, decline an offer, or ignore it until the countdown expires. | The offer passes to the next eligible driver. The rider stays in "finding" with no error.<br>*Proves a declined offer re-routes, so one selective driver never strands a rider.* | ☐ | ☐ |
| **2.3** | Cash ride with tip, and a card ride | Complete one cash ride and add a tip on the receipt. Complete one card ride. | Cash tip accepted and confirmed ("Tip added"). Card ride completes. Both receipts correct.<br>*Proves both payment paths, including the cash-tip fix and card capture.* | ☐ | ☐ |
| **2.4** | Fare is correct for the distance | Compare the estimate against the distance shown. Test one very short trip and one longer trip. | Short trip reaches the minimum fare; longer trip scales proportionally. No anomalous values.<br>*Proves pricing is credible to a human. Fare mathematics is already verified in the lab.* | ☐ | ☐ |

---

## 4. Priority 3 — Resilience and Accuracy (good to pass)

| ID | Test case | Steps | Expected result | P | F |
|---|---|---|---|---|---|
| **3.1** | Background the app mid-ride | During a trip, lock the phone or switch apps ~30 s, then reopen. | Trip restores to the correct state (en route / on trip), not reset to home.<br>*Proves the trip survives multitasking, which riders do constantly.* | ☐ | ☐ |
| **3.2** | Reroute — driver takes a different road · *Field only* | Instruct the driver to deliberately take a road other than the drawn route line. | The route line redraws to follow the road actually taken, within a few seconds.<br>*Proves the map tracks reality — the primary basis on which riders judge quality.* | ☐ | ☐ |
| **3.3** | Pickup precision · *Field only* | Check the pickup pin and the "Current location" row against the tester's actual position. | Pin and address match the real position. The recenter control snaps back to the tester.<br>*Proves the driver is sent to the correct spot — incorrect pickup is the leading cause of pickup friction.* | ☐ | ☐ |
| **3.4** | Rider location correct on cold open · *Field only* | Open the rider app from a cold start. | Map lands on the tester's real location, not the Miami fallback. If it opens on the fallback it self-corrects, or one recenter tap fixes it.<br>*Proves the reported location defect is resolved.* | ☐ | ☐ |

---

## 5. Dispatch, Range and Pricing Edges

| ID | Test case | Steps | Expected result | P | F |
|---|---|---|---|---|---|
| **4.1** | Driver out of range (>9 km) receives nothing · *Field only* | Put a driver online 10–15 km away, across the city. Book from the rider phone. | The distant driver is not offered the ride. Only drivers within 9 km are considered.<br>*Proves the geofence: no wasted pings, no impossibly far cars.* | ☐ | ☐ |
| **4.2** | Only a far driver (~7 km) — reached, fare unchanged · *Field only* | Make the only online driver ~7 km from the pickup, still inside the 9 km cap. Book a ride. | That driver does receive the offer; rider sees a longer "arriving in N minutes". Fare is the normal trip fare — the 7 km approach does not inflate it.<br>*Proves the ring expands, ETA reflects the real approach, and driver distance never affects price.* | ☐ | ☐ |
| **4.3** | Surge under real demand | Create demand: several bookings in a small area within a couple of minutes, or test during a busy hour. | Surge multiplier rises, capped at 2×, a "fares are higher due to demand" notice shows, and the fare reflects the multiplier.<br>*Verified at 2× in the lab; this confirms natural triggering.* | ☐ | ☐ |
| **4.4** | Two riders, one driver (race condition) | Two riders book within one second of each other, with only one driver online nearby. | Only one rider is assigned. The other keeps searching or gets "no drivers". Never double booked.<br>*Proves the lock holds under a race — the hardest dispatch defect to detect and the most damaging in production.* | ☐ | ☐ |
| **4.5** | Busy driver is not re-offered | With a driver mid-trip, have another rider book nearby. | The busy driver is skipped; dispatch searches for a free driver.<br>*Proves active drivers are excluded, so no driver holds two rides at once.* | ☐ | ☐ |
| **4.6** | Favourite driver priority | Mark a driver as favourite, then book while that driver is online nearby. | The favourite is offered the ride first, ahead of other equally near drivers.<br>*Proves the favourites queue-jump, a genuine retention feature.* | ☐ | ☐ |
| **4.7** | Location denied — mandatory gate | Deny or disable location permission for the rider app, then attempt to use it. | A clear "location required" gate blocks booking and offers to enable location. No silent Miami fallback.<br>*Proves booking cannot occur from an unknown location.* | ☐ | ☐ |

---

## 6. Endurance

| ID | Test case | Steps | Expected result | P | F |
|---|---|---|---|---|---|
| **5.1** | Long-ride endurance (optional, run once) · *Field only* | Complete one ride of 30–60 minutes, end to end. | Map stays smooth with a long route, live ETA counts down, socket stays connected throughout, completion still succeeds at the end (token auto-refreshes).<br>*Proves 30–60 minute stability: long-route rendering, ETA over distance, socket and token survival.* | ☐ | ☐ |

---

## Before you start — known state

Read this first; several cases will fail for reasons that are **not** defects in
what they are testing.

| Blocker | Effect on this plan |
|---|---|
| **OTP SMS is mocked** | Nobody can log in with a real code. Use the on-screen **dev code**, or read it from the backend logs. Affects every case. |
| **Stripe webhook secret absent** | Card payments authorise and capture but never reach a final state. **Case 2.3's card leg will not settle.** The cash leg and the tip are unaffected. |
| **TLS is off** | Backend is plain HTTP on the LAN. Fine for field testing; blocks App Store. |
| **Background checks mocked** | Driver onboarding completes without a real check. |
| **Disk at 98% on the build box** | Run `docker system prune` before a long session. |

**Device readiness:** Android is continuously validated. **iOS has not been
rebuilt since 2026-09-14 and has never run on a physical iPhone** — if you are
testing on iOS, build it first per [handoff-for-mac.md](handoff-for-mac.md) and
expect the two unverified behaviours called out there (pinch-zoom during
tracking, and background/resume mid-ride).

**Backend address** is DHCP and has moved before — confirm with `hostname -I`
on the Linux box (currently `192.168.1.69`) and pass it as
`--dart-define=API_BASE_URL=http://<ip>:3000/api/v1`.

**Watch it live:** Grafana at `http://192.168.1.69:3001` — the **Ops** dashboard
shows dispatch backlog, match latency and drivers online while you test, which
turns "it felt slow" into a number.
