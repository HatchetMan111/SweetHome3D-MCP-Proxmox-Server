#!/usr/bin/env bash
#
# SweetHome3D + MCP-Server + Web-Desktop (noVNC)
# Community-Scripts Stil – zum Ausführen IN einer frischen Ubuntu 24.04 VM (Proxmox)
# Getestet für: Ubuntu 24.04 noble, 4 vCPU / 8GB RAM / 20GB (Disk später in Proxmox erweiterbar)
# Aufruf als root:  bash sweethome3d-mcp-install.sh
# Optional:        VNCPASS=meinpass bash sweethome3d-mcp-install.sh
#
set -e

# ---------- Community-Scripts Look ----------
YW=$(echo "\033[33m"); BL=$(echo "\033[36m"); RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m"); CL=$(echo "\033[m"); CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"

header_info() {
  clear 2>/dev/null || true
  cat <<"EOF"
   ____                      _   _   _                      _____ ____
  / ___|_      _____  ___  _| | | | | | ___  _ __ ___   ___|___ |  _ \
  \___ \ \ /\ / / _ \/ _ \| |_| |_| | |/ _ \| '_ ` _ \ / _ \ / /| | | |
   ___) \ V  V /  __/  __/|  _  _  | | | (_) | | | | | |  __// / | |_| |
  |____/ \_/\_/ \___|\___||_| |_| |_|_|\___/|_| |_| |_|\___/_/  |____/
         + MCP-Server + noVNC Web-Desktop für Proxmox VM
EOF
}

msg_info()  { echo -e "  ${BL}●${CL} $1"; }
msg_ok()    { echo -e "  ${CM} $1"; }
msg_error() { echo -e "  ${CROSS} $1"; }
catch_errors() { msg_error "Fehler in Zeile $1 – Abbruch."; exit 1; }
trap 'catch_errors $LINENO' ERR

# ---------- Config ----------
APP="SweetHome3D-MCP"
SH3D_VER="7.5"
SH3D_URL="https://sourceforge.net/projects/sweethome3d/files/SweetHome3D/SweetHome3D-${SH3D_VER}/SweetHome3D-${SH3D_VER}-linux-x64.tgz/download"
SH3D_DIR="/opt/SweetHome3D"
MCP_REPO="grimashevich/sweethome3d-mcp-server"
VNC_USER="${VNC_USER:-root}"
VNC_DISPLAY=":1"
VNC_PORT="5901"
NOVNC_PORT="6080"
MCP_PORT="9877"
VNCPASS="${VNCPASS:-sweethome3d}"
export DEBIAN_FRONTEND=noninteractive

header_info
echo -e "${YW}App:${CL} ${APP} | SH3D ${SH3D_VER} | VNC ${VNC_PORT} | noVNC ${NOVNC_PORT} | MCP ${MCP_PORT}\n"

if [ "$(id -u)" -ne 0 ]; then msg_error "Bitte als root ausführen."; exit 1; fi
if ! grep -qs "Ubuntu.*24.04" /etc/os-release; then msg_info "Kein Ubuntu 24.04 erkannt – versuche trotzdem weiter."; fi

# Unter Cloud-Init (Auto-Install beim ersten Boot) keinen Abbruch wegen fehlendem TTY,
# und auf cloud-init / apt-Locks warten (sonst schlägt apt-get fehl).
if command -v cloud-init >/dev/null 2>&1; then
  msg_info "Warte ggf. auf cloud-init (max 10 Min)"
  cloud-init status --wait >/dev/null 2>&1 || true
fi

# ---------- 1. System ----------
msg_info "System updaten + Basis installieren"
if command -v fuser >/dev/null 2>&1; then
  msg_info "Warte ggf. auf apt-Sperren (max 10 Min)"
  for i in $(seq 1 120); do
    if ! fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then break; fi
    sleep 5
  done
fi
apt-get update -qq || { msg_info "apt-update Retry in 10s"; sleep 10; apt-get update -qq; }
if [ "${UPGRADE:-0}" = "1" ]; then
  msg_info "Upgrade (UPGRADE=1 gesetzt, dauert länger)"
  apt-get upgrade -y -qq
else
  msg_info "Upgrade übersprungen (mit UPGRADE=1 aktivierbar)"
