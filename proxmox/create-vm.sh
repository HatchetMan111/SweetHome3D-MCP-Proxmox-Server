#!/usr/bin/env bash
#
# SweetHome3D-MCP – Proxmox VM erstellen (Host-Script, Community-Scripts Stil)
# Auf dem PROXMOX-HOST als root ausführen, NICHT in der VM.
#
# Einzeiler:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/proxmox/create-vm.sh)"
#
# Was es tut:
#   - nimmt automatisch die nächste freie VMID (pvesh get /cluster/nextid)
#   - falls Wunsch-ID belegt ist, wird hochgezählt bis frei
#   - erstellt Ubuntu 24.04 Cloud-Init VM namens 3D-Home (4 vCPU / 8GB / 20GB)
#
# Optional per Env überschreibbar:
#   VM_ID=200 VM_NAME=3D-Home VM_CPU=4 VM_RAM=8192 VM_DISK_GB=20 \
#   VM_BRIDGE=vmbr0 VM_STORAGE=local-lvm VM_ISO_STORAGE=local \
#   VNCPASS=sweethome3d AUTO_INSTALL=1 \
#   bash create-vm.sh
# AUTO_INSTALL=1 (Standard) installiert SweetHome3D per Cloud-Init
# automatisch in der VM nach (~10-15 Min). Mit AUTO_INSTALL=0 nur VM erstellen.
#
set -e

