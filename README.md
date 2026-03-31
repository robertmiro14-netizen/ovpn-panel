# ⚡ Vol OVPN Panel — OpenVPN

Автоматический установщик OpenVPN с веб-панелью управления для Ubuntu 20.04 / 22.04 / 24.04.

## ✨ Возможности

- 🔐 **Первый запуск** — установка пароля прямо в браузере (bcrypt)
- 🔒 **HTTPS** — самоподписанный SSL сертификат (10 лет)
- 📜 **PKI автоматически** — CA сертификат и сервер-сертификат создаются при установке
- 👥 **Управление клиентами** — создание и удаление (отзыв сертификата)
- 📥 **Скачать `.ovpn`** — готовый конфиг для любого устройства
- 🔄 **Auto-refresh** — список клиентов обновляется каждые 15 секунд

## 🚀 Установка

### 1. Подключитесь к серверу

```bash
ssh root@your-server-ip
```

### 2. Запустите одной командой

```bash
curl -fsSL https://raw.githubusercontent.com/robertmiro14-netizen/ovpn-panel/main/install_ovpn_panel.sh | bash
```

> Скрипт автоматически:
> - Установит Node.js 20 LTS (если нужно)
> - Установит Docker (если нужно)
> - Инициализирует PKI и создаст CA сертификат
> - Запустит **OpenVPN** в Docker
> - Сгенерирует **SSL сертификат** для HTTPS панели
> - Запустит **Vol OVPN Panel** как systemd-сервис (порт 51822)
> - Настроит UFW (порты 22/tcp, 1194/udp, 51822/tcp)

### 3. Откройте панель в браузере

```
https://YOUR_SERVER_IP:51822
```

> ⚠️ Браузер покажет предупреждение о сертификате — нажмите **«Продолжить»** (это нормально для self-signed cert).

При **первом входе** вам предложат установить пароль.

---

## 📱 Как добавить клиента

1. Войдите в панель → нажмите **«Новый клиент»**
2. Введите имя (только латиница, цифры, `_`, `-`)
3. Нажмите **«Создать»** (генерируется сертификат ~5-10 сек)
4. Нажмите **↓** для скачивания `.ovpn` файла

### Приложения OpenVPN:
| Платформа | Ссылка |
|-----------|--------|
| iOS | [App Store](https://apps.apple.com/app/openvpn-connect/id590379981) |
| Android | [Google Play](https://play.google.com/store/apps/details?id=net.openvpn.openvpn) |
| Windows | [Download](https://openvpn.net/community-downloads/) |
| macOS | [Tunnelblick](https://tunnelblick.net/downloads.html) |
| Linux | `sudo apt install openvpn` |

---

## ⚙️ Технические детали

| Параметр | Значение |
|----------|----------|
| OpenVPN порт | `1194/udp` |
| Веб-панель порт | `51822/tcp` |
| Протокол панели | `HTTPS` (self-signed) |
| Данные OpenVPN | `/opt/ovpn-data/` |
| PKI / CA | `/opt/ovpn-data/pki/` |
| Панель расположена | `/opt/vol-ovpn-panel/` |
| SSL сертификат | `/opt/vol-ovpn-panel/cert.crt` |
| Файл пароля | `/opt/vol-ovpn-panel/.password` |

---

## 🛠️ Управление сервисами

```bash
# Статус
systemctl status vol-ovpn-panel
docker ps | grep vol-openvpn

# Логи в реальном времени
journalctl -u vol-ovpn-panel -f
docker logs -f vol-openvpn

# Перезапуск
systemctl restart vol-ovpn-panel
docker restart vol-openvpn
```

---

## 🔄 Сброс пароля

```bash
rm /opt/vol-ovpn-panel/.password
systemctl restart vol-ovpn-panel
```

---

## 🔄 Обновление панели

```bash
REPO="https://raw.githubusercontent.com/robertmiro14-netizen/ovpn-panel/main"
curl -fsSL "$REPO/server.js"  -o /opt/vol-ovpn-panel/server.js
curl -fsSL "$REPO/panel.html" -o /opt/vol-ovpn-panel/panel.html
systemctl restart vol-ovpn-panel && echo "✅ Готово"
```

---

## 🏗️ Архитектура

```
Браузер (HTTPS) ──→  :51822 (Vol OVPN Panel / Node.js)
                            │
                            ├── GET /          → panel.html
                            ├── GET /api/clients → читает /opt/ovpn-data/pki/index.txt
                            ├── POST /api/clients → docker exec ovpn easyrsa build-client-full
                            ├── DELETE /api/clients/:name → docker exec ovpn ovpn_revokeclient
                            └── GET /api/clients/:name/config → docker exec ovpn ovpn_getclient

OpenVPN ────→ :1194/udp (Docker vol-openvpn)
PKI/CA  ────→ /opt/ovpn-data/pki/
```

---

## 📋 Требования

- Ubuntu **20.04 / 22.04 / 24.04**
- Доступ **root** (или sudo)
- Открытые порты: **1194/udp** и **51822/tcp**
- Минимум **512 MB RAM**
