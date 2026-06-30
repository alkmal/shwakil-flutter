# Shwakil - Flutter App

نظام بطاقات الدفع المسبق - تطبيق Flutter متعدد المنصات (Android / iOS / Web)

## متطلبات التشغيل

- Flutter SDK 3.x+
- Dart 3.x+
- Backend: Laravel (راجع `../backend/`)

## تشغيل التطبيق

```powershell
cd flutter
flutter pub get
```

### Android / iOS
```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api --dart-define=API_CLIENT_KEY=your-key
```

### Web (Chrome)
```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api --dart-define=API_CLIENT_KEY=your-key
```

## هيكل المشروع

```
lib/
├── main.dart              # نقطة الدخول
├── screens/               # 50 شاشة
├── services/              # 26+ service للتواصل مع API
├── widgets/               # مكونات UI مشتركة
├── models/                # نماذج البيانات
├── utils/                 # أدوات مساعدة والثيم
└── localization/          # دعم تعدد اللغات
```

## الشاشات الرئيسية

- **المصادقة**: تسجيل دخول، تسجيل، OTP، نسيت كلمة المرور
- **البطاقات**: إنشاء بطاقة، مسح بطاقة، طلبات طباعة، مخزون
- **المحفظة**: رصيد، تحويل سريع، طلبات شحن/سحب
- **الأدمن**: لوحة تحكم كاملة لإدارة النظام
