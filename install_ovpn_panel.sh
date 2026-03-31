#!/bin/bash
# ============================================================
#  VOL OVPN PANEL — OpenVPN + Node.js web panel
#  Поддерживает Ubuntu 20.04 / 22.04 / 24.04
#  Запуск: sudo bash install_ovpn_panel.sh
#  или:    curl -fsSL <url>/install_ovpn_panel.sh | bash
# ============================================================
set -e

# ─── Цвета ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

# ─── Проверки ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Запускайте от root (sudo bash $0)"
command -v apt >/dev/null 2>&1 || error "Поддерживается только Debian/Ubuntu"

echo -e "${BOLD}${GREEN}"
echo "  ██╗   ██╗ ██████╗ ██╗        ██████╗ ██╗   ██╗██████╗ ███╗   ██╗"
echo "  ██║   ██║██╔═══██╗██║       ██╔═══██╗██║   ██║██╔══██╗████╗  ██║"
echo "  ██║   ██║██║   ██║██║       ██║   ██║██║   ██║██████╔╝██╔██╗ ██║"
echo "  ╚██╗ ██╔╝██║   ██║██║       ██║   ██║╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║"
echo "   ╚████╔╝ ╚██████╔╝███████╗  ╚██████╔╝ ╚████╔╝ ██║     ██║ ╚████║"
echo "    ╚═══╝   ╚═════╝ ╚══════╝   ╚═════╝   ╚═══╝  ╚═╝     ╚═╝  ╚═══╝"
echo -e "${NC}"
echo -e "${BOLD}  VOL OVPN PANEL — OpenVPN${NC}"
echo "  ──────────────────────────"
echo ""

# ─── Публичный IP ───────────────────────────────────────────
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || \
            curl -s --max-time 5 https://ifconfig.me  || \
            hostname -I | awk '{print $1}')
info "Публичный IP: ${BOLD}${SERVER_IP}${NC}"

OVPN_PORT=1194      # OpenVPN UDP
WEB_PORT=51822      # Vol OVPN Panel (публичный)
REPO_RAW="https://raw.githubusercontent.com/robertmiro14-netizen/ovpn-panel/main"

# ─── 1. Системные пакеты ────────────────────────────────────
info "Обновление пакетов..."
apt update -qq
apt install -y -qq curl ufw iptables openssl 2>/dev/null || true
success "Пакеты готовы"

# ─── 2. Node.js 20 LTS ──────────────────────────────────────
if ! command -v node >/dev/null 2>&1 || [[ $(node -e "process.exit(process.version.split('.')[0].slice(1)<18?1:0)" 2>/dev/null; echo $?) -eq 1 ]]; then
    info "Установка Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt install -y nodejs >/dev/null 2>&1
    success "Node.js установлен: $(node --version)"
else
    success "Node.js уже установлен: $(node --version)"
fi

# ─── 3. Docker ──────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
    info "Установка Docker..."
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
    systemctl enable docker >/dev/null 2>&1
    systemctl start docker
    success "Docker установлен: $(docker --version | cut -d' ' -f3 | tr -d ',')"
else
    success "Docker уже установлен: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

# ─── 4. IP forwarding ───────────────────────────────────────
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
success "IP forwarding включён"

# ─── 5. UFW ─────────────────────────────────────────────────
info "Настройка UFW..."
ufw allow 22/tcp          >/dev/null 2>&1 || true
ufw allow ${OVPN_PORT}/udp >/dev/null 2>&1 || true
ufw allow ${WEB_PORT}/tcp  >/dev/null 2>&1 || true
ufw --force enable         >/dev/null 2>&1 || true
success "Порты открыты: 22/tcp, ${OVPN_PORT}/udp, ${WEB_PORT}/tcp"

# ─── 6. Vol OVPN Panel (Node.js) ────────────────────────────
info "Создание Vol OVPN Panel..."
mkdir -p /opt/vol-ovpn-panel
chmod 750 /opt/vol-ovpn-panel

# package.json — через printf (без heredoc)
printf '{"name":"vol-ovpn-panel","version":"1.0.0","main":"server.js","dependencies":{"bcryptjs":"^2.4.3","express":"^4.19.2","express-session":"^1.18.0"}}\n' \
    > /opt/vol-ovpn-panel/package.json
success "package.json создан"

# Скачать server.js и panel.html из репозитория
info "Скачивание server.js..."
curl -fsSL "${REPO_RAW}/server.js" -o /opt/vol-ovpn-panel/server.js \
    || error "Не удалось скачать server.js с ${REPO_RAW}"
success "server.js загружен"

info "Скачивание panel.html..."
curl -fsSL "${REPO_RAW}/panel.html" -o /opt/vol-ovpn-panel/panel.html \
    || error "Не удалось скачать panel.html с ${REPO_RAW}"
success "panel.html загружен"

