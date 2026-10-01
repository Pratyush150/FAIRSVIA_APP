# Lottie animations

| File | Source | Creator | Changes |
|---|---|---|---|
| confetti.json | https://lottiefiles.com/free-animation/confetti-c6X3v895ye | LottieFiles user lenzy68cn1ftjn10 | Recoloured to the FAIRSVIA palette (teal, gold, coral, mint, rose) |
| money.json | https://lottiefiles.com/free-animation/money-5QAsY5qlMO | LottieFiles user wjaviugke1 | none |
| loading.json | https://lottiefiles.com/free-animation/sandy-loading-o4VygOMtb8 | LottieFiles user panamo | none |
| searching.json | https://lottiefiles.com/animations/radar-QE34660xBs ("Radar", #77256) | Waqar Ali (/WaqarBhi) | Blue → accent teal #1FA7A8 (fills, strokes, sweep gradient); ring strokes ×5 so they read at 48–64 px |
| arrived.json | https://lottiefiles.com/animations/location-pin-eMxxvrWIRG ("Location Pin", #10183) | Tam Doan (/kunio) | Blue → teal #0B7A7B |
| no_cars.json | https://lottiefiles.com/animations/non-data-found-jPkYKZPjtk ("non data found", #101961) | Aakash Deep (/t3l27dm3bgpz5zol) | Blues → teal #1FA7A8 / #0B7A7B; greys kept |
| success.json | https://lottiefiles.com/animations/success-tick-cuwjLHAR7g ("success tick", #57137) | Aman Awasthy (/8btri5uxa6l561id) | Green → teal #0B7A7B |
| thanks.json | https://lottiefiles.com/animations/star-YYFe7koQtA ("star", #17304) | idea ideas (/5ahf19fl9i2sm3d3) | Star → gold #F5C542; sparkle dots → palette (teal, accent, mint, marigold, rose) |
| location.json | https://lottiefiles.com/animations/location-permissions-MMe8Q2YEbx ("Location Permissions", #10572) | LottieFiles (/LottieFiles) | Red pin → teal #0B7A7B/#0A5A5A, green toggle → #1FA7A8, black outlines → #3A4148; hand kept |
| offline.json | https://lottiefiles.com/animations/offline-JdB3yBeXkC ("offline", #141337) | Douglas Rodrigues de Sousa (/2plm611qjwirzkf6) | Teals → #0B7A7B / #1FA7A8 (the connection banner tints it to its ink at runtime) |
| sos.json | https://lottiefiles.com/animations/shield-protection-UUE6WNFWoc ("Shield Protection", #23012) | Daris Ali Mufti (/darisalimufti) | Mint → #1FA7A8, cyan sparkles → #4FD6D2, yellow → gold #F5C542 |
| spinner.json | https://lottiefiles.com/animations/loader-vjcwzr1d9f ("loader", #79798) | Hanina Kahfi (/ijum4kzkmt) | Red/rose arc → teal #0B7A7B / accent #1FA7A8. Used by `BrandLoader` and `PrimaryButton` (tinted to the button ink) |
| empty_box.json | https://lottiefiles.com/animations/empty-box-BYA3OT05o0 ("empty_box", #1505657) | Genius (/rk08wo8lbq4xkqaz) | Moth + dashed flight path grey → teal #0B7A7B / #1FA7A8; box greys kept |
| no_results.json | https://lottiefiles.com/animations/no-results-TUMUcoetr5 ("No results", #1040745) | Nzime (/nzime) | Purple → accent #1FA7A8 |
| gift.json | https://lottiefiles.com/animations/untitled-file-BQOhatfwaU ("gift", #1511880) | Erhan KARACA (/bips8luu53) | Greens → teal #0B7A7B / #1FA7A8 / #0A5A5A / mint #4FD6D2; coral confetti strokes → gold #F5C542 |
| trophy.json | https://lottiefiles.com/animations/trophy-xL11f7ayqS ("trophy", #35683) | zanwei.guo (/zanwei.guo) | Yellow → gold #F5C542 |

All are LottieFiles free animations, normally under the Lottie Simple
License (free for commercial use, no attribution required). The licence shown
on each page could not be read automatically (bot protection; the files and
creators were found through LottieFiles' public GraphQL API), so **the owner
must confirm it on each page before launch.**

Shortlist and picks (2–3 candidates per moment, frames at 5/30/55/80 %, and
the recoloured finals): `docs/brand/research/lottie-candidates.png`.

Added 2026-09-25 (spinner, empty_box, no_results, gift, trophy): found and
downloaded through the same public GraphQL API (`searchPublicAnimations`);
all have no embedded images and are 5–36 KB minified. The licence is **assumed** to be the Lottie Simple License like
other free public animations and **must be confirmed on each page by the
owner before launch**. Candidates (8 loaders, 8 empty boxes, 5 no-results,
5 gifts, 5 trophies) were rendered with lottie-web and picked by eye; the
recoloured finals: `docs/brand/research/lottie-candidates-2.png`.

Added 2026-09-26 (rider bottom-nav icons, same public GraphQL API; ~45
candidates per icon rendered with lottie-web and picked by eye for clean line
style). All three are minified, image-free, 8.6–10 KB. No colours are baked
in: `LottieMoment.navHome/navTrips/navAccount` repaint every fill and stroke
at runtime with the nav's selected (accent) / muted colour, so they follow
any theme colour. Licence **assumed** Lottie Simple License, **unconfirmed —
owner must check each page before launch**.

| File | Source | Author | Changes |
|---|---|---|---|

## Bottom-nav icons (2026-09-26, replace the earlier line icons)
Colourful filled illustrations in the same style as `gift.json`, recoloured to the brand teal/gold; Lottie Simple License.
- `nav_home.json` — "house" by Sheraz Khan, https://lottiefiles.com/animations/house-5kDRkbZKF6 (orange roof -> teal, brown door -> gold)
- `nav_trips.json` — "vehicle" by Mistry Yash, https://lottiefiles.com/animations/vehicle-eJKunc2QU5 (purple body -> teal, red light -> gold)
- `nav_account.json` — "Unauthenticated User" by Saam Mohamed, https://lottiefiles.com/animations/unauthenticated-user-0mLs0yHws5 (orange -> teal)

## FAIRSVIA recolour (2026-10-01)

All animations were recoloured for FAIRSVIA with `tools/brand/recolor_lottie.py`:
teal/mint -> blue, gold -> coral (trophy and money keep their gold). Shapes and
motion are unchanged; licence terms above still apply to the modified files.
