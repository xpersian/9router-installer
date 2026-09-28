# نصب‌کننده npm برای 9Router

[English](README.md) | فارسی

اسکریپت نصب و آپدیت یک‌خطی برای [9Router](https://github.com/decolua/9router) از سورس روی Ubuntu/Debian.

## امکانات

- نصب Node.js 22، Git، ابزارهای Build و PM2 در صورت نیاز
- Clone و Update سورس رسمی 9Router
- Build و اجرای مستقیم 9Router با npm و PM2
- اجرای سرویس روی پورت 20128 و آدرس 0.0.0.0
- ساخت خودکار Secretهای تصادفی برای JWT و API
- انتخاب رمز Dashboard به‌صورت تعاملی با تأیید دوباره
- سازگار با اجرای `curl ... | bash` چون ورودی‌های تعاملی را مستقیماً از `/dev/tty` می‌گیرد
- پرسیدن اینکه دامنه می‌خواهید یا نه؛ در غیر این صورت IPv4 عمومی سرور را پیدا می‌کند
- تعمیر نصب‌های قبلی که به‌اشتباه IPv6 را در URL ذخیره کرده‌اند
- حفظ `.env` و داده‌های قبلی هنگام آپدیت
- باز کردن TCP پورت 20128 در UFW فقط اگر UFW از قبل فعال باشد
- بررسی اینکه 9Router روی پورت موردنظر Listen است و Dashboard محلی پاسخ می‌دهد
- ساخت Swap موقت هنگام Build اگر مجموع Swap کمتر از 2 گیگابایت باشد

## نصب یا آپدیت

به‌عنوان root اجرا کنید:

```bash
curl -fsSL https://raw.githubusercontent.com/xpersian/9router-installer/main/install-9router.sh | bash
```

در اولین اجرا اسکریپت از شما دامنه و رمز Dashboard را می‌پرسد.

اگر دامنه ندارید:

```text
http://SERVER_IPV4:20128
```

اگر دامنه وارد کنید:

```text
http://DOMAIN:20128
```

این installer خودش HTTPS، Nginx، Apache یا Reverse Proxy را تنظیم نمی‌کند.

برای آپدیت 9Router کافی است همان دستور را دوباره اجرا کنید. فایل `.env` و داده‌های برنامه حفظ می‌شوند.

## Dashboard

آدرس:

```text
http://SERVER_IPV4:20128/dashboard
```

یا آدرس دامنه‌ای که هنگام نصب تنظیم کرده‌اید.

رمز ورود، همان رمزی است که در اولین نصب انتخاب کرده‌اید. اگر نصب قدیمی دارای `INITIAL_PASSWORD` خالی باشد، اسکریپت دوباره از شما رمز می‌گیرد.

## دستورات کاربردی

```bash
pm2 status
pm2 logs 9router
pm2 restart 9router
```

## مسیر فایل‌ها

```text
/opt/9router/.env
/opt/9router/        # سورس برنامه
/var/lib/9router/    # داده‌های دائمی برنامه
```

سطح دسترسی فایل `.env` روی 600 تنظیم می‌شود.

## Firewall

اگر UFW فعال باشد، installer پورت TCP شماره 20128 را باز می‌کند.

ممکن است VPS شما یک Firewall یا Security Group جداگانه در پنل سرویس‌دهنده داشته باشد؛ در آن صورت برای دسترسی مستقیم از مرورگر باید TCP 20128 را آنجا هم باز کنید.

## توضیح

این repository یک installer مستقل برای 9Router است و خود پروژه 9Router توسط توسعه‌دهندگان upstream نگهداری می‌شود.
