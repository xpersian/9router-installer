# نصب‌کننده 9Router

نصب ساده Docker برای [9Router](https://github.com/decolua/9router).

## نصب

با root اجرا کنید:

```bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash
```

اسکریپت در صورت نیاز Docker را نصب می‌کند، `decolua/9router:latest` را اجرا می‌کند، پورت `20128` را روی `0.0.0.0` در دسترس می‌گذارد، IPv4 عمومی سرور را پیدا می‌کند و بعد از Reboot خودکار اجرا می‌شود.

در اولین اجرا رمز Dashboard را می‌پرسد. با Enter خالی یک رمز خودکار می‌سازد و نمایش می‌دهد. در اجراهای بعدی رمز موجود حفظ می‌شود.

## منو

```text
1) Install / Update 9Router
2) Status
3) Restart 9Router
4) Uninstall 9Router
0) Exit
```

## آپدیت خودکار

یک systemd timer هر روز ساعت 04:30 با حداکثر 10 دقیقه تأخیر تصادفی، آخرین Docker Image را بررسی می‌کند. فقط در صورت وجود Image جدید، کانتینر دوباره ساخته می‌شود.

آپدیت دستی:

```bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash -s -- update
```

## دسترسی

```text
http://SERVER_IPV4:20128/dashboard
http://SERVER_IPV4:20128/v1
```

installer هیچ Rule یا پورتی را در Firewall تغییر نمی‌دهد. اگر Firewall نصب باشد فقط هشدار نمایش می‌دهد.

## حذف

گزینه 4 را انتخاب کنید یا:

```bash
curl -fsSL https://github.com/xpersian/9router-installer/raw/refs/heads/main/9router.sh | bash -s -- uninstall
```

9Router، Docker Image، تنظیمات و داده‌های آن حذف می‌شوند؛ خود Docker باقی می‌ماند.
