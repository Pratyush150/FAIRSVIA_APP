# RideVela Admin

Back-office admin panel for RideVela (ops, KYC/background-check review, fare/surge/promo
config, refunds, live monitoring).

## Platform targets — web + Android only (no iOS by design)

The admin app ships **`web/` and `android/` only — it has no `ios/` folder, intentionally.**
It's an internal back-office tool used from a desktop browser (and, if needed, an Android
device), so an iOS build is not a target. CI builds it via `flutter build web`
(`.github/workflows/ci.yml`).

This is a deliberate exception to the repo-wide "keep iOS-ready" rule (CLAUDE.md §2),
which applies to the customer-facing **rider** and **driver** apps. Those two keep full,
committed `ios/` trees. If admin ever needs an iOS target, scaffold it with
`flutter create --platforms=ios .` from this directory and commit the generated `ios/`.

## Run

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.48:3000/api/v1
# or serve a built bundle:  tools/webserve.py 9090 build/web
```
