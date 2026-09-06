# نصب‌کننده Docker برای 9Router

اسکریپت نصب یک‌خطی برای اجرای [9Router](https://github.com/decolua/9router) با Docker.

## امکانات

- نصب Docker روی Debian/Ubuntu در صورت نصب نبودن
- استفاده از image منتشرشده رسمی پروژه: `decolua/9router:latest`
- اجرای 9Router روی پورت پیش‌فرض `20128`
- نگهداری دائمی داده‌ها در `/opt/9router/data`
- ساخت خودکار secretهای تصادفی و رمز اولیه
- اجرای خودکار کانتینر بعد از reboot با restart policy
- ساخت systemd timer برای بررسی روزانه آپدیت
- دریافت آخرین image و recreate کردن کانتینر فقط در صورت وجود نسخه جدید
- حفظ اطلاعات persistent هنگام آپدیت
- باز کردن TCP پورت 20128 در UFW فقط در صورتی که UFW از قبل فعال باشد
- عدم دستکاری Apache و پورت 443

## نصب یک‌خطی

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

دستور را با کاربر `root` اجرا کنید.

## دسترسی مستقیم

بعد از نصب:

```text
http://IP-SERVER:20128
```

API:

```text
http://IP-SERVER:20128/v1
```

در پایان نصب، رمز اولیه‌ای که به‌صورت تصادفی ساخته شده نمایش داده می‌شود. حتماً آن را ذخیره کنید و در صورت پشتیبانی نسخه نصب‌شده، از داخل داشبورد تغییر دهید.

## فایل‌ها

```text
/opt/9router/
├── .env
├── data/
├── update.sh
└── update.log
```

فایل `.env` با سطح دسترسی محدود `600` ساخته می‌شود. اطلاعات دائمی برنامه خارج از کانتینر نگهداری می‌شوند.

## آپدیت خودکار

یک systemd timer هر روز حوالی ساعت 04:30 image را بررسی می‌کند و برای جلوگیری از فشار هم‌زمان روی سرویس‌ها، تا 10 دقیقه تأخیر تصادفی دارد.

بررسی timer:

```bash
systemctl status 9router-update.timer
```

مشاهده لاگ آپدیت:

```bash
journalctl -u 9router-update.service
```

یا:

```bash
cat /opt/9router/update.log
```

بررسی و اجرای دستی آپدیت:

```bash
/opt/9router/update.sh
```

## مدیریت کانتینر

```bash
docker ps
docker logs -f 9router
docker restart 9router
docker stop 9router
docker start 9router
```

## Cloud / Proxy خود 9Router

این installer فرض نمی‌کند که صرفاً با تنظیم URL سرویس Cloud، یک Cloud Endpoint عمومی ساخته می‌شود. قابلیت Cloud Sync/Endpoint به نسخه نصب‌شده 9Router و تنظیمات داشبورد آن بستگی دارد.

در هر صورت instance محلی از طریق پورت `20128` مستقیماً قابل دسترسی است.

## پورت 443

این installer عمداً از پورت 443 استفاده یا آن را تغییر نمی‌دهد. بنابراین اگر Apache، Mirza یا سرویس HTTPS دیگری روی 443 فعال باشد، تغییری در آن ایجاد نمی‌شود.

## امنیت

پورت `20128` مستقیماً توسط Docker روی سرور منتشر می‌شود. اگر سرور از اینترنت قابل دسترسی است، در صورت نیاز دسترسی این پورت را با firewall یا security group محدود کنید و تنظیمات احراز هویت و امنیت ارائه‌شده توسط نسخه 9Router خود را فعال نگه دارید.

## حذف

برای حذف کانتینر و updater و در عین حال نگه‌داشتن داده‌ها:

```bash
docker rm -f 9router
systemctl disable --now 9router-update.timer
rm -f /etc/systemd/system/9router-update.timer
rm -f /etc/systemd/system/9router-update.service
systemctl daemon-reload
rm -rf /opt/9router
```

دستور آخر را فقط زمانی اجرا کنید که عمداً قصد حذف data و configuration مربوط به 9Router را دارید.

## توضیح

این repository یک installer مستقل برای اجرای 9Router است و بخشی از پروژه اصلی 9Router نیست. خود 9Router و Docker image آن توسط توسعه‌دهندگان پروژه upstream نگهداری می‌شوند.
