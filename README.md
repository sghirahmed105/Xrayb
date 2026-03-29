# XRAY Cloud Run (VLESS / VMESS / TROJAN)

Deploy Xray-core on Google Cloud Run with WebSocket + TLS.

## ✨ المميزات

- VLESS / VMESS / TROJAN
- UUID / Password مخصص
- WebSocket Path مخصص
- Domain مخصص (اختياري)
- Termux مدعوم
- جميع معاملات الأداء اختيارية قابلة للتخصيص

## 📋 المتطلبات

- حساب Google Cloud
- gcloud CLI مثبت
- مشروع GCP فعال

## 🚀 طرق التوزيع

### الطريقة 1: البرنامج التفاعلي (الأبسط)

```bash
git clone https://github.com/wwen3713-spec/wwen3713.git
cd wwen3713
chmod +x install.sh
./install.sh
# سيطلب منك الإعدادات تدريجياً - يمكنك الضغط Enter للتخطي
```

#### مع Telegram Bot (اختياري)

```bash
git clone https://github.com/wwen3713-spec/wwen3713.git
cd wwen3713
chmod +x install.sh

# مع Token و Chat ID
BOT_TOKEN="your_telegram_bot_token" \
CHAT_ID="your_telegram_chat_id" \
./install.sh
```

**الحصول على البيانات:**

- **BOT_TOKEN**: أنشئ bot على [@BotFather](https://t.me/BotFather) واحصل على الـ token
- **CHAT_ID**: أرسل رسالة لـ [@userinfobot](https://t.me/userinfobot) واحصل على Chat ID

### الطريقة 2: البرنامج المرن مع Presets (موصى به) ⭐

```bash
chmod +x deploy-custom.sh
./deploy-custom.sh

# سيظهر لك:
# ⚡ Quick Start with Presets:
# 1) production (2048MB, 1 CPU, 16 instances, 1000 concurrency)
# 2) budget (2048MB, 2 CPU, 8 instances, 1000 concurrency)
# 3) custom (enter all settings manually)
```

### الطريقة 3: متغيرات البيئة

```bash
PROTO=vless WSPATH=/ws SERVICE=xray REGION=us-central1 \
MEMORY=512 CPU=1 MAX_INSTANCES=10 CONCURRENCY=100 \
./install.sh
```

### الطريقة 4: gcloud مباشرة

```bash
gcloud run deploy xray \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1
```
