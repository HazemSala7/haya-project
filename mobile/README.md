# أكاديمية الحياة — التطبيق المحمول

تطبيق Flutter لمتابعة التأهيل، للأخصائيات والأهالي والإدارة.

## البناء والتشغيل

```bash
flutter pub get
flutter run
```

**الخادم**: يشير إلى `https://neurex.ps/haya/api` بشكل افتراضي. غيّره في `lib/core/auth/session.dart`:

```dart
const kApiBase = String.fromEnvironment('API_BASE', 
  defaultValue: 'http://10.0.2.2:8020/api'); // للمحاكي المحلي
```

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8020/api
```

## حسابات التجربة

| الحساب | الدور | كلمة المرور |
|---|---|---|
| `rana@haya.test` | أخصائية | `password` |
| `sanaa@haya.test` | ولي أمر | `password` |
| `admin@haya.test` | إدارة | `password` |

## البنية

```
lib/
├── main.dart                # نقطة الدخول، اختيار الواجهة حسب الدور
├── core/                    # المشترك بين الأدوار
│   ├── api/                 # عميل Dio، معالجة الأخطاء
│   ├── auth/                # Riverpod sessions
│   ├── models/              # النماذج المثنية من البيانات
│   ├── widgets/             # مكوّنات UI: بطاقات، رسوم بيانية، نماذج
│   ├── theme.dart           # الألوان والخطوط
│   ├── format.dart          # التواريخ والأرقام والتسميات
│   ├── data.dart            # Riverpod providers
│   └── core.dart            # Barrel export
├── guardian/                # ولي أمر: الرئيسية والأطفال والرسائل والحساب
├── specialist/              # أخصائية: الرئيسية والطلاب والجلسات والحساب
├── admin/                   # إدارة: الرئيسية والطلاب والفريق والحساب
└── shared/                  # شاشات موحدة: الدخول
```

## الميزات المرحلة الأولى

- ✅ تسجيل الدخول بالبريد أو الهاتف
- ✅ ثلاث واجهات حسب الدور (ولي أمر / أخصائية / إدارة)
- ✅ اللوحة الرئيسية لكل دور
- ✅ شاشات تعريفية للبقية

---

الإصدار: **1.0.0** | اللغة: **عربي**