# ─── 7. SSL сертификат (самоподписанный) ────────────────────
info "Генерация SSL сертификата..."
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /opt/vol-ovpn-panel/cert.key \
    -out    /opt/vol-ovpn-panel/cert.crt \
    -days 3650 \
    -subj "/CN=${SERVER_IP}/O=Vol OVPN Panel/C=UA" \
    >/dev/null 2>&1
chmod 600 /opt/vol-ovpn-panel/cert.key
success "SSL сертификат создан (действителен 10 лет)"

# npm install
info "Установка npm зависимостей..."
cd /opt/vol-ovpn-panel && npm install --production --quiet 2>/dev/null
success "Зависимости установлены"

# ─── 8. Systemd сервис vol-ovpn-panel ───────────────────────
printf '[Unit]\nDescription=Vol OVPN Panel\nAfter=network.target docker.service\nWants=docker.service\n\n[Service]\nType=simple\nWorkingDirectory=/opt/vol-ovpn-panel\nExecStart=/usr/bin/node /opt/vol-ovpn-panel/server.js\nRestart=always\nRestartSec=5\nEnvironment=NODE_ENV=production\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/vol-ovpn-panel.service

systemctl daemon-reload
systemctl enable vol-ovpn-panel >/dev/null 2>&1
systemctl restart vol-ovpn-panel
success "Vol OVPN Panel запущена на порту ${WEB_PORT}"

# ─── 9. OpenVPN через Docker (kylemanna/openvpn) ────────────
info "Загрузка образа OpenVPN..."
mkdir -p /opt/ovpn-data
chmod 700 /opt/ovpn-data
docker pull kylemanna/openvpn >/dev/null 2>&1
success "Образ загружен"

# Инициализация PKI (если ещё не настроено)
if [ ! -f /opt/ovpn-data/pki/ca.crt ]; then
    info "Генерация конфигурации OpenVPN..."
    docker run -v /opt/ovpn-data:/etc/openvpn --rm \
        kylemanna/openvpn ovpn_genconfig \
        -u udp://${SERVER_IP}:${OVPN_PORT} \
        -n "1.1.1.1" -n "8.8.8.8" \
        >/dev/null 2>&1
    success "Конфигурация создана"

    info "Инициализация PKI и создание CA сертификата..."
    docker run -v /opt/ovpn-data:/etc/openvpn --rm \
        -e EASYRSA_BATCH=1 \
        kylemanna/openvpn ovpn_initpki nopass \
        >/dev/null 2>&1
    success "PKI инициализирован, CA сертификат создан"
else
    success "PKI уже инициализирован"
fi

# Запуск OpenVPN
info "Запуск OpenVPN..."
docker stop vol-openvpn 2>/dev/null || true
docker rm   vol-openvpn 2>/dev/null || true

docker run -d \
    --name=vol-openvpn \
    --cap-add=NET_ADMIN \
    -p ${OVPN_PORT}:${OVPN_PORT}/udp \
    -v /opt/ovpn-data:/etc/openvpn \
    --restart unless-stopped \
    kylemanna/openvpn

sleep 3
success "OpenVPN запущен"

# ─── 10. Итоги ──────────────────────────────────────────────
PANEL_OK=$(systemctl is-active vol-ovpn-panel 2>/dev/null || echo "inactive")
DOCKER_OK=$(docker inspect -f '{{.State.Running}}' vol-openvpn 2>/dev/null || echo "false")

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║     VOL OVPN — УСТАНОВКА ЗАВЕРШЕНА      ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
[[ "$PANEL_OK" == "active" ]] \
    && echo -e "  ${BOLD}Vol OVPN Panel:${NC}   ${GREEN}● Работает${NC}" \
    || echo -e "  ${BOLD}Vol OVPN Panel:${NC}   ${RED}● Ошибка${NC} (journalctl -u vol-ovpn-panel)"
[[ "$DOCKER_OK" == "true" ]] \
    && echo -e "  ${BOLD}OpenVPN:${NC}          ${GREEN}● Работает${NC}" \
    || echo -e "  ${BOLD}OpenVPN:${NC}          ${RED}● Ошибка${NC} (docker logs vol-openvpn)"
echo ""
echo -e "  ${BOLD}Веб-панель:${NC}  ${CYAN}https://${SERVER_IP}:${WEB_PORT}${NC}"
echo -e "  ${YELLOW}★  Браузер покажет предупреждение о сертификате — нажмите «Продолжить»${NC}"
echo -e "  ${YELLOW}★  При первом входе задайте пароль в браузере${NC}"
echo ""
echo -e "  ${CYAN}Логи панели:${NC}   journalctl -u vol-ovpn-panel -f"
echo -e "  ${CYAN}Логи OpenVPN:${NC}  docker logs -f vol-openvpn"
echo -e "  ${CYAN}Перезапуск:${NC}    systemctl restart vol-ovpn-panel && docker restart vol-openvpn"
echo ""
echo -e "  Откройте: ${BOLD}https://${SERVER_IP}:${WEB_PORT}${NC}"
echo ""