fi
apt-get install -y curl wget unzip git sudo net-tools iproute2 \
  openjdk-17-jre xfce4 xfce4-terminal dbus-x11 \
  tigervnc-standalone-server tigervnc-common \
  novnc websockify python3-websockify
msg_ok "Basis installiert"

# ---------- 2. Sweet Home 3D ----------
msg_info "Installiere Sweet Home 3D ${SH3D_VER} nach ${SH3D_DIR}"
rm -rf /tmp/sh3d.tgz "${SH3D_DIR}" /opt/SweetHome3D-"${SH3D_VER}"
curl -fSL --retry 3 -o /tmp/sh3d.tgz "${SH3D_URL}"
mkdir -p /opt
tar xzf /tmp/sh3d.tgz -C /opt
# Extrahierter Ordner heißt SweetHome3D-<VER> -> normieren
if [ ! -d "${SH3D_DIR}" ]; then
  if [ -d "/opt/SweetHome3D-${SH3D_VER}" ]; then
    mv "/opt/SweetHome3D-${SH3D_VER}" "${SH3D_DIR}"
  else
    msg_error "SH3D-Archiv unerwartet – kein Ordner SweetHome3D-${SH3D_VER} in /opt"; ls /opt; exit 1
  fi
fi
[ -x "${SH3D_DIR}/SweetHome3D" ] || { msg_error "Starter ${SH3D_DIR}/SweetHome3D fehlt"; ls -la "${SH3D_DIR}" | head; exit 1; }
chmod +x "${SH3D_DIR}/SweetHome3D"
ln -sf "${SH3D_DIR}/SweetHome3D" /usr/local/bin/sweethome3d
msg_ok "Sweet Home 3D installiert"

# ---------- 3. MCP-Plugin (latest .sh3p) ----------
msg_info "Lade neuestes MCP-Plugin (${MCP_REPO})"
MCP_URL=$(curl -fsSL "https://api.github.com/repos/${MCP_REPO}/releases/latest" | grep -o 'https://[^"]*\.sh3p' | head -n1 || true)
if [ -z "${MCP_URL}" ]; then
  # Fallback auf bekannte Version
  MCP_URL="https://github.com/${MCP_REPO}/releases/download/v1.1.0/sh3d-mcp-plugin-1.1.0.sh3p"
  msg_info "GitHub-API gab kein Asset – nutze Fallback: ${MCP_URL}"
fi
mkdir -p /tmp/mcp && curl -fSL -o /tmp/mcp/plugin.sh3p "${MCP_URL}" || {
  msg_error "MCP-Download fehlgeschlagen: ${MCP_URL}"; exit 1;
}
for PLUGDIR in "/root/.eteks/sweethome3d/plugins" "/root/.sweethome3d/plugins" "/home/sh3d/.eteks/sweethome3d/plugins" "/home/sh3d/.sweethome3d/plugins"; do
  mkdir -p "${PLUGDIR}"
  cp /tmp/mcp/plugin.sh3p "${PLUGDIR}/" 2>/dev/null || true
done
msg_ok "MCP-Plugin installiert"

# ---------- 4. VNC + noVNC ----------
msg_info "Richte TigerVNC (${VNC_DISPLAY}) + noVNC (${NOVNC_PORT}) ein"
/usr/bin/vncserver -kill "${VNC_DISPLAY}" >/dev/null 2>&1 || true
mkdir -p /root/.vnc
printf '%s' "${VNCPASS}" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

cat > /root/.vnc/xstartup <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources
startxfce4 &
# Sweet Home 3D Autostart (MCP startet automatisch mit, Port 9877)
sleep 2
/opt/SweetHome3D/SweetHome3D &
EOF
chmod +x /root/.vnc/xstartup

cat > /etc/systemd/system/vncserver@.service <<EOF
[Unit]
Description=TigerVNC Server :%i (SweetHome3D Desktop)
After=network.target
[Service]
Type=forking
User=root
PAMName=login
PIDFile=/root/.vnc/%H:%i.pid
ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill :%i > /dev/null 2>&1 || :'
ExecStart=/usr/bin/vncserver :%i -geometry 1600x900 -depth 24
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

WEBSOCKIFY_BIN=$(command -v websockify || echo /usr/bin/websockify)
[ -x "${WEBSOCKIFY_BIN}" ] || { msg_error "websockify nicht gefunden – Paket websockify fehlt?"; exit 1; }
NOVNC_WEB="/usr/share/novnc"
if [ ! -f "${NOVNC_WEB}/vnc.html" ]; then
  msg_error "noVNC Web-Dateien fehlen unter ${NOVNC_WEB} – Paket novnc fehlt?"
  exit 1
