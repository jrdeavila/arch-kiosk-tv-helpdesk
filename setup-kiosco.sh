#!/usr/bin/env bash
# ===========================================================================
#  setup-kiosco.sh — convierte un Arch YA INSTALADO en el kiosco del televisor.
#
#  Para cuando el sistema base ya está puesto (por archinstall, a mano, o
#  porque install-kiosk.sh se quedó a medias) y solo falta el navegador a
#  pantalla completa, los drivers de vídeo y los servicios.
#
#  Se ejecuta EN el equipo, como root:
#
#      bash setup-kiosco.sh              # drivers + kiosco, sin tocar la red
#      bash setup-kiosco.sh --red        # además, deja la red estática
#      bash setup-kiosco.sh --ayuda
#
#  SÍ es idempotente, al revés que install-kiosk.sh: se puede repetir tantas
#  veces como haga falta.
# ===========================================================================
set -euo pipefail

: "${URL:=https://helpdesk.ccvalledupar.org.co}"
: "${KIOSK_USER:=kiosco}"
: "${IP_ADDR:=192.168.0.200/23}"     # /23: la red de la oficina es 255.255.254.0
: "${IP_GW:=192.168.0.100}"
: "${IP_DNS:=8.8.8.8 8.8.4.4}"

say()  { printf '\n\033[1;36m::\033[0m \033[1m%s\033[0m\n' "$*"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$*"; }
inf()  { printf '   \033[90m·\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

CONFIG_RED=0
case "${1:-}" in
  --red)    CONFIG_RED=1 ;;
  --ayuda|-h|--help)
    cat <<AYUDA

  setup-kiosco.sh — termina un Arch ya instalado y lo deja como kiosco.

  Instala los drivers de vídeo que toquen (Intel / AMD / NVIDIA, detectados
  con lspci), cage, chromium y greetd; crea el usuario sin privilegios que
  abre el navegador, y habilita los servicios.

      bash setup-kiosco.sh          drivers + kiosco, sin tocar la red
      bash setup-kiosco.sh --red    además deja la red estática en $IP_ADDR

  Variables:  URL=$URL
              KIOSK_USER=$KIOSK_USER
              IP_ADDR=$IP_ADDR  IP_GW=$IP_GW  IP_DNS=$IP_DNS

  Es idempotente: repetirlo no rompe nada.

  Al terminar:  systemctl start greetd    (o reiniciar)

AYUDA
    exit 0 ;;
  "") ;;
  *) die "opción desconocida: $1  (prueba --ayuda)" ;;
esac

[ "$(id -u)" = 0 ] || die "Esto va como root:  sudo bash $0 ${1:-}"
command -v pacman >/dev/null || die "Esto solo vale para Arch."

# --- 1. Drivers de vídeo ---------------------------------------------------
say "Drivers de vídeo"
GPU="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
inf "${GPU:-no se detectó GPU en lspci}"

DRV=(mesa)
if   grep -qi 'intel'          <<<"$GPU"; then DRV+=(vulkan-intel  intel-media-driver libva-intel-driver)
elif grep -qiE 'amd|radeon|ati' <<<"$GPU"; then DRV+=(vulkan-radeon libva-mesa-driver)
elif grep -qi 'nvidia'         <<<"$GPU"; then DRV+=(nvidia nvidia-utils)
fi
inf "paquetes: ${DRV[*]}"

# --- 2. Paquetes del kiosco ------------------------------------------------
say "Instalando paquetes"
pacman -Sy --needed --noconfirm "${DRV[@]}" \
  cage chromium greetd \
  ttf-dejavu noto-fonts noto-fonts-emoji \
  openssh
ok "drivers, cage, chromium, greetd, fuentes y openssh"

# --- 3. Usuario del navegador ----------------------------------------------
say "Usuario $KIOSK_USER"
if id "$KIOSK_USER" >/dev/null 2>&1; then
  inf "ya existe"
else
  useradd -m -s /bin/bash "$KIOSK_USER"
  ok "creado"
fi
# Sin contraseña y sin sudo: greetd lo entra sin autenticar, y si algún día se
# cuelan por el navegador caen en una cuenta sin nada que robar.
passwd -l "$KIOSK_USER" >/dev/null 2>&1 || true

# --- 4. La página ----------------------------------------------------------
say "El kiosco"
cat > /etc/kiosco.conf <<EOF
# Página que muestra el televisor. Tras cambiarla:  systemctl restart greetd
URL=$URL
EOF

cat > /usr/local/bin/kiosco-navegador <<'EOF'
#!/usr/bin/env bash
# Lanza el navegador a pantalla completa. Si se cae, cage termina, greetd
# relanza la sesión y la pantalla vuelve sola: el reinicio es gratis.
set -eu
. /etc/kiosco.conf
exec chromium \
  --kiosk "$URL" \
  --ozone-platform=wayland \
  --incognito \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --no-first-run \
  --password-store=basic \
  --check-for-update-interval=31536000
EOF
chmod 755 /usr/local/bin/kiosco-navegador

mkdir -p /etc/greetd
cat > /etc/greetd/config.toml <<EOF
# Kiosco: sin greeter y sin menú. Arranca, entra solo y abre el navegador.
[terminal]
vt = 1

[initial_session]
command = "cage -s -- /usr/local/bin/kiosco-navegador"
user = "$KIOSK_USER"
EOF
ok "cage + chromium en $URL"

# --- 5. Red (opcional) -----------------------------------------------------
if [ "$CONFIG_RED" = 1 ]; then
  say "Red estática"
  # NetworkManager y networkd se pelean por la misma interfaz: solo uno.
  if systemctl is-enabled NetworkManager >/dev/null 2>&1; then
    systemctl disable --now NetworkManager
    inf "NetworkManager desactivado"
  fi
  { printf '[Match]\nType=ether\n\n[Network]\nAddress=%s\nGateway=%s\n' "$IP_ADDR" "$IP_GW"
    for d in $IP_DNS; do printf 'DNS=%s\n' "$d"; done
    printf '\n[Link]\nRequiredForOnline=routable\n'
  } > /etc/systemd/network/20-cable.network
  chmod 644 /etc/systemd/network/20-cable.network
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  systemctl enable systemd-networkd systemd-resolved
  ok "$IP_ADDR vía $IP_GW, DNS $IP_DNS"
else
  inf "red sin tocar (usa --red para dejarla estática en $IP_ADDR)"
fi

# --- 6. Servicios ----------------------------------------------------------
say "Servicios"
systemctl enable sshd greetd
# Que la red esté habilitada es lo que evita que el equipo desaparezca al
# reiniciar: es el fallo más común de una instalación a medias.
for s in systemd-networkd NetworkManager; do
  systemctl is-enabled "$s" >/dev/null 2>&1 && inf "$s: habilitado"
done
if ! systemctl is-enabled systemd-networkd NetworkManager >/dev/null 2>&1; then
  printf '   \033[33m!\033[0m NINGÚN gestor de red habilitado: al reiniciar te quedas sin red.\n'
  printf '       Lanza esto otra vez con --red, o habilita NetworkManager.\n'
fi
ok "sshd y greetd habilitados"

say "Listo"
cat <<EOF

   Para arrancar el kiosco ahora mismo, sin reiniciar:

       systemctl start greetd

   Comprobaciones:

       systemctl status greetd
       journalctl -u greetd -b --no-pager | tail -30

   Para cambiar la página:

       sudoedit /etc/kiosco.conf && systemctl restart greetd

EOF
