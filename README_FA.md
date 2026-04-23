# Shade

یک اپ سبک macOS برای عبور ترافیک از طریق Google Apps Script relay با رابط کاربری ساده.

![Shade App Dashboard](macos-app/sc/app-dashboard.png)


[English](README.md) | فارسی

## این برنامه چه کاری انجام می‌دهد

- یک پراکسی محلی HTTP و SOCKS5 اجرا می‌کند.
- از طریق پروفایل‌های Google Apps Script relay متصل می‌شود.
- با یک کلیک Start و Stop می‌شود.
- با یک Toggle، پراکسی سیستم macOS را Set یا Clear می‌کند.
- تست اتصال داخلی (سبک ping/latency) دارد.
- مدیریت ساخت و نصب گواهی را انجام می‌دهد تا HTTPS با تنظیم دستی کمتر کار کند.

## امکانات اصلی

- چند پروفایل: ذخیره و جابه‌جایی بین Script ID و Auth Key های مختلف.
- کنترل ساده: دکمه‌های Start، Stop، Test و Set System Proxy در داشبورد.
- وضعیت زنده: نمایش واضح Running/Stopped و پورت‌های فعال.
- قابل استفاده هم برای پراکسی برنامه/مرورگر و هم برای پراکسی کل سیستم.

## شروع سریع

1. یک یا چند پروفایل اضافه کنید (Script ID و Auth Key).
2. یک پروفایل انتخاب کنید.
3. روی Start بزنید.
4. در صورت نیاز Set as system proxy را فعال کنید.
5. برای بررسی سریع اتصال، Test را اجرا کنید.

## حمایت مالی

- TON: UQCriHkMUa6h9oN059tyC23T13OsQhGGM3hUS2S4IYRBZgvx
- USDT (BEP20): 0x71F41696c60C4693305e67eE3Baa650a4E3dA796
- TRX (TRON): TFrCzU7bDey9WSh3fhqCBqhaiMzr8VhcUV

```
مرورگر -> پراکسی محلی -> Google/CDN -> رله شما -> سایت مقصد
           |
           +-> فیلتر فقط google.com را می‌بیند
```

مرورگر، درخواست‌ها را به پراکسی محلی می‌فرستد. پراکسی این درخواست‌ها را از مسیر Google عبور می‌دهد تا برای فیلتر شبیه ترافیک عادی به نظر برسد. سپس رله‌ای که شما deploy کرده‌اید، سایت اصلی را دریافت می‌کند و پاسخ را برمی‌گرداند.

---

## راه‌اندازی مرحله‌به‌مرحله

### مرحله 1: دریافت پروژه

```bash
git clone -b python_testing https://github.com/masterking32/MasterHttpRelayVPN.git
cd MasterHttpRelayVPN
pip install -r requirements.txt
```

> **دسترسی به PyPI ندارید؟** از این mirror استفاده کنید:
> ```bash
> pip install -r requirements.txt -i https://mirror-pypi.runflare.com/simple/ --trusted-host mirror-pypi.runflare.com
> ```

اگر نخواستید با Git کار کنید، می‌توانید فایل ZIP پروژه را از GitHub دانلود و extract کنید.

### مرحله 2: راه‌اندازی رله Google با `Code.gs`

این بخش همان رله‌ای است که روی سرورهای Google اجرا می‌شود و سایت‌ها را برای شما دریافت می‌کند.

