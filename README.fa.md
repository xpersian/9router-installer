# نصب‌کننده Docker برای 9Router

فارسی | [English](README.md)

اسکریپت نصب و مدیریت یک‌خطی برای اجرای [9Router](https://github.com/decolua/9router) با Docker روی Debian و Ubuntu.

## امکانات

- نصب خودکار Docker در صورت نصب نبودن
- استفاده از image پروژه: `decolua/9router:latest`
- اجرای 9Router روی پورت `20128`
- نگهداری دائمی داده‌ها در `/opt/9router/data`
- ساخت خودکار secretهای تصادفی و رمز اولیه
- اجرای خودکار 9Router بعد از reboot سرور
- بررسی خودکار آپدیت Docker image هر روز حوالی ساعت `04:30`
- recreate کردن کانتینر فقط در صورت وجود image جدید
- حفظ data و configuration هنگام آپدیت
- مدیریت خودکار CLI Token موردنیاز مسیرهای محافظت‌شده Tunnel
- نمایش وضعیت Tunnel و امکان فعال یا غیرفعال کردن آن از داخل اسکریپت
- باز کردن TCP پورت `20128` در UFW فقط در صورتی که UFW از قبل فعال باشد
- عدم دستکاری Apache، Nginx و پورت `443`
- داشتن گزینه‌های نصب، Repair، Update، Status، Tunnel، Log، Restart و حذف کامل

## نصب سریع

دستور زیر را با کاربر `root` اجرا کنید:

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

بعد از اجرا، منوی مدیریت نمایش داده می‌شود.

برای نصب یا Repair مستقیم بدون ورود به منو:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh) install
```

## منوی مدیریت

هر زمان برای باز کردن منو کافی است دوباره این دستور را اجرا کنید:

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

گزینه‌های موجود:

```text
1) Install / Repair 9Router
2) Update now
3) Status
4) Tunnel status
5) Enable Tunnel
6) Disable Tunnel
7) Show logs
8) Restart 9Router
9) Uninstall completely
0) Exit
```

### نصب / Repair

وابستگی‌های لازم را بررسی و در صورت نیاز نصب می‌کند، اگر configuration قبلی وجود نداشته باشد آن را می‌سازد، آخرین image را دریافت می‌کند و کانتینر `9router` را با حفظ داده‌های `/opt/9router/data` اجرا یا بازسازی می‌کند.

### آپدیت فوری

آخرین نسخه `decolua/9router:latest` را دریافت می‌کند. فقط اگر image جدید باشد کانتینر recreate می‌شود.

### وضعیت

وضعیت کانتینر Docker را نمایش می‌دهد و health endpoint محلی 9Router را بررسی می‌کند.

## Tunnel

اسکریپت برای Tunnel سه قابلیت دارد:

- مشاهده وضعیت Tunnel
- فعال کردن Tunnel
- غیرفعال کردن Tunnel

بعضی مسیرهای Tunnel در 9Router ممکن است به CLI Token محلی نیاز داشته باشند. اسکریپت این Token را از اطلاعات محلی نصب 9Router محاسبه کرده و درخواست را مستقیماً به API محلی ارسال می‌کند؛ بنابراین قرار نیست Token را دستی در Dashboard کپی کنید.

بعد از نصب نیز اسکریپت از شما می‌پرسد که آیا می‌خواهید Tunnel را همان لحظه فعال کنید یا خیر.

اگر فعال‌سازی Tunnel ناموفق بود، از گزینه‌های **Tunnel status** و **Show logs** برای بررسی استفاده کنید.

## دسترسی به 9Router

بعد از نصب:

```text
http://IP-SERVER:20128
```

آدرس پایه API سازگار با OpenAI:

```text
http://IP-SERVER:20128/v1
```

رمز اولیه‌ای که به‌صورت خودکار ساخته می‌شود در پایان نصب نمایش داده خواهد شد. آن را در جای امن نگه دارید و در صورت پشتیبانی نسخه نصب‌شده، از داخل Dashboard تغییر دهید.

## آپدیت خودکار

یک systemd timer هر روز حوالی ساعت `04:30` وجود نسخه جدید را بررسی می‌کند. برای جلوگیری از اجرای هم‌زمان روی تعداد زیادی سرور، تا ۱۰ دقیقه تأخیر تصادفی نیز دارد.

بررسی وضعیت timer:

```bash
systemctl status 9router-update.timer
```

مشاهده لاگ سرویس آپدیت:

```bash
journalctl -u 9router-update.service
```

یا:

```bash
cat /opt/9router/update.log
```

اجرای مستقیم updater:

```bash
/opt/9router/update.sh
```

همچنین از داخل منو می‌توانید گزینه **Update now** را انتخاب کنید.

## فایل‌ها

```text
/opt/9router/
├── .env
├── data/
├── update.sh
└── update.log
```

فایل `.env` با سطح دسترسی محدود `600` ساخته می‌شود و داده‌های دائمی 9Router خارج از کانتینر نگهداری می‌شوند.

## لاگ و Restart

از داخل منوی مدیریت می‌توانید Logها را ببینید یا سرویس را Restart کنید.

دستورهای دستی:

```bash
docker logs -f 9router
docker restart 9router
```

## حذف کامل

از منو گزینه زیر را انتخاب کنید:

```text
9) Uninstall completely
```

اسکریپت قبل از حذف از شما تأیید می‌گیرد و سپس موارد زیر را حذف می‌کند:

- کانتینر Docker با نام `9router`
- Docker image مربوط به 9Router
- systemd service و timer مربوط به آپدیت خودکار
- مسیر `/opt/9router` شامل data و configuration دائمی

خود Docker از روی سرور حذف نمی‌شود.

> ⚠️ هشدار: حذف کامل باعث پاک شدن دائمی اطلاعات محلی 9Router می‌شود.

## پورت 443 و سرویس‌های موجود

این installer عمداً از TCP پورت `443` استفاده یا آن را تغییر نمی‌دهد. بنابراین سرویس‌های فعلی مانند Apache، Nginx یا سایر سرویس‌های HTTPS دست‌نخورده باقی می‌مانند.

## امنیت

طبق تنظیمات installer، پورت `20128` توسط Docker منتشر می‌شود. اگر سرور از اینترنت عمومی قابل دسترسی است، در صورت نیاز دسترسی این پورت را با firewall یا security group محدود کنید و احراز هویت 9Router را فعال نگه دارید.

اتوماسیون Tunnel فقط CLI Token محلی را برای درخواست‌هایی که از خود سرور به API محلی 9Router ارسال می‌شوند استفاده می‌کند. `cli-secret` یا Token را در اختیار دیگران قرار ندهید.

## توضیح

این repository یک installer و ابزار مدیریتی مستقل است و بخشی از پروژه اصلی 9Router محسوب نمی‌شود. خود [9Router](https://github.com/decolua/9router) و Docker image آن توسط توسعه‌دهندگان پروژه upstream نگهداری می‌شوند.
