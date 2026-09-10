#!/usr/bin/env bash
#
# SweetHome3D-MCP – VM-Diagnose (auf dem PROXMOX-HOST als root)
#
# Einzeiler:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/proxmox/check-vm.sh)"
# Mit VMID:
#   VMID=155 bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/proxmox/check-vm.sh)"
#
# Prüft hostseitig alles was geht und gibt den exakten Diagnose-Block
# für die VM-Konsole aus. Bitte dessen Output bei Problemen mitschicken.
#
set -u

YW=$(echo "\033[33m"); BL=$(echo "\033[36m"); RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m"); CL=$(echo "\033[m"); CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"
msg_info()  { echo -e "  ${BL}●${CL} $1"; }
msg_ok()    { echo -e "  ${CM} $1"; }
msg_error() { echo -e "  ${CROSS} $1"; }

VMID="${VMID:-}"
if [ -z "${VMID}" ]; then
  VMID=$(qm list 2>/dev/null | grep -i "3D-Home" | awk '{print $1}' | head -n1 || true)
  [ -z "${VMID}" ] && { msg_error "Keine VM '3D-Home' gefunden – mit VMID=155 ... aufrufen."; exit 1; }
fi
echo -e "${YW}Prüfe VM ${VMID}${CL}\n"

msg_info "qm status:"
qm status "${VMID}" 2>&1 || true
echo ""

msg_info "qm config (cloud-init relevant):"
qm config "${VMID}" 2>&1 | grep -iE 'cicustom|ipconfig|ciuser|ide2|scsi0|agent|memory|cores' || true
echo ""

msg_info "Cloud-Init Snippet auf dem Host:"
ls -la /var/lib/vz/snippets/sweethome3d-"${VMID}"-user.yaml 2>&1 || true
echo ""

msg_info "IP via Guest-Agent:"
qm guest cmd "${VMID}" network-get-interfaces 2>/dev/null | grep -o '"ip-address"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | grep -v '^127\.' | grep -v '^169\.254\.' | head -n3 || echo "(noch keine IP vom Guest-Agent)"
echo ""

cat <<EOF2
==================== IN DER VM AUSFÜHREN ====================
Bitte in Proxmox → VM ${VMID} → Console einloggen (ubuntu/ubuntu)
und DIESEN Block am Stück einfügen + Output kopieren:

cloud-init status --long 2>&1 | head -20
echo ---INSTALL-LOG---
tail -n 60 /var/log/sweethome3d-install.log 2>&1
echo ---SERVICES---
systemctl is-active vncserver@1.service novnc.service 2>&1
echo ---PORTS---
(ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -E ':(6080|5901|9877)' || (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null)
echo ---FILES---
ls /opt/ 2>&1; ls /root/.eteks/sweethome3d/plugins/ 2>&1
echo ---VNC-JOURNAL---
journalctl -u vncserver@1 --no-pager -n 30 2>&1 | tail -30
=============================================================
EOF2