1. وارد [Google Apps Script](https://script.google.com/) شوید.
2. روی **New project** کلیک کنید.
3. کد پیش‌فرض را کامل حذف کنید.
4. فایل `apps_script/Code.gs` همین پروژه را باز کنید، همه محتوای آن را کپی کنید و داخل Apps Script قرار دهید.
5. این خط را به یک رمز دلخواه و امن تغییر دهید:
   ```javascript
   const AUTH_KEY = "your-secret-password-here";
   ```
6. روی **Deploy -> New deployment** کلیک کنید.
7. نوع deployment را **Web app** بگذارید.
8. این تنظیمات را انتخاب کنید:
   - **Execute as:** Me
   - **Who has access:** Anyone
9. روی **Deploy** بزنید.
10. مقدار **Deployment ID** را کپی کنید. در مرحله بعد به آن نیاز دارید.

نکته: مقداری که برای `AUTH_KEY` می‌گذارید باید دقیقا با `auth_key` در فایل `config.json` یکی باشد.

### مرحله 3: تنظیم `config.json`

ابتدا فایل نمونه را کپی کنید:

```bash
cp config.example.json config.json
```

در ویندوز می‌توانید فایل را دستی کپی و rename کنید.

سپس `config.json` را باز کنید و مقادیر را وارد کنید:

```json
{
  "mode": "apps_script",
  "google_ip": "216.239.38.120",
  "front_domain": "www.google.com",
  "script_id": "PASTE_YOUR_DEPLOYMENT_ID_HERE",
  "auth_key": "your-secret-password-here",
  "listen_host": "127.0.0.1",
  "listen_port": 8085,
  "socks5_enabled": true,
  "socks5_port": 1080,
  "log_level": "INFO",
  "verify_ssl": true
}
```

- `script_id` : همان Deployment ID مرحله 2
- `auth_key` : همان رمزی که در `Code.gs` گذاشته‌اید

### مرحله 4: اجرا

```bash
python3 main.py
```

اگر همه‌چیز درست باشد، پراکسی HTTP روی `127.0.0.1:8085` و SOCKS5 روی `127.0.0.1:1080` بالا می‌آید.

### مرحله 5: تنظیم مرورگر

مرورگر را روی این پراکسی تنظیم کنید:

- **Proxy Address:** `127.0.0.1`
- **Proxy Port:** `8085`
- **Type:** HTTP
- **SOCKS5 Port (اختیاری):** `1080`

نمونه تنظیم مرورگرها:

- **Firefox:** Settings -> General -> Network Settings -> Manual proxy
- **Chrome / Edge:** از تنظیمات پراکسی سیستم استفاده می‌کنند
- یا از افزونه‌هایی مثل FoxyProxy استفاده کنید

### مرحله 6: نصب گواهی CA برای HTTPS

در حالت `apps_script`، برنامه برای مدیریت HTTPS یک گواهی محلی می‌سازد. اگر آن را نصب نکنید، مرورگر برای سایت‌ها خطای امنیتی می‌دهد.

فایل گواهی بعد از اولین اجرا در این مسیر ساخته می‌شود:

`ca/ca.crt`

#### ویندوز
1. روی `ca/ca.crt` دوبار کلیک کنید.
2. گزینه **Install Certificate** را بزنید.
3. گزینه **Current User** را انتخاب کنید.
4. گزینه **Place all certificates in the following store** را بزنید.
5. از بخش **Browse**، گزینه **Trusted Root Certification Authorities** را انتخاب کنید.
6. مراحل را تا پایان ادامه دهید.
7. مرورگر را یک بار ببندید و دوباره باز کنید.

#### Firefox
Firefox معمولا certificate store جداگانه دارد:

1. به **Settings -> Privacy & Security -> Certificates** بروید.
2. روی **View Certificates** کلیک کنید.
3. در تب **Authorities**، روی **Import** بزنید.
4. فایل `ca/ca.crt` را انتخاب کنید.
5. گزینه **Trust this CA to identify websites** را فعال کنید.

> **نصب خودکار هنگام اجرا:** در حالت `apps_script`، برنامه به صورت خودکار وضعیت اعتماد گواهی CA را بررسی کرده و در صورت نیاز نصب می‌کند. در صورت موفقیت پیام تأیید در لاگ نمایش داده می‌شود. اگر نصب خودکار ناموفق بود، می‌توانید دستور `python main.py --install-cert` را اجرا کنید.

نکته امنیتی: پوشه `ca/` را با کسی به اشتراک نگذارید. اگر خواستید از اول گواهی جدید بسازید، این پوشه را حذف کنید تا دوباره ساخته شود.


---

## حالت‌های موجود

این پروژه کاملاً روی حالت **Apps Script** تمرکز دارد. فقط به یک اکانت رایگان Google نیاز دارید — بدون VPS، بدون سرور، بدون Cloudflare. همه‌چیز برای همین حالت تنظیم شده است.

---

## اشتراک‌گذاری در شبکه محلی (اختیاری)

به‌طور پیش‌فرض، پروکسی فقط به `127.0.0.1` (localhost) گوش می‌دهد، به این معنی که فقط کامپیوتر شما می‌تواند از آن استفاده کند. برای اینکه سایر دستگاه‌های موجود در شبکه محلی (LAN) شما بتوانند از این پروکسی استفاده کنند:

۱. در فایل `config.json` خود، مقدار `"lan_sharing"` را `true` قرار دهید.
۲. پروکسی به طور خودکار به تمام رابط‌های شبکه (`0.0.0.0`) گوش خواهد داد.
۳. در لاگ راه‌اندازی، آدرس‌های IP شبکه محلی شما که سایر دستگاه‌ها می‌توانند به آن متصل شوند، نمایش داده می‌شود.

**نمونه پیکربندی برای شبکه محلی:**
json
{
  "lan_sharing": true,
  "listen_host": "0.0.0.0",
  "listen_port": 8085
}

**هشدار امنیتی:** وقتی اشتراک‌گذاری در شبکه محلی فعال باشد، هر کسی در شبکه محلی شما می‌تواند از پروکسی شما استفاده کند. اطمینان حاصل کنید که شبکه شما مورد اعتماد است و اقدامات امنیتی بیشتری را در نظر بگیرید.

**در سایر دستگاه‌ها:** آن‌ها را طوری پیکربندی کنید که از آدرس IP کامپیوتر شما در شبکه محلی (که در لاگ راه‌اندازی نمایش داده می‌شود) و پورت 8085 به عنوان پروکسی HTTP استفاده کنند.

---

## تنظیمات اصلی

| تنظیم | توضیح |
|------|-------|
| `auth_key` | رمز مشترک بین کامپیوتر شما و رله |
| `script_id` | شناسه Deployment مربوط به Google Apps Script شما |
| `listen_host` | محل گوش دادن (`127.0.0.1` = فقط همین کامپیوتر، `0.0.0.0` = همه اینترفیس‌ها برای اشتراک‌گذاری LAN) |
| `listen_port` | پورتی که پروکسی روی آن اجرا می‌شود (پیش‌فرض: `8085`) |
| `lan_sharing` | فعال‌سازی اشتراک‌گذاری LAN تا دستگاه‌های دیگر در شبکه شما بتوانند از پروکسی استفاده کنند (به‌صورت پیش‌فرض `false`) |
| `log_level` | میزان جزئیات لاگ: `DEBUG`، `INFO`، `WARNING`، `ERROR` |

### تنظیمات پیشرفته

| تنظیم | مقدار پیش‌فرض | توضیح |
|------|---------------|-------|
| `google_ip` | `216.239.38.120` | IP مورد استفاده برای مسیر Google |
| `front_domain` | `www.google.com` | دامنه‌ای که فیلتر می‌بیند |
| `verify_ssl` | `true` | بررسی اعتبار TLS |
| `script_ids` | - | چند Deployment ID برای load balancing |
| `block_hosts` | `[]` | هاست‌هایی که هرگز نباید tunnel شوند (پاسخ 403). نام دقیق (`ads.example.com`) یا پسوند با نقطه‌ی ابتدایی (`.doubleclick.net`). |
| `bypass_hosts` | `["localhost", ".local", ".lan", ".home.arpa"]` | هاست‌هایی که مستقیم می‌روند (بدون MITM و بدون رله). برای منابع داخلی شبکه یا سایت‌هایی که با MITM مشکل دارند. |
| `direct_google_exclude` | مراجعه به [config.example.json](config.example.json) | اپ‌های Google که باید از مسیر MITM برای رله استفاده کنند به‌جای tunnel مستقیم. |

### وابستگی‌های اختیاری

همه وابستگی‌های [`requirements.txt`](requirements.txt) اختیاری هستند — در حالت پایه بدون هیچ‌کدام کار می‌کند، ولی با نصب آن‌ها امکانات بیشتری در دسترس است:

| بسته | کاربرد |
|------|---------|
| `cryptography` | رمزگشایی MITM برای HTTPS (در حالت `apps_script` لازم است) |
| `h2` | ارتباط HTTP/2 با رله Apps Script (به‌طور محسوسی سریع‌تر) |
| `brotli` | پشتیبانی از فشرده‌سازی `Content-Encoding: br` |
| `zstandard` | پشتیبانی از فشرده‌سازی `Content-Encoding: zstd` |
| `netifaces` | تشخیص بهتر اینترفیس‌های شبکه برای اشتراک‌گذاری LAN (در صورت نبود آن، حالت جایگزین در دسترس است) |

### استفاده از چند Script ID

اگر چند نسخه از `Code.gs` را deploy کنید، می‌توانید همه Deployment ID ها را در آرایه `script_ids` بگذارید:

```json
{
  "script_ids": [
    "DEPLOYMENT_ID_1",
    "DEPLOYMENT_ID_2",
    "DEPLOYMENT_ID_3"
  ]
}
```
> **نکته :** اگر از چندین دیپلویمنت آیدی استفاده میکنید توجه داشته باشید که auth_key های همه دیپلویمنت ها باید یکسان باشند.
---

## به‌روزرسانی `Code.gs`

اگر فایل `Code.gs` را تغییر دادید، باید دوباره **Deploy -> New deployment** بزنید و `script_id` جدید را داخل `config.json` قرار دهید. صرفا ذخیره کردن کد، نسخه فعال را عوض نمی‌کند.

---

## دستورهای اجرا

```bash
python3 main.py
python3 main.py -p 9090
python3 main.py --socks5-port 1081
python3 main.py --disable-socks5
python3 main.py --log-level DEBUG
python3 main.py -c /path/to/config.json
python3 main.py --install-cert        # نصب گواهی CA و خروج
python3 main.py --no-cert-check       # رد شدن از بررسی خودکار گواهی
```

> **نصب خودکار:** هنگام اجرا در حالت `apps_script`، برنامه به‌طور خودکار بررسی می‌کند که آیا گواهی CA قابل اعتماد است یا نه و در صورت نیاز آن را نصب می‌کند. اگر نصب خودکار ناموفق بود (مثلاً نیاز به دسترسی مدیر دارد)، می‌توانید دستور `python main.py --install-cert` را اجرا کنید یا مراحل مرحله ۶ را دنبال کنید.

---

## معماری

```
┌─────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────┐
│ Browser │────►│ Local Proxy  │────►│ CDN / Google │────►│  Relay   │──► Internet
│         │◄────│ (this tool)  │◄────│  (fronted)   │◄────│ Endpoint │◄──
└─────────┘     └──────────────┘     └─────────────┘     └──────────┘
```

---

## فایل‌های پروژه

```
MasterHttpRelayVPN/
├── main.py                    # نقطه شروع: پراکسی را راه‌اندازی می‌کند
├── config.example.json        # نمونه کانفیگ (به config.json کپی شود)
├── requirements.txt           # وابستگی‌های اختیاری پایتون
├── apps_script/
│   └── Code.gs                # اسکریپت رله روی Google Apps Script
├── ca/                        # گواهی MITM (هرگز به اشتراک نگذارید)
│   ├── ca.crt
│   └── ca.key
└── src/                       # پیاده‌سازی پراکسی
    ├── proxy_server.py        # دریافت CONNECT و SOCKS5
    ├── domain_fronter.py      # کلاینت رله Apps Script (fronted از طریق Google)
    ├── h2_transport.py        # ارتباط HTTP/2 (اختیاری)
    ├── mitm.py                # ساخت و مدیریت گواهی‌ها
    ├── cert_installer.py      # نصب خودکار CA در ویندوز/مک/لینوکس + فایرفاکس
    ├── codec.py               # رمزگشای Content-Encoding (gzip/deflate/br/zstd)
    ├── constants.py           # مقادیر پیش‌فرض قابل تنظیم
    └── logging_utils.py       # فرمت‌دهنده‌ی لاگ رنگی و منظم
```

---

## رفع مشکل

| مشکل | راه‌حل |
|------|--------|
| `Config not found` | فایل `config.example.json` را به `config.json` کپی کنید |
| خطای certificate در مرورگر | گواهی CA را نصب کنید (مرحله ۶) |
| تلگرام کار می‌کند ولی مرورگر سایت‌ها را باز نمی‌کند | تقریباً مطمئناً گواهی CA نصب نشده. مرحله ۶ را دنبال کنید، سپس مرورگر را **کاملاً ببندید و دوباره باز کنید** (برای Chrome/Edge مطمئن شوید هیچ پروسه Chrome در پس‌زمینه باز نیست). |
| گواهی نصب شد ولی مرورگر هنوز خطا می‌دهد | Chrome و Edge گواهی‌ها را cache می‌کنند — باید مرورگر را **کاملاً ببندید** (Task Manager یا system tray را چک کنید) و دوباره باز کنید. Firefox نیاز به import جداگانه دارد (بخش Firefox در مرحله ۶). |
| خطای `unauthorized` | مقدار `auth_key` و `AUTH_KEY` باید یکسان باشند |
| timeout | IP دیگری برای Google امتحان کنید |
| سرعت کم | از چند `script_id` برای load balancing استفاده کنید |
| خطای `502 Bad JSON` | Google به‌جای JSON پاسخ HTML برگردانده (مثلاً صفحه quota یا 404). دلایل: `script_id` اشتباه، تجاوز از سهمیه روزانه Apps Script، یا عدم ایجاد deployment جدید پس از ویرایش `Code.gs`. `script_id` را بررسی کنید و یک **deployment جدید** بسازید. |
| تلگرام روی HTTP proxy کار می‌کند ولی روی SOCKS5 نه | **طبیعی است.** کلاینت SOCKS5 نام دامنه را روی سیستم خودش resolve می‌کند و مستقیم به IP وصل می‌شود، پس بایت‌های MTProto تلگرام به IP فیلترشده می‌رسد که نه می‌توانیم direct-tunnel کنیم و نه MITM. تلگرام را به‌جای SOCKS5 به صورت **HTTP proxy** (`127.0.0.1:8085`) تنظیم کنید — در این حالت نام دامنه ارسال می‌شود و پراکسی با SNI-rewrite از طریق Google عبور می‌دهد. |
| گوگل و یوتیوب باز می‌شوند ولی ویدیوهای یوتیوب پخش نمی‌شوند و سایت‌های دیگر باز نمی‌شوند | اتصال به `script.google.com` با موفقیت برقرار نشده. احتمالاً مشکل از deployment فایل `Code.gs` روی Google Apps Script است یا سهمیه روزانه اجرا تمام شده. یک deployment جدید از `Code.gs` بسازید و `script_id` را بررسی کنید، یا منتظر بمانید تا سهمیه reset شود (نیمه‌شب به وقت Pacific / ۱۰:۳۰ ظهر به وقت ایران). |

---

## نکات امنیتی

- فایل `config.json` را با کسی به اشتراک نگذارید.
- مقدار پیش‌فرض `AUTH_KEY` را قبل از deploy عوض کنید.
- پوشه `ca/` را منتشر نکنید.
- بهتر است `listen_host` روی `127.0.0.1` بماند.
- هر دیپلویمنت روی گوگل اسکریپت دارای محدودیت 20,000 درخواست در هر 24 ساعت است
---

## License

MIT