fi
cat > /etc/systemd/system/novnc.service <<EOF
[Unit]
Description=noVNC WebSocket Proxy (SweetHome3D Web-Desktop)
After=network.target vncserver@1.service
Wants=vncserver@1.service
[Service]
ExecStart=${WEBSOCKIFY_BIN} --web=${NOVNC_WEB} ${NOVNC_PORT} localhost:${VNC_PORT}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q vncserver@1.service
systemctl enable -q novnc.service
systemctl restart vncserver@1.service
systemctl restart novnc.service
msg_ok "VNC + noVNC laufen"

# Firewall (falls ufw aktiv)
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow ${NOVNC_PORT}/tcp >/dev/null || true
  ufw allow ${VNC_PORT}/tcp >/dev/null || true
  ufw allow ${MCP_PORT}/tcp >/dev/null || true
fi

sleep 3
systemctl is-active -q vncserver@1.service || { msg_error "VNC startet nicht – journalctl -u vncserver@1"; exit 1; }
systemctl is-active -q novnc.service || { msg_error "noVNC startet nicht – journalctl -u novnc"; exit 1; }
msg_ok "Services aktiv"

# ---------- 5. Abschluss ----------
IP=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
[ -z "${IP}" ] && IP="<VM-IP>"
MCP_TEST=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${MCP_PORT}/mcp" || echo "000")

clear 2>/dev/null || true
header_info
echo -e "${GN}✔ Installation fertig — ${APP}${CL}\n"
echo -e "${YW}Weboberfläche (Browser):${CL}  http://${IP}:${NOVNC_PORT}/vnc.html"
echo -e "${YW}VNC-Client:${CL}              ${IP}:${VNC_PORT}  (Passwort: ${VNCPASS})"
echo -e "${YW}MCP-Server (in SH3D):${CL}     http://${IP}:${MCP_PORT}/mcp  (lokaler Check: HTTP ${MCP_TEST} – 200/400 = ok, 000 = SH3D noch am Starten)"
echo -e "${YW}Sweet Home 3D:${CL}            /opt/SweetHome3D/SweetHome3D  (läuft bereits im VNC-Desktop)"
echo ""
echo -e "${BL}So richtest du es vollends ein:${CL}"
echo "  1) Browser öffnen:  http://${IP}:${NOVNC_PORT}/vnc.html  → Verbinden (Passwort oben)"
echo "  2) In Sweet Home 3D: Tools/Werkzeuge → MCP Server... → muss 'Running on 9877' zeigen."
echo "     Falls nicht: SH3D einmal neu starten (läuft im VNC-Desktop), Plugin liegt in ~/.eteks/sweethome3d/plugins/"
echo "  3) Erst einen Grundriss öffnen/erstellen, dann AI verbinden – MCP steuert immer das offene Home."
echo ""
echo -e "${BL}opencode verbinden (auf deinem Rechner, nicht in der VM):${CL}"
echo "  In ~/.config/opencode/opencode.json eintragen (IP anpassen!):"
cat <<EOF
  {
    "\$schema": "https://opencode.ai/config.json",
    "mcp": {
      "sweethome3d-vm": {
        "type": "remote",
        "url": "http://${IP}:${MCP_PORT}/mcp",
        "enabled": true
      }
    }
  }
EOF
echo "  Danach opencode neu starten. Achtung: MCP hat keine Auth –"
echo "  Port ${MCP_PORT} NICHT direkt ins Internet, nur via VPN/Tailscale/WireGuard oder SSH-Tunnel:"
echo "    ssh -L 9877:localhost:9877 root@${IP}   # dann in opencode http://localhost:9877/mcp nutzen"
echo ""
echo -e "${BL}Erste Prompts zum Testen:${CL}"
echo '  "Nutze sweethome3d-vm get_state und fasse zusammen, was im aktuellen Home ist."'
echo '  "Erstelle 10x8m Grundriss mit 2 Zimmern, Küche, Bad, 260cm Wandhöhe, dann export_plan_image."'
echo ""
echo -e "${RD}Hinweis:${CL} VM braucht GUI – kein LXC ohne Desktop-Tuning. Snapshot in Proxmox machen!"
