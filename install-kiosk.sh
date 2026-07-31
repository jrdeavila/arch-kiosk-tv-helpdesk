#!/usr/bin/env bash
# ===========================================================================
#  install-kiosk.sh — instala Arch en un equipo dedicado a mostrar UNA página
#  web a pantalla completa en un televisor. Nada más: sin escritorio, sin
#  sesión de usuario que tocar, sin teclado después del primer arranque.
#
#  Se ejecuta DESDE EL LIVE ISO de Arch, por SSH, con la red por cable ya
#  levantada:
#
#      curl -fsSL -O https://raw.githubusercontent.com/jrdeavila/arch-kiosk-tv-helpdesk/main/install-kiosk.sh
#      less install-kiosk.sh              # léelo: formatea un disco entero
#      DISK=/dev/sda bash install-kiosk.sh
#
#  Va en dos etapas dentro del mismo fichero: la primera particiona y hace el
#  pacstrap, luego se copia a /mnt/root y se relanza a sí misma dentro del
#  arch-chroot con --chroot. No hay dos ficheros que sincronizar.
#
#  NO es idempotente: formatea. Si algo sale mal a mitad, se vuelve a lanzar
#  entero desde el live.
# ===========================================================================
set -euo pipefail

# --- Configuración ---------------------------------------------------------
# Todo se puede sobreescribir por entorno:  DISK=/dev/nvme0n1 URL=... bash install-kiosk.sh
: "${DISK:=}"                            # obligatorio. /dev/sda, /dev/nvme0n1...
: "${URL:=https://helpdesk.ccvalledupar.org.co}"   # la página del televisor
: "${KIOSK_HOST:=kiosco}"                # hostname
: "${ADMIN_USER:=jricardo}"              # usuario con sudo y ssh (tú)
: "${KIOSK_USER:=kiosco}"                # usuario sin privilegios que abre el navegador
: "${IP_MODE:=static}"                   # static | dhcp
: "${IP_ADDR:=192.168.0.200/24}"         # solo si IP_MODE=static. FUERA del pool DHCP
: "${IP_GW:=192.168.0.100}"
: "${IP_DNS:=8.8.8.8 8.8.4.4}"
: "${TIMEZONE:=America/Bogota}"
: "${LOCALE:=es_CO.UTF-8}"
: "${KEYMAP:=la-latin1}"

