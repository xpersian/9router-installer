# نصب‌کننده Docker برای 9Router

[English](README.md) | فارسی

نصب سریع 9Router روی VPS با استفاده از Docker Image منتشرشده پروژه اصلی.

## امکانات

- استفاده از Image آماده decolua/9router:latest
- بدون نصب Node.js و بدون npm build روی VPS
- نگهداری Data در /opt/9router/data
- اجرای خودکار بعد از Reboot با restart policy داکر
- اجرای سرویس روی پورت 20128
- در صورت نداشتن دامنه، تشخیص خودکار IPv4 عمومی
- دریافت رمز Dashboard در اولین نصب
- با Enter خالی، تولید و نمایش یک رمز ساده و نسبتاً امن
- حفظ رمز قبلی در اجراهای بعدی
- مدیریت Cloudflare Quick Tunnel از منو: وضعیت، فعال، غیرفعال و Refresh URL
- حفظ وضعیت فعال بودن Tunnel توسط خود 9Router و امکان Resume بعد از Restart
- آپدیت خودکار روزانه با systemd timer
- فقط تشخیص Firewall و نمایش هشدار؛ هیچ Ruleی تغییر نمی‌کند
- حذف کامل 9Router با تأیید

## نصب

با root اجرا کنید:

~~~bash
curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh' | bash
~~~

بعد از اجرا منوی شماره‌ای نمایش داده می‌شود.

## منو

~~~text
1) Install / Update 9Router
2) Update now
3) Status
4) Tunnel status
5) Enable Tunnel
6) Disable Tunnel
7) Refresh Tunnel URL
8) Show logs
9) Restart 9Router
10) Uninstall 9Router
0) Exit
~~~

## نصب اول

### آدرس

اسکریپت می‌پرسد دامنه دارید یا نه.

بدون دامنه، IPv4 عمومی VPS را پیدا می‌کند:

~~~text
http://SERVER_IPV4:20128
~~~

با دامنه:

~~~text
http://DOMAIN:20128
~~~

این installer خودش HTTPS، Nginx، Apache یا Reverse Proxy را تنظیم نمی‌کند.

### رمز Dashboard

در نصب اول:

~~~text
Dashboard password (Enter = auto-generate):
~~~

می‌توانید رمز دلخواه وارد کنید یا فقط Enter بزنید.

رمز خودکار مشابه این خواهد بود:

~~~text
9Router@03cb644633
~~~

رمز دقیق تولیدشده نمایش داده شده و در /opt/9router/.env ذخیره می‌شود.

در اجراهای بعدی رمز موجود حفظ می‌شود و دوباره تولید نمی‌شود.

## Docker

کانتینر با تنظیماتی مشابه این اجرا می‌شود:

~~~bash
docker run -d \
  --name 9router \
  --restart unless-stopped \
  -p 0.0.0.0:20128:20128 \
  --env-file /opt/9router/.env \
  -v /opt/9router/data:/app/data \
  decolua/9router:latest
~~~

Image اصلی PORT=20128، HOSTNAME=0.0.0.0 و DATA_DIR=/app/data را استفاده می‌کند.

## تنظیمات محیطی

متغیرهای اصلی upstream که installer تنظیم می‌کند:

~~~text
JWT_SECRET
INITIAL_PASSWORD
DATA_DIR=/app/data
PORT=20128
HOSTNAME=0.0.0.0
NODE_ENV=production
BASE_URL
CLOUD_URL=https://9router.com
NEXT_PUBLIC_BASE_URL
NEXT_PUBLIC_CLOUD_URL=https://9router.com
API_KEY_SECRET
MACHINE_ID_SALT
ENABLE_REQUEST_LOGS=false
AUTH_COOKIE_SECURE=false
REQUIRE_API_KEY=false
~~~

## Tunnel

منو این امکانات را دارد:

~~~text
Tunnel status
Enable Tunnel
Disable Tunnel
Refresh Tunnel URL
~~~

اسکریپت برای ارتباط با API داخلی Tunnel از CLI Token محلی 9Router استفاده می‌کند و خود Token را نمایش نمی‌دهد.

وقتی Tunnel فعال شود، وضعیت آن در 9Router ذخیره می‌شود و Startup پروژه اصلی می‌تواند پس از Restart کانتینر Tunnel را دوباره Resume کند.

Refresh یعنی Tunnel غیرفعال و دوباره فعال می‌شود و ممکن است URL عمومی جدیدی ایجاد شود.

## آپدیت خودکار

یک systemd timer با نام 9router-update.timer ساخته می‌شود.

این Timer تقریباً هر روز ساعت 04:30 با یک تأخیر تصادفی کوتاه Image decolua/9router:latest را بررسی می‌کند.

کانتینر فقط در صورت وجود Image جدید یا نبودن/متوقف بودن کانتینر Recreate می‌شود. Data و .env حفظ می‌شوند.

بررسی Timer:

~~~bash
systemctl status 9router-update.timer
~~~

آپدیت دستی:

~~~bash
bash <(curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh') update
~~~

## نصب‌های قبلی

فایل /opt/9router/.env موجود حفظ می‌شود.

اگر Data قبلی در /var/lib/9router وجود داشته باشد و /opt/9router/data خالی باشد، installer آن را به مسیر Data جدید Docker کپی می‌کند.

کانتینر قبلی با نام 9router با Image منتشرشده جایگزین می‌شود و Data روی Host حفظ می‌شود.

## Firewall

هیچ Rule یا پورتی باز یا تغییر داده نمی‌شود.

اگر UFW، firewalld یا nftables نصب باشد، فقط هشدار نمایش داده می‌شود.

ممکن است Firewall یا Security Group جداگانه در پنل VPS روی TCP پورت 20128 محدودیت ایجاد کند.

## حذف کامل

~~~bash
bash <(curl -fsSL https://github.com/xpersian/9router-installer/archive/refs/heads/main.tar.gz | tar -xzO --wildcards '*/9router.sh') uninstall
~~~

برای تأیید باید REMOVE را وارد کنید.

موارد زیر حذف می‌شوند:

~~~text
/opt/9router
9router-update.timer
9router-update.service
/usr/local/sbin/9router-update
~~~

خود Docker حذف نمی‌شود.

## دستورات کاربردی

~~~bash
docker ps
docker logs -f 9router
docker restart 9router
systemctl status 9router-update.timer
~~~

## پروژه اصلی

9Router:
https://github.com/decolua/9router

Docker Image:
https://hub.docker.com/r/decolua/9router

این repository یک installer مستقل برای پروژه اصلی است.
