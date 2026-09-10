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
catch_errors() {
  msg_error "Fehler in Zeile $1 – Abbruch. Diagnose:"
  echo "----- systemctl sweethome3d-desktop -----"
  systemctl status sweethome3d-desktop.service --no-pager 2>&1 | head -20 || true
  echo "----- journal sweethome3d-desktop (letzte 25) -----"
  journalctl -u sweethome3d-desktop --no-pager -n 25 2>&1 | tail -25 || true
  echo "----- journal novnc (letzte 10) -----"
  journalctl -u novnc --no-pager -n 10 2>&1 | tail -10 || true
  echo "----- SH3D app log -----"
  tail -20 /var/log/sweethome3d-app.log 2>&1 || true
  echo "----- /root/.vnc logs -----"
  for f in /root/.vnc/*.log; do
    [ -f "$f" ] && { echo "--- $f ---"; tail -20 "$f" 2>&1; }
  done
  exit 1
}
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
# Achtung: KEIN nacktes `cloud-init status --wait` hier – wenn dieses Script
# selbst per Cloud-Init runcmd läuft, wartet es dabei auf sich selbst (Deadlock).
# Daher strikt zeitbegrenzt, Fehler egal.
if command -v cloud-init >/dev/null 2>&1; then
  msg_info "Warte ggf. auf cloud-init (max 2 Min)"
  timeout 120 cloud-init status --wait >/dev/null 2>&1 || true
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
apt-get install -y curl wget unzip git sudo net-tools iproute2 xauth \
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
# MCP-Plugin braucht Java 11+, das mitgelieferte SH3D-Runtime ist aber Java 8
# -> stilllegen, damit der Starter das System-Java (17) nimmt
if [ -x "${SH3D_DIR}/runtime/bin/java" ]; then
  BUNDLED_VER=$("${SH3D_DIR}/runtime/bin/java" -version 2>&1 | head -n1 || true)
  msg_info "Gebundeltes SH3D-Java: ${BUNDLED_VER}"
  if echo "${BUNDLED_VER}" | grep -qE '"1\.[0-8]\.'; then
    msg_info "Bundled Java 8 erkannt – wird stillgelegt (System-Java übernimmt)"
    rm -rf "${SH3D_DIR}/runtime.bundled-j8-disabled"
    mv "${SH3D_DIR}/runtime" "${SH3D_DIR}/runtime.bundled-j8-disabled"
  fi
fi
SYS_JAVA_VER=$(java -version 2>&1 | head -n1 || true)
msg_info "System-Java: ${SYS_JAVA_VER}"
echo "${SYS_JAVA_VER}" | grep -qE '"(1[1-9]|[2-9][0-9])\.' || { msg_error "System-Java < 11 – MCP-Plugin braucht Java 11+"; exit 1; }
msg_ok "Sweet Home 3D installiert"

# ---------- 3. MCP-Plugin (latest .sh3p) ----------
msg_info "Lade neuestes MCP-Plugin (${MCP_REPO})"
MCP_URL=$(curl -fsSL "https://api.github.com/repos/${MCP_REPO}/releases/latest" | grep -o 'https://[^"]*\.sh3p' | head -n1 || true)
if [ -z "${MCP_URL}" ]; then
  # Fallback auf bekannte Version
  MCP_URL="https://github.com/${MCP_REPO}/releases/download/v1.1.0/sh3d-mcp-plugin-1.1.0.sh3p"
  msg_info "GitHub-API gab kein Asset – nutze Fallback: ${MCP_URL}"
fi
mkdir -p /tmp/mcp && rm -f /tmp/mcp/*.sh3p
PLUGIN_FILE=$(basename "${MCP_URL}")
curl -fSL -o "/tmp/mcp/${PLUGIN_FILE}" "${MCP_URL}" || {
  msg_error "MCP-Download fehlgeschlagen: ${MCP_URL}"; exit 1;
}
for PLUGDIR in "/root/.eteks/sweethome3d/plugins" "/root/.sweethome3d/plugins" "/home/sh3d/.eteks/sweethome3d/plugins" "/home/sh3d/.sweethome3d/plugins"; do
  mkdir -p "${PLUGDIR}"
  rm -f "${PLUGDIR}/plugin.sh3p" 2>/dev/null || true
  cp /tmp/mcp/*.sh3p "${PLUGDIR}/" 2>/dev/null || true
done
msg_ok "MCP-Plugin installiert (${PLUGIN_FILE})"

# ---------- 4. VNC + noVNC (Xvnc direkt, ohne vncserver-Wrapper) ----------
# Der vncserver-Perl-Wrapper starb mit Exit 255 und die Restart-Schleife hat
# dabei jedes Mal den gerade gestarteten X-Server gekillt. Daher: Xvnc läuft
# direkt als simple-Service, Session startet ein Wrapper-Script.
msg_info "Richte Xvnc (${VNC_DISPLAY}) + noVNC (${NOVNC_PORT}) ein"
# Alten Wrapper-Service + hängende Reste aus vorherigen Läufen entfernen
systemctl disable --now vncserver@1.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/vncserver@.service
/usr/bin/vncserver -kill "${VNC_DISPLAY}" >/dev/null 2>&1 || true
DISPNUM="${VNC_DISPLAY#:}"
# Achtung: Pattern in eckigen Klammern, damit pkill nicht die eigene Shell trifft
pkill -f "Xvnc :[${DISPNUM}]" >/dev/null 2>&1 || true
pkill -f "com.eteks.sweethome3d.SweetHome3D" >/dev/null 2>&1 || true
sleep 2
rm -rf "/tmp/.X11-unix/X${DISPNUM}" "/tmp/.X${DISPNUM}-lock" || true
rm -f /root/.vnc/*.log /root/.vnc/*.pid || true
mkdir -p /root/.vnc
printf '%s' "${VNCPASS}" | vncpasswd -f > /root/.vnc/passwd
chmod 600 /root/.vnc/passwd

cat > /usr/local/bin/sh3d-xsession <<'EOF'
#!/bin/sh
# Startet Xvnc + XFCE + Sweet Home 3D (MCP auf 9877). Läuft als systemd-Service.
export DISPLAY=:1
/usr/bin/Xvnc :1 -geometry 1600x900 -depth 24 -rfbport 5901 \
  -SecurityTypes VncAuth -PasswordFile /root/.vnc/passwd \
  -AlwaysShared -AcceptKeyEvents -AcceptPointerEvents \
  -SendCutText -AcceptCutText -desktop 3D-Home &
XVNC_PID=$!
for i in $(seq 1 30); do
  [ -S /tmp/.X11-unix/X1 ] && break
  sleep 1
done
[ -S /tmp/.X11-unix/X1 ] || { echo "Xvnc-Socket fehlt, breche ab"; exit 1; }
if command -v xauth >/dev/null 2>&1; then
  rm -f /root/.Xauthority
  COOKIE=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
  xauth -f /root/.Xauthority add :1 . "$COOKIE"
  export XAUTHORITY=/root/.Xauthority
fi
unset SESSION_MANAGER DBUS_SESSION_BUS_ADDRESS
[ -r /root/.Xresources ] && xrdb /root/.Xresources 2>/dev/null || true
pkill -f "com.eteks.sweethome3d.SweetHome3D" 2>/dev/null || true
startxfce4 &
sleep 2
setsid /opt/SweetHome3D/SweetHome3D >/var/log/sweethome3d-app.log 2>&1 &
wait $XVNC_PID
EOF
chmod +x /usr/local/bin/sh3d-xsession

cat > /etc/systemd/system/sweethome3d-desktop.service <<EOF
[Unit]
Description=SweetHome3D Desktop (Xvnc + XFCE + SH3D)
After=network.target
[Service]
Type=simple
ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill :1 >/dev/null 2>&1 || :; /usr/bin/pkill -f "Xvnc :[1]" >/dev/null 2>&1 || :; rm -rf /tmp/.X11-unix/X1 /tmp/.X1-lock'
ExecStart=/usr/local/bin/sh3d-xsession
Restart=always
RestartSec=5
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
After=network.target sweethome3d-desktop.service
Wants=sweethome3d-desktop.service
[Service]
ExecStart=${WEBSOCKIFY_BIN} --web=${NOVNC_WEB} ${NOVNC_PORT} localhost:${VNC_PORT}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q sweethome3d-desktop.service
systemctl enable -q novnc.service
systemctl restart sweethome3d-desktop.service
systemctl restart novnc.service
msg_info "Warte auf VNC-Port ${VNC_PORT} (max 90s)"
for i in $(seq 1 90); do
  (ss -tln 2>/dev/null || netstat -tln 2>/dev/null) | grep -q ":${VNC_PORT} " && break
  sleep 1
done
msg_ok "VNC + noVNC laufen"

# Firewall (falls ufw aktiv)
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow ${NOVNC_PORT}/tcp >/dev/null || true
  ufw allow ${VNC_PORT}/tcp >/dev/null || true
  ufw allow ${MCP_PORT}/tcp >/dev/null || true
fi

sleep 2
systemctl is-active -q sweethome3d-desktop.service || { msg_error "Desktop-Service startet nicht – journalctl -u sweethome3d-desktop"; exit 1; }
systemctl is-active -q novnc.service || { msg_error "noVNC startet nicht – journalctl -u novnc"; exit 1; }
msg_ok "Services aktiv"

# SH3D (Java) braucht beim ersten Start 1-3 Min – auf MCP-Port warten statt raten
msg_info "Warte auf Sweet Home 3D / MCP-Port ${MCP_PORT} (max 3 Min)"
MCP_TEST="000"
for i in $(seq 1 60); do
  CODE=$(curl -s -m 3 -o /dev/null -w "%{http_code}" "http://127.0.0.1:${MCP_PORT}/mcp" 2>/dev/null || true)
  [ -z "${CODE}" ] && CODE="000"
  if [ "${CODE}" != "000" ]; then MCP_TEST="${CODE}"; break; fi
  sleep 3
done
if [ "${MCP_TEST}" = "000" ]; then
  msg_error "MCP-Port ${MCP_PORT} antwortet nicht – SH3D-Prozess prüfen:"
  ps aux | grep -iE 'sweethome|Xvnc|startxfce' | grep -v grep || true
  tail -30 /var/log/sweethome3d-app.log 2>&1 || true
  exit 1
fi
msg_ok "MCP antwortet (HTTP ${MCP_TEST})"

# Web-Port muss wirklich lauschen, sonst kein Erfolgsbanner
if ! (ss -tln 2>/dev/null || netstat -tln 2>/dev/null) | grep -q ":${NOVNC_PORT} "; then
  msg_error "Port ${NOVNC_PORT} lauscht nicht – journalctl -u novnc prüfen"
  exit 1
fi

# ---------- 5. Abschluss ----------
IP=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -m1 -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
[ -z "${IP}" ] && IP="<VM-IP>"

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
