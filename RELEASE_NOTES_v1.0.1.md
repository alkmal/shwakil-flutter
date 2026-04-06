# Flutter Release v1.0.1+3

## Highlights

- Added onboarding screens for first launch.
- Improved login and multi-step registration UX and validation.
- Improved OTP, account verification, security, and account settings flows.
- Added top-up requests and card print requests.
- Split heavy admin screens into faster focused screens.
- Improved responsive layout and overall visual consistency.

## Recommended Release Checks

- Registration and password validation
- Login and OTP
- Balance, transfer, and top-up requests
- Admin dashboard and approval screens
- Card print request flow

## Build

```bash
flutter pub get
flutter build apk --release
flutter build appbundle --release
```