YW=$(echo "\033[33m"); BL=$(echo "\033[36m"); RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m"); CL=$(echo "\033[m"); CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"
msg_info()  { echo -e "  ${BL}●${CL} $1"; }
msg_ok()    { echo -e "  ${CM} $1"; }
msg_error() { echo -e "  ${CROSS} $1"; }
header_info() {
  clear
  cat <<"EOF"
   ____  ___  _   _                      _____ ____
  |___ \|  _|| | | | ___  _ __ ___   ___|___ |  _ \
    / /| |_ | |_| |/ _ \| '_ ` _ \ / _ \ / /| | | |
   / / |  _||  _  | (_) | | | | | |  __// / | |_| |
  /_/  |_|  |_| |_|\___/|_| |_| |_|\___/_/  |____/
        Proxmox VM-Ersteller für SweetHome3D-MCP
EOF
}

VM_NAME="${VM_NAME:-3D-Home}"
VM_CPU="${VM_CPU:-4}"
VM_RAM="${VM_RAM:-8192}"
VM_DISK_GB="${VM_DISK_GB:-20}"
VM_BRIDGE="${VM_BRIDGE:-vmbr0}"
VM_STORAGE="${VM_STORAGE:-local-lvm}"
VM_ISO_STORAGE="${VM_ISO_STORAGE:-local}"
CLOUD_IMG_URL="${CLOUD_IMG_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
WANT_ID="${VM_ID:-}"
AUTO_INSTALL="${AUTO_INSTALL:-1}"
VNCPASS="${VNCPASS:-sweethome3d}"
INSTALL_URL="${INSTALL_URL:-https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/install/sweethome3d-mcp-install.sh}"

header_info
echo -e "${YW}Name:${CL} ${VM_NAME} | CPU: ${VM_CPU} | RAM: ${VM_RAM}MB | Disk: ${VM_DISK_GB}G\n"

if [ "$(id -u)" -ne 0 ]; then msg_error "Bitte als root auf dem Proxmox-Host ausführen."; exit 1; fi
command -v qm >/dev/null 2>&1 || { msg_error "qm nicht gefunden – kein Proxmox-Host?"; exit 1; }
command -v pvesh >/dev/null 2>&1 || { msg_error "pvesh nicht gefunden – kein Proxmox-Host?"; exit 1; }

vmid_taken() { qm status "$1" >/dev/null 2>&1; }

# --- VMID bestimmen: belegt -> nächste nehmen ---
if [ -n "${WANT_ID}" ]; then
  VMID="${WANT_ID}"
  while vmid_taken "${VMID}"; do
    msg_info "VMID ${VMID} belegt – nehme nächste."
    VMID=$((VMID + 1))
  done
else
  VMID=$(pvesh get /cluster/nextid 2>/dev/null || echo "200")
  # nextid kann String mit Anführungszeichen sein -> nur Ziffern
  VMID=$(echo "${VMID}" | tr -cd '0-9')
  [ -z "${VMID}" ] && VMID=200
  while vmid_taken "${VMID}"; do
    VMID=$((VMID + 1))
  done
fi
msg_info "Nutze VMID ${VMID} / Name ${VM_NAME}"

# --- Storage prüfen, ggf. Fallback ---
if ! pvesm status --storage "${VM_STORAGE}" >/dev/null 2>&1; then
  msg_info "Storage ${VM_STORAGE} nicht gefunden – suche Ersatz."
  VM_STORAGE=$(pvesm status -content images 2>/dev/null | awk 'NR>1 {print $1}' | head -n1)
  [ -z "${VM_STORAGE}" ] && { msg_error "Kein Storage mit images-Content gefunden."; exit 1; }
  msg_info "Nutze Storage ${VM_STORAGE}"
fi

# --- Cloud-Image laden ---
IMG_TMP="/var/lib/vz/template/iso/noble-server-cloudimg-amd64-${VMID}.img"
mkdir -p "$(dirname "${IMG_TMP}")"
if [ ! -s "${IMG_TMP}" ]; then
  msg_info "Lade Ubuntu 24.04 Cloud-Image (einmalig, ~600MB)"
  wget -q --show-progress -O "${IMG_TMP}" "${CLOUD_IMG_URL}"
fi
msg_ok "Cloud-Image bereit"

# --- VM erstellen ---
msg_info "Erstelle VM ${VMID} (${VM_NAME})"
qm create "${VMID}" \
  --name "${VM_NAME}" \
  --memory "${VM_RAM}" \
  --cores "${VM_CPU}" \
  --sockets 1 \
  --cpu host \
  --machine q35 \
  --bios seabios \
  --ostype l26 \
  --agent enabled=1 \
  --net0 "virtio,bridge=${VM_BRIDGE}" \
  --scsihw virtio-scsi-pci \
  --boot order=scsi0 \
  --serial0 socket \
  --vga std

qm importdisk "${VMID}" "${IMG_TMP}" "${VM_STORAGE}" --format qcow2 >/dev/null
qm set "${VMID}" --scsi0 "${VM_STORAGE}:vm-${VMID}-disk-0,discard=on,ssd=1" >/dev/null
qm resize "${VMID}" scsi0 "${VM_DISK_GB}G" >/dev/null
qm set "${VMID}" \
  --ide2 "${VM_STORAGE}:cloudinit" \
  --ipconfig0 ip=dhcp \
  --ciuser ubuntu \
  --cipassword ubuntu >/dev/null
qm set "${VMID}" --description "SweetHome3D-MCP Web-Desktop (Ubuntu 24.04 + XFCE + noVNC :6080 + MCP :9877). Inner-Setup: siehe README." >/dev/null

# --- Cloud-Init Auto-Install (Innen-Setup läuft beim ersten Boot) ---
if [ "${AUTO_INSTALL}" = "1" ]; then
  msg_info "Aktiviere Auto-Install per Cloud-Init (VNCPASS gesetzt, Log: /var/log/sweethome3d-install.log)"
  SNIP_STORE="${VM_ISO_STORAGE}"
  if ! pvesm status --storage "${SNIP_STORE}" 2>/dev/null | grep -q snippets; then
    SNIP_STORE=$(pvesm status -content snippets 2>/dev/null | awk 'NR>1 {print $1}' | head -n1)
    [ -z "${SNIP_STORE}" ] && SNIP_STORE="local"
  fi
  SNIP_DIR=$(pvesm path "${SNIP_STORE}:snippets" 2>/dev/null || echo "/var/lib/vz/snippets")
  mkdir -p "${SNIP_DIR}"
  SNIP_FILE="${SNIP_DIR}/sweethome3d-${VMID}-user.yaml"
  # VNCPASS escapen (einfache Anführungszeichen verdoppeln für YAML single-quotes)
  SAFE_PASS=$(printf "%s" "${VNCPASS}" | sed "s/'/''/g")
  cat > "${SNIP_FILE}" <<EOF2
#cloud-config
hostname: 3d-home
manage_etc_hosts: true
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: 'ubuntu'
ssh_pwauth: true
packages:
  - qemu-guest-agent
  - curl
  - wget
  - sudo
runcmd:
  - systemctl enable --now qemu-guest-agent || true
  - export DEBIAN_FRONTEND=noninteractive VNCPASS='${SAFE_PASS}'
  - curl -fsSL -o /root/sweethome3d-mcp-install.sh '${INSTALL_URL}'
  - chmod +x /root/sweethome3d-mcp-install.sh
  - bash /root/sweethome3d-mcp-install.sh > /var/log/sweethome3d-install.log 2>&1 || true
EOF2
  qm set "${VMID}" --cicustom "user=${SNIP_STORE}:snippets/sweethome3d-${VMID}-user.yaml" >/dev/null
  msg_ok "Auto-Install aktiv (${SNIP_STORE}:snippets/sweethome3d-${VMID}-user.yaml)"
else
  msg_info "AUTO_INSTALL=0 – VM wird nur erstellt, Innen-Setup manuell."
fi

msg_ok "VM ${VMID} erstellt"

# --- Starten ---
qm start "${VMID}" >/dev/null 2>&1 || msg_info "Autostart übersprungen – bitte manuell starten."
sleep 5
qm status "${VMID}" || true

# --- Auf Guest-Agent IP warten (max ~5 Min) ---
GUEST_IP=""
if [ "${AUTO_INSTALL}" = "1" ]; then
  msg_info "Warte auf Cloud-Init IP via Guest-Agent (bis zu 5 Min)..."
  for i in $(seq 1 60); do
    GUEST_IP=$(qm guest cmd "${VMID}" network-get-interfaces 2>/dev/null | grep -o '"ip-address"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | grep -v '^127\.' | grep -v '^169\.254\.' | head -n1 || true)
    if [ -n "${GUEST_IP}" ]; then break; fi
    sleep 5
  done
  if [ -n "${GUEST_IP}" ]; then msg_ok "VM-IP: ${GUEST_IP}"; else msg_info "Noch keine IP – Proxmox → VM ${VMID} → Summary/QEMU Guest Agent prüfen."; fi
fi

clear
header_info
echo -e "${GN}✔ VM fertig — ${VM_NAME} (${VMID})${CL}\n"
echo -e "${YW}VMID:${CL}  ${VMID}"
echo -e "${YW}Name:${CL}  ${VM_NAME}"
echo -e "${YW}Specs:${CL} ${VM_CPU} vCPU / ${VM_RAM}MB RAM / ${VM_DISK_GB}G Disk"
if [ -n "${GUEST_IP:-}" ]; then
  echo -e "${YW}VM-IP:${CL} ${GUEST_IP}"
  echo -e "${YW}Web (in ~10-15 Min):${CL} http://${GUEST_IP}:6080/vnc.html"
  echo -e "${YW}MCP (nach Setup):${CL} http://${GUEST_IP}:9877/mcp"
fi
echo ""
if [ "${AUTO_INSTALL}" = "1" ]; then
  echo -e "${BL}Auto-Install läuft:${CL} Innen-Setup startet beim ersten Boot automatisch."
  echo "  Log in der VM: tail -f /var/log/sweethome3d-install.log"
  echo "  Login: ubuntu / ubuntu (bitte ändern!), VNC-Pass: ${VNCPASS}"
  echo "  Fertig wenn: http://VM-IP:6080/vnc.html erreichbar ist."
  echo ""
  echo -e "${BL}Falls es hängt, manuell in der VM (erst sudo -i):${CL}"
else
  echo -e "${BL}So geht's weiter:${CL}"
  echo "  1) Proxmox → VM ${VMID} → Console/Cloud-Init IP abwarten (DHCP)."
  echo "     Login: ubuntu / ubuntu (bitte nach erstem Login ändern!)"
  echo "  2) In der VM anmelden (ubuntu/ubuntu), dann als root das Innen-Setup starten:"
fi
echo "     sudo -i"
echo "     curl -fsSL -o sweethome3d-mcp-install.sh \\"
echo "       https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/install/sweethome3d-mcp-install.sh"
echo "     chmod +x sweethome3d-mcp-install.sh && bash sweethome3d-mcp-install.sh"
echo "  3) Danach Browser: http://VM-IP:6080/vnc.html, MCP: http://VM-IP:9877/mcp"
echo ""
echo -e "${BL}Hinweis:${CL} Falls VMID ${VMID} belegt gewesen wäre, wurde automatisch hochgezählt."
echo "  Mit VM_ID=250 bash create-vm.sh kannst du eine Wunsch-ID vorgeben."
