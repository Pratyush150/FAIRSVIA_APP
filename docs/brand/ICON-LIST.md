# RideVela — icons in use and what each one is for

*2026-09-25, final look (Plan F "Map Glass"). Utility icons are Phosphor
(MIT), vendored as fonts in `packages/design_system/fonts/`; `autoRickshaw` and
`cashRupee` are our own glyphs added to those fonts. Generated from the code
(every `PhosphorIcons*.name` use in apps/* and packages/*), then described by
hand. Apps: R = rider, D = driver, A = admin console, all = shared screens.*

Rules they follow (audit 2.1): one icon family; sizes 16 / 20 / 24; filled
only to show a state (selected, rated, favourite); colour by meaning; one
40 px badge style (`AppIconBadge`); every icon-only button has a label.

## Getting around the app
| Icon | Where | Purpose |
|---|---|---|
| `list` | R, D | Account menu button (top right on the map) |
| `arrowLeft` | all | Back button |
| `x` | all | Close / dismiss / cancel ride / remove promo |
| `caretRight` | all | "Opens something" chevron at the end of a row |
| `caretDown` / `caretUp` | R | Expand / collapse (fare details, "Later" chip) |
| `dotsThree` | R | "More options" menu on the live ride (share, help, cancel) |
| `arrowClockwise` | all | Refresh / Try again |
| `arrowUpRight` | R | Fill a search suggestion into the box |
| `magnifyingGlass` | R, A | Search ("Where to?", admin user search) |
| `plus` | all | Add (card, place, promo, support ticket) |
| `pencilSimple` | all | Edit profile / edit item |
| `trash` | all | Delete (saved place, contact, account data) |
| `copy` | all | Copy an error for support |
| `export` | R | Share trip status |
| `paperPlaneRight` | all | Send a chat or support message |

## Map and places
| Icon | Where | Purpose |
|---|---|---|
| `gpsFix` | R, D | Recenter on my location |
| `gpsSlash` | R, D | Location is off / not allowed (banner) |
| `record` | R, D | Pickup point (ring) |
| `square` | R | Destination point in the search screen |
| `mapPin` | R | Destination / drop-off; place rows |
| `mapPinPlus` | R, D | Add a stop |
| `mapTrifold` | R, A | Set location on the map; map placeholder; admin live map |
| `compass` | R | "Search for a destination" empty state |
| `house` | R | Saved place: Home |
| `briefcase` | R | Saved place: Work |
| `star` | all | Saved places (menu) · rating stars (filled = rated) |
| `navigationArrow` | D | Navigate to pickup / drop-off; "keeps working while you navigate" |
| `path` | D, A | Route / trips; "riders see you coming" |
| `flag` | R, D | Drop-off / trip end marker in lists |
| `hourglass` | R | Waiting for the location fix |
| `ruler` | R | Trip distance (ride details) |

## The ride
| Icon | Where | Purpose |
|---|---|---|
| `car` | R, A | Vehicle / ride type / "Vehicle" row; driver card fallback |
| `taxi` | R, A | Finding a driver; ride-type chip; comparison card |
| `autoRickshaw` | — | Auto-rickshaw (built, ride type switched off) |
| `user` | all | Seats per ride type; profile avatar fallback; name field |
| `userCircle` | R, D | Rider / passenger |
| `userPlus` | R | Book for someone else; add emergency contact |
| `personSimpleWalk` | R, D | "I'm on my way" to the driver |
| `clock` | R | Arrival time; scheduled rides |
| `calendarBlank` | R | Pick a date (pre-book) |
| `calendarCheck` | R | Pre-book a ride; ride scheduled |
| `note` | R, D | Note for the driver ("meet at the lobby") |
| `chatCircle` | R, D | Message the driver / rider |
| `phone` | all | Call the driver / passenger; phone field |
| `receipt` | all | Ride details; your trips; rate card; receipts |
| `ticket` | R | Number plate row (ride details) |
| `trendUp` | R | Surge / high demand |
| `lightning` | R | "Fastest" badge on the comparison card |
| `piggyBank` | R | "Cheapest" badge on the comparison card |
| `question` | R | "Unknown" price in the comparison card |
| `circle` | R, A | Neutral status dot |
| `check` | all | Done / selected / completed |
| `checkCircle` | R | Ride completed; selected payment; SOS sent |
| `checks` | all | Mark all notifications read |

## Money
| Icon | Where | Purpose |
|---|---|---|
| `money` | all | Cash payment; earnings; revenue |
| `cashRupee` | — | Cash in rupees (Plan D art; not in the final look) |
| `creditCard` | R | Card payment; payment methods |
| `wallet` | D | Earnings |
| `bank` | D, A | Payouts / direct deposit; platform fees |
| `percent` | D | Commission / platform share |
| `handHeart` | D | Tips received |
| `coins` | A | Refunds |
| `tag` | R, A | Promo codes |
| `sealCheck` | R, D | Verified / guaranteed (payouts, comparison) |
| `chartLineUp` | A | Record an observed competitor fare |
| `cards` | A | Promo / content cards |

## Safety
| Icon | Where | Purpose |
|---|---|---|
| `shieldCheck` | all | **Safety** pill; safety sheet; "only while online" |
| `siren` | all | Send SOS alert |
| `addressBook` | all | Emergency contacts |
| `chatText` | all | Contacts will be texted (SOS) |
| `chatCircleSlash` | all | Nobody will be texted (no contacts yet) |
| `cloudSlash` | all | Couldn't load (offline) |
| `warning` | A | Warning state |
| `warningCircle` | all | Error / retry |

## Account and settings
| Icon | Where | Purpose |
|---|---|---|
| `bell` / `bellRinging` | all | Notifications / new notification |
| `heart` | R | Favourite drivers; add to favourites (filled = favourite) |
| `circleHalf` | all | Appearance (Light / Dark / Same as phone) |
| `sun` / `moon` | all | Light / Dark options in Appearance |
| `moonStars` | D | "You're offline" (resting) |
| `headset` | all | Help & support |
| `envelopeSimple` | all | Email field |
| `deviceMobile` | all | Phone number (account deletion) |
| `signOut` | all | Sign out |
| `userMinus` | all | Delete account |
| `calendarX` | all | Cancelled (account deletion step) |
| `wrench` | all | Server settings (pilot builds) |
| `tray` | all | Empty list |
| `info` | R | Fare breakdown (ⓘ); information notes |
| `broadcast` | D, A | Ride offers near you; drivers online |

## Admin console only
| Icon | Purpose |
|---|---|
| `squaresFour` | Overview |
| `users` | Users / trips list |
| `arrowsLeftRight` | Compare / pricing |
| `toggleLeft` / `toggleRight` | Feature switches off / on |
| `heartbeat` | Monitoring (Grafana) |
