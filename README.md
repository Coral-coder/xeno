# xeno
## TestFlight

`.github/workflows/ios-testflight.yml` archives and uploads the iOS app. Put `*u` in a commit
subject on `main` to upload, `*b` to archive only, or run it by hand from Actions. Signing uses
Xcode cloud signing and never revokes certificates.
