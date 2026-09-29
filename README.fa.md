# نصب‌کننده npm برای 9Router

[English](README.md) | فارسی

اسکریپت نصب و آپدیت یک‌خطی [9Router](https://github.com/decolua/9router) روی Ubuntu/Debian.

## امکانات

- نصب Node.js 22، Git، ابزارهای Build و PM2 در صورت نیاز
- اجرای مستقیم 9Router از سورس upstream با npm و PM2
- اجرای سرویس روی پورت **20128** و آدرس **0.0.0.0**
- در اولین اجرا می‌پرسد دامنه دارید یا نه؛ در غیر این صورت IPv4 عمومی سرور را پیدا می‌کند
- IPv6 برای URL عمومی استفاده نمی‌شود
- در اولین اجرا رمز Dashboard را می‌پرسد
- با زدن Enter بدون وارد کردن رمز، یک رمز ساده و نسبتاً امن مثل `9Router@a1b2c3d4e5` می‌سازد و نمایش می‌دهد
- در اجراهای بعدی رمز موجود حفظ می‌شود و رمز جدید درخواست یا تولید نمی‌شود
- نصب‌های قدیمی با رمز خالی یا IPv6 اشتباه را تعمیر می‌کند
- ورودی‌ها از `/dev/tty` گرفته می‌شوند و بنابراین با `curl ... | bash` هم درست کار می‌کند
- اگر مجموع Swap کمتر از ۲ گیگ باشد، هنگام نصب و Build یک Swap موقت ۲ گیگ ساخته می‌شود
- ابزارهای رایج Firewall را تشخیص می‌دهد و فقط هشدار می‌دهد؛ هیچ Rule یا پورتی را تغییر نمی‌دهد
- منوی Status، Logs، Restart و Uninstall دارد
- اگر `/opt/9router` از قبل وجود داشته باشد، به خطای `destination path ... already exists` نمی‌خورد

## نصب

با root اجرا کنید:

~~~bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash
~~~

بعد از اجرا یک منوی شماره‌ای نمایش داده می‌شود.

## منو

~~~text
1) Install / Update 9Router
2) Status
3) Show logs
4) Restart 9Router
5) Uninstall 9Router
0) Exit
~~~

## نصب اول

### آدرس

اسکریپت می‌پرسد:

~~~text
Do you have a domain? (y/n):
~~~

با انتخاب `n`، IPv4 عمومی سرور خودکار پیدا می‌شود:

~~~text
http://SERVER_IPV4:20128
~~~

با انتخاب `y`، دامنه را وارد می‌کنید:

~~~text
http://DOMAIN:20128
~~~

این installer خودش HTTPS، Nginx، Apache یا Reverse Proxy را تنظیم نمی‌کند.

### رمز Dashboard

در اولین نصب:

~~~text
Choose dashboard password (Enter = generate):
~~~

می‌توانید رمز دلخواه وارد کنید یا فقط Enter بزنید تا رمز خودکار ساخته شود. رمز دقیق تولیدشده نمایش داده می‌شود.

در تمام اجراهای بعدی رمز موجود حفظ می‌شود و دوباره تولید یا جایگزین نمی‌شود.

## آپدیت

همان دستور نصب را دوباره اجرا کنید و گزینه زیر را بزنید:

~~~text
1) Install / Update 9Router
~~~

اسکریپت سورس upstream را به‌روز می‌کند، وابستگی‌ها را نصب می‌کند، Build را انجام می‌دهد و سرویس PM2 را Restart می‌کند. فایل `.env` حفظ می‌شود.

## حذف

برای حذف 9Router:

~~~bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash -s -- uninstall
~~~

یا از منوی اصلی گزینه **5** را انتخاب کنید.

برای حذف باید دقیقاً `REMOVE` را وارد کنید. موارد زیر حذف می‌شوند:

~~~text
/opt/9router
/var/lib/9router
~~~

Node.js، npm، PM2 و Git حذف نمی‌شوند و Firewall نیز تغییر نمی‌کند.

## دستورات کاربردی

~~~bash
pm2 status
pm2 logs 9router
pm2 restart 9router
~~~

## مسیر فایل‌ها

~~~text
/opt/9router/.env
/opt/9router/          # سورس 9Router
/var/lib/9router/      # داده‌های دائمی برنامه
~~~

سطح دسترسی `.env` برابر **600** است.

## Firewall

installer هیچ پورت یا Rule فایروال را باز یا تغییر نمی‌دهد.

اگر UFW، firewalld یا nftables نصب باشد، فقط هشدار نمایش داده می‌شود. ممکن است Firewall یا Security Group جداگانه‌ای در پنل سرویس‌دهنده VPS نیز روی TCP **20128** محدودیت ایجاد کند.

## توضیح

این repository یک installer مستقل برای 9Router است و خود پروژه 9Router توسط توسعه‌دهندگان upstream نگهداری می‌شود.