say()  { printf '\n\033[1;36m::\033[0m \033[1m%s\033[0m\n' "$*"; }
ok()   { printf '   \033[32m✓\033[0m %s\n' "$*"; }
inf()  { printf '   \033[90m·\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ===========================================================================
#  AYUDA — toda la documentación viaja dentro del script, para no depender de
#  tener el README a mano en el equipo destino.
# ===========================================================================
if [ "${1:-}" = "--ayuda" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
cat <<AYUDA

  install-kiosk.sh — Arch Linux en un equipo que solo muestra una página web
  a pantalla completa en un televisor.

  ---------------------------------------------------------------------------
  1. EN EL EQUIPO DESTINO (teclado y pantalla, una sola vez)
  ---------------------------------------------------------------------------

  Arranca el live ISO de Arch y conecta el cable de red. Luego:

      ip -brief link                  # mira cómo se llama: enp3s0, eno1...

  Si hay DHCP, ya tendrás IP; compruébalo con 'ip -brief address'. Si NO hay
  DHCP, o quieres usar desde ya la dirección definitiva:

      ip link set enp3s0 up
      ip address add $IP_ADDR dev enp3s0
      ip route add default via $IP_GW
      resolvectl dns enp3s0 $IP_DNS
      ping -c3 archlinux.org          # el DNS hace falta para el pacstrap

  Ponle contraseña a root si vas a entrar por SSH desde otro equipo:

      passwd

  ---------------------------------------------------------------------------
  2. LANZARLO DESDE EL USB
  ---------------------------------------------------------------------------

  Monta el USB FUERA de /mnt (/mnt es la raíz del sistema que se va a instalar)
  y ejecútalo desde ahí: así el log se escribe directamente en el USB.

      lsblk -o NAME,SIZE,RM,FSTYPE,MOUNTPOINTS    # el extraíble lleva RM=1
      mount /dev/sdb1 /tmp/usb --mkdir
      cd /tmp/usb
      lsblk                                       # identifica el disco destino

      DISK=/dev/sda bash install-kiosk.sh

  Pide escribir el nombre del disco para confirmar el borrado, y una contraseña
  (dos veces) que valdrá para root y para $ADMIN_USER. A partir de ahí va solo:
  tarda lo que tarde el pacstrap.

  Al terminar:  reboot   (y quita el USB)

  ---------------------------------------------------------------------------
  3. VARIABLES  (todas por entorno, delante del 'bash install-kiosk.sh')
  ---------------------------------------------------------------------------

      DISK          OBLIGATORIA. /dev/sda, /dev/nvme0n1...
      URL           $URL
      KIOSK_HOST    $KIOSK_HOST
      ADMIN_USER    $ADMIN_USER          (sudo + ssh)
      KIOSK_USER    $KIOSK_USER          (abre el navegador, sin privilegios)
      IP_MODE       $IP_MODE             (static | dhcp)
      IP_ADDR       $IP_ADDR
      IP_GW         $IP_GW
      IP_DNS        $IP_DNS
      TIMEZONE      $TIMEZONE
      LOCALE        $LOCALE
      KEYMAP        $KEYMAP
      LOG           fuerza dónde escribir el log

  OJO CON LAS DOS IP: la del live ISO es temporal y es a la que haces ssh
  durante la instalación. IP_ADDR es la estática que se escribe en el sistema
  instalado y NO entra en vigor hasta reiniciar. Si al live le pones ya la
  misma, la dirección no cambia en ningún momento.

  ---------------------------------------------------------------------------
  4. SI FALLA
  ---------------------------------------------------------------------------

  Deja un log con la traza de cada orden, incluida la etapa del chroot, más un
  diagnóstico (lsblk, montajes, red, pacman.log, dmesg). Acaba:

    - Junto al script, si lo lanzaste desde el USB. Ya lo tienes.
    - Si no, en /tmp (que es RAM) y al fallar intenta copiarlo solo a un USB
      extraíble escribible. Si no encuentra ninguno, te dice cómo hacerlo.

  Si la instalación va bien, queda también dentro del equipo en
  /var/log/kiosco-install.log

  NO es idempotente: formatea. Si algo sale mal a mitad, se relanza entero.

  ---------------------------------------------------------------------------
  5. DESPUÉS
  ---------------------------------------------------------------------------

      ssh $ADMIN_USER@${IP_ADDR%%/*}
      ssh-copy-id $ADMIN_USER@${IP_ADDR%%/*}      # y quita PasswordAuthentication

      # cambiar la página del televisor:
      sudoedit /etc/kiosco.conf && sudo systemctl restart greetd

  En la BIOS del HP: "Restore on AC power loss" -> "Power On", para que tras un
  corte de luz vuelva solo sin que nadie pulse el botón.

  El montaje es greetd (autologin sin greeter) -> cage (compositor Wayland de
  una sola ventana) -> chromium --kiosk. Si el navegador se cae, cage termina,
  greetd relanza la sesión y la pantalla vuelve sola.

AYUDA
exit 0
fi

# ===========================================================================
#  ETAPA 2 — dentro del arch-chroot
# ===========================================================================
if [ "${1:-}" = "--chroot" ]; then
  # La salida ya la captura el tee de la etapa 1 (arch-chroot hereda los fd).
  # La traza detallada va aparte, a un fichero que la etapa 1 pega al log.
  exec 3>>/root/.kiosk-trace
  BASH_XTRACEFD=3
  PS4='+ chroot:${LINENO}: '
  set -x
  trap 'printf "\n\033[1;31m✗\033[0m etapa chroot, línea %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

  # shellcheck disable=SC1091
  . /root/.kiosk-env
  PASS="$(cat /root/.kiosk-pass)"

  say "Hora, idioma y teclado"
  ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  hwclock --systohc
  sed -i "s/^#\(${LOCALE} \)/\1/;s/^#\(en_US.UTF-8 \)/\1/" /etc/locale.gen
  locale-gen
  echo "LANG=$LOCALE"    > /etc/locale.conf
  echo "KEYMAP=$KEYMAP"  > /etc/vconsole.conf
  ok "$TIMEZONE, $LOCALE, teclado $KEYMAP"

  say "Nombre del equipo"
  echo "$KIOSK_HOST" > /etc/hostname
  cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${KIOSK_HOST}.localdomain ${KIOSK_HOST}
EOF
  ok "$KIOSK_HOST"

  say "Usuarios"
  # Dos usuarios a propósito: si algún día se cuelan por el navegador, caen en
  # una cuenta sin sudo y sin nada que robar.
  useradd -m -G wheel -s /bin/bash "$ADMIN_USER"
  { set +x; } 2>/dev/null          # sin traza: la contraseña no debe ir al log
  echo "root:$PASS" | chpasswd
  echo "$ADMIN_USER:$PASS" | chpasswd
  set -x
  useradd -m -s /bin/bash "$KIOSK_USER"
  passwd -l "$KIOSK_USER" >/dev/null    # sin contraseña: greetd lo entra sin autenticar
  echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
  chmod 440 /etc/sudoers.d/wheel
  visudo -c >/dev/null || die "sudoers inválido"
  ok "$ADMIN_USER (sudo, ssh) y $KIOSK_USER (navegador, sin privilegios)"

  say "Red por cable"
  if [ "$IP_MODE" = static ]; then
    { printf '[Match]\nType=ether\n\n[Network]\nAddress=%s\nGateway=%s\n' "$IP_ADDR" "$IP_GW"
      for d in $IP_DNS; do printf 'DNS=%s\n' "$d"; done
      printf '\n[Link]\nRequiredForOnline=routable\n'
    } > /etc/systemd/network/20-cable.network
    inf "estática $IP_ADDR vía $IP_GW"
  else
    cat > /etc/systemd/network/20-cable.network <<'EOF'
[Match]
Type=ether

[Network]
DHCP=ipv4

[DHCPv4]
UseDNS=yes

[Link]
RequiredForOnline=routable
EOF
    inf "DHCP"
  fi
  chmod 644 /etc/systemd/network/20-cable.network
  # Sin este symlink no hay resolución de nombres, aunque la IP esté bien.
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  ok "systemd-networkd (Type=ether: da igual cómo se llame la interfaz)"

  say "SSH"
  # El sshd de un Arch instalado NO deja entrar a root con contraseña, a
  # diferencia del live. Se entra con $ADMIN_USER.
  cat > /etc/ssh/sshd_config.d/10-kiosco.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication yes
EOF
  ok "acceso como $ADMIN_USER (copia tu llave con ssh-copy-id y quita el password)"

  say "Arranque"
  if [ -d /sys/firmware/efi ]; then
    bootctl install
    # ROOTUUID viene de la etapa 1: dentro del arch-chroot, /proc es el del live
    # ISO, así que findmnt / devolvería la raíz equivocada.
    cat > /boot/loader/loader.conf <<'EOF'
default arch.conf
timeout 0
console-mode max
EOF
    cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux (kiosco)
linux   /vmlinuz-linux
initrd  /$UCODE_IMG
initrd  /initramfs-linux.img
options root=UUID=$ROOTUUID rw quiet loglevel=3 consoleblank=0
EOF
    ok "systemd-boot, sin menú (timeout 0)"
  else
    grub-install --target=i386-pc "$DISK"
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 consoleblank=0"/' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
    ok "GRUB en $DISK (BIOS legacy)"
  fi

  say "El kiosco"
  # La URL vive aquí y en ningún otro sitio: cambiarla es editar este fichero
  # y reiniciar greetd, sin tocar configuración del sistema.
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

  # cage: compositor Wayland que solo sabe enseñar una ventana a pantalla
  # completa. initial_session de greetd = autologin al arrancar, sin greeter.
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

  say "Servicios"
  systemctl enable systemd-networkd systemd-resolved sshd greetd
  systemctl is-enabled systemd-networkd systemd-resolved sshd greetd >/dev/null \
    || die "algún servicio no quedó habilitado"
  ok "networkd, resolved, sshd, greetd"

  rm -f /root/.kiosk-pass /root/.kiosk-env
  exit 0
fi

# ===========================================================================
#  ETAPA 1 — en el live ISO
# ===========================================================================

# --- Log -------------------------------------------------------------------
# El live ISO vive en RAM: si esto falla y se reinicia, el log se pierde. Así
# que se escribe donde sobreviva, y al fallar se intenta copiar a un USB.
if [ -z "${LOG:-}" ]; then
  _d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo /tmp)"
  # Si el script se lanzó desde un USB, el log se queda ahí mismo.
  if [ -w "$_d" ] && ! findmnt -no FSTYPE --target "$_d" 2>/dev/null |
       grep -qE 'tmpfs|overlay|ramfs|iso9660|squashfs'; then
    LOG="$_d/kiosco-install-$(date +%Y%m%d-%H%M%S).log"
  else
    LOG="/tmp/kiosco-install-$(date +%Y%m%d-%H%M%S).log"
  fi
fi
: > "$LOG"

# Prompts y avisos van a la terminal real, no al tee. Si no hay terminal
# (script redirigido, sin tty), se cae con elegancia a stderr/stdin.
# El 2>/dev/null va primero a propósito: si no, el error de apertura de
# /dev/tty se imprime antes de que la redirección lo pueda silenciar.
if : 2>/dev/null > /dev/tty;   then TTY_OUT=/dev/tty; TTY_IN=/dev/tty
else                              TTY_OUT=/dev/stderr; TTY_IN=/dev/stdin; fi

exec 3>>"$LOG"                   # fd 3: solo al fichero, sin ensuciar la pantalla
BASH_XTRACEFD=3
PS4='+ ${LINENO}: '
set -x
exec > >(tee -a "$LOG") 2>&1         # todo lo demás: pantalla Y fichero

# Copia el log a un USB conectado, si lo hay. Es best-effort: nunca falla.
#
# Se filtra por RM=1 (extraíble) y no por TRAN=usb: TRAN solo lo lleva el disco
# padre, en las particiones viene vacío. Y se lee en formato -P (pares
# clave="valor") porque en modo raw los campos vacíos se colapsan y descuadran
# las posiciones.
rescatar_log() {
  local punto=/tmp/kiosco-usb linea disco
  disco="$(basename "${DISK:-nada}")"
  while read -r linea; do
    local NAME='' FSTYPE='' TYPE='' PKNAME='' RM=''
    eval "$linea"
    [ "$TYPE" = part ] || continue
    [ "$RM" = 1 ]      || continue
    [ "$PKNAME" != "$disco" ] || continue   # jamás el disco que estamos instalando
    case "$FSTYPE" in vfat|exfat|ntfs|ext2|ext3|ext4) ;; *) continue ;; esac
    mkdir -p "$punto" 2>/dev/null || continue
    if mount "/dev/$NAME" "$punto" 2>/dev/null; then
      # El USB del propio ISO monta en solo lectura: el cp falla y se sigue.
      if cp "$LOG" "$punto/" 2>/dev/null; then
        sync; umount "$punto" 2>/dev/null
        printf '   \033[32m✓\033[0m log copiado al USB /dev/%s como %s\n' \
          "$NAME" "$(basename "$LOG")" > "$TTY_OUT"
        return 0
      fi
      umount "$punto" 2>/dev/null
    fi
  done < <(lsblk -Pno NAME,FSTYPE,TYPE,PKNAME,RM 2>/dev/null)
  return 1
}

al_salir() {
  local st=$1
  set +x
  set +e    # el diagnóstico es best-effort: un grep sin coincidencias o un
            # dmesg restringido no pueden abortar el volcado a medias.
  # La traza de la etapa 2 vive dentro del sistema instalado; recógela mientras
  # /mnt siga montado.
  if [ -f /mnt/root/.kiosk-trace ]; then
    { echo "--- traza de la etapa chroot ---"; cat /mnt/root/.kiosk-trace; } >&3
    rm -f /mnt/root/.kiosk-trace
  fi

  if [ "$st" != 0 ]; then
    {
      echo "--- diagnóstico (salida $st) ---"
      echo "== lsblk";        lsblk -f 2>&1
      echo "== montajes";     mount | grep -E '/mnt' 2>&1
      echo "== red";          ip -brief address 2>&1; networkctl status 2>&1
      echo "== pacman";       tail -n 40 /mnt/var/log/pacman.log 2>&1
      echo "== dmesg";        dmesg | tail -n 50 2>&1
    } >&3 2>&3
    printf '\n\033[1;31m✗ Falló.\033[0m Log completo en: \033[1m%s\033[0m\n' "$LOG" > "$TTY_OUT"
    if ! rescatar_log; then
      cat > "$TTY_OUT" <<AYUDA

   No hay ningún USB escribible conectado. Para llevarte el log, conecta uno y:

       lsblk -o NAME,SIZE,RM,FSTYPE,MOUNTPOINTS   # el extraíble lleva RM=1
       mount /dev/sdX1 /tmp/usb --mkdir
       cp $LOG /tmp/usb/
       umount /tmp/usb

   Móntalo en /tmp/usb y no en /mnt: /mnt es la raíz del sistema que se está
   instalando.

AYUDA
    fi
  fi
  exec 3>&-
}
trap 'al_salir $?' EXIT

[ "$(id -u)" = 0 ] || die "Esto va como root, desde el live ISO."
[ -f /usr/bin/pacstrap ] || die "Esto se ejecuta desde el live ISO de Arch, no desde un sistema instalado."
[ -n "$DISK" ] || die "Falta DISK. Mira 'lsblk' y lanza:  DISK=/dev/sda URL=https://... bash $0"
[ -b "$DISK" ] || die "$DISK no es un dispositivo de bloque."

say "Comprobando la red"
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "Sin red. Repasa 'ip -brief address' y 'networkctl status'."
ok "hay salida a Internet"

say "Disco de destino"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS,MODEL "$DISK"
echo
# Los prompts van directos a la tty: stdout está detrás de un tee y el orden
# con respecto a read no está garantizado.
printf '   \033[1;31mSe va a BORRAR ENTERO %s.\033[0m\n' "$DISK" > "$TTY_OUT"
printf '   Escribe el nombre del disco (%s) para confirmar: ' "$(basename "$DISK")" > "$TTY_OUT"
read -r confirm < "$TTY_IN"
[ "$confirm" = "$(basename "$DISK")" ] || die "Cancelado."

printf '\n   Contraseña para root y para %s: ' "$ADMIN_USER" > "$TTY_OUT"
read -rs PASS < "$TTY_IN"; echo > "$TTY_OUT"
printf '   Otra vez: ' > "$TTY_OUT"
read -rs PASS2 < "$TTY_IN"; echo > "$TTY_OUT"
[ -n "$PASS" ] || die "Contraseña vacía."
[ "$PASS" = "$PASS2" ] || die "No coinciden."
case "$PASS" in *:*) die "La contraseña no puede llevar ':' (chpasswd lo usa de separador)." ;; esac

# nvme0n1 -> nvme0n1p1 ;  sda -> sda1
part() { case "$DISK" in *[0-9]) echo "${DISK}p$1" ;; *) echo "${DISK}$1" ;; esac; }

if [ -d /sys/firmware/efi ]; then FIRMWARE=uefi; else FIRMWARE=bios; fi
inf "firmware: $FIRMWARE"

say "Particionando $DISK"
umount -R /mnt 2>/dev/null || true
sgdisk --zap-all "$DISK" >/dev/null
if [ "$FIRMWARE" = uefi ]; then
  sgdisk -n1:0:+1G   -t1:ef00 -c1:ESP  "$DISK" >/dev/null
  sgdisk -n2:0:0     -t2:8300 -c2:root "$DISK" >/dev/null
else
  sgdisk -a1 -n1:24K:+1000K -t1:ef02 -c1:bios "$DISK" >/dev/null
  sgdisk -n2:0:0            -t2:8300 -c2:root "$DISK" >/dev/null
fi
partprobe "$DISK"
udevadm settle
ok "$(part 1) + $(part 2)"

say "Formateando"
if [ "$FIRMWARE" = uefi ]; then
  mkfs.fat -F32 "$(part 1)" >/dev/null
fi
mkfs.ext4 -F -L root "$(part 2)" >/dev/null
mount "$(part 2)" /mnt
if [ "$FIRMWARE" = uefi ]; then
  mount --mkdir "$(part 1)" /mnt/boot
fi
ROOTUUID="$(blkid -s UUID -o value "$(part 2)")"
ok "raíz ext4 montada en /mnt"

say "Instalando el sistema base"
timedatectl set-ntp true

# Microcódigo según la CPU: en un HP de escritorio será Intel o AMD.
if grep -qm1 'GenuineIntel' /proc/cpuinfo; then
  UCODE=intel-ucode; UCODE_IMG=intel-ucode.img
else
  UCODE=amd-ucode;   UCODE_IMG=amd-ucode.img
fi
inf "microcódigo: $UCODE"

PKGS=(
  base linux linux-firmware "$UCODE"
  openssh sudo vim
  mesa                       # aceleración de vídeo; chromium sin esto va a tirones
  cage chromium greetd       # el kiosco en sí
  ttf-dejavu noto-fonts noto-fonts-emoji
)
if [ "$FIRMWARE" = bios ]; then
  PKGS+=(grub)
fi

pacstrap -K /mnt "${PKGS[@]}"
genfstab -U /mnt >> /mnt/etc/fstab
ok "$(echo "${PKGS[@]}" | wc -w) paquetes"

say "Configurando el sistema instalado"
{
  printf 'URL=%q\n'         "$URL"
  printf 'KIOSK_HOST=%q\n'  "$KIOSK_HOST"
  printf 'ADMIN_USER=%q\n'  "$ADMIN_USER"
  printf 'KIOSK_USER=%q\n'  "$KIOSK_USER"
  printf 'IP_MODE=%q\n'     "$IP_MODE"
  printf 'IP_ADDR=%q\n'     "$IP_ADDR"
  printf 'IP_GW=%q\n'       "$IP_GW"
  printf 'IP_DNS=%q\n'      "$IP_DNS"
  printf 'TIMEZONE=%q\n'    "$TIMEZONE"
  printf 'LOCALE=%q\n'      "$LOCALE"
  printf 'KEYMAP=%q\n'      "$KEYMAP"
  printf 'DISK=%q\n'        "$DISK"
  printf 'UCODE_IMG=%q\n'   "$UCODE_IMG"
  printf 'ROOTUUID=%q\n'    "$ROOTUUID"
} > /mnt/root/.kiosk-env
{ set +x; } 2>/dev/null            # sin traza: si no, la contraseña acaba en el log
printf '%s' "$PASS" > /mnt/root/.kiosk-pass
set -x
chmod 600 /mnt/root/.kiosk-env /mnt/root/.kiosk-pass

install -m 755 "$0" /mnt/root/install-kiosk.sh
arch-chroot /mnt bash /root/install-kiosk.sh --chroot
rm -f /mnt/root/install-kiosk.sh

say "Listo"
# La traza de la etapa 2 vive dentro del sistema instalado: hay que recogerla
# ANTES de desmontar (el trap de salida corre demasiado tarde para esto).
if [ -f /mnt/root/.kiosk-trace ]; then
  { echo "--- traza de la etapa chroot ---"; cat /mnt/root/.kiosk-trace; } >&3
  rm -f /mnt/root/.kiosk-trace
fi
# Y una copia del log dentro del propio equipo, para consultarlo por SSH
# cuando ya no haya USB de por medio.
cp "$LOG" /mnt/var/log/kiosco-install.log 2>/dev/null || true
umount -R /mnt
inf "log: $LOG  (copia en /var/log/kiosco-install.log del equipo)"
cat <<EOF

   Quita el USB y reinicia:  reboot

   Al arrancar debería salir la página directamente en el televisor.
   Desde tu PC, para administrarlo:

       ssh ${ADMIN_USER}@$([ "$IP_MODE" = static ] && echo "${IP_ADDR%%/*}" || echo "<ip>")
       ssh-copy-id ${ADMIN_USER}@...        # y luego quita PasswordAuthentication

   Para cambiar la página:  sudoedit /etc/kiosco.conf && sudo systemctl restart greetd

   En la BIOS del HP, pon "Restore on AC power loss" en "Power On": así tras un
   corte de luz el televisor recupera la página sin que nadie pulse el botón.

EOF
