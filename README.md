# virtual_currency_cards

Flutter app with a Laravel backend workspace and MySQL database.

## Backend Status

The backend is now organized around:

- `backend/laravel` for the new Laravel project
- `backend/php` for the current custom PHP API logic
- `backend/public` for the ready-to-upload web + PHP deployment package

Laravel has been scaffolded, configured for the current database, and prepared with API routing.
The full migration of all existing API business logic from `backend/php` into Laravel controllers and services is still a separate next step.

## Current Environment

Backend environment values:

- `MYSQL_HOST=127.0.0.1`
- `MYSQL_PORT=3306`
- `MYSQL_USER=root`
- `MYSQL_PASSWORD=123456`
- `MYSQL_DATABASE=alkmal_wa`

## Laravel Local Run

```powershell
cd backend/laravel
php artisan serve
```

## Current PHP API Local Run

```powershell
cd backend/php
php -S 127.0.0.1:8080
```

## Flutter Local Run

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080/api
```
