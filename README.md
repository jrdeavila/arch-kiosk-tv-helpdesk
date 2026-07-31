# arch-kiosk-tv-helpdesk

Instala Arch Linux en un equipo dedicado que arranca y muestra **una** página web
a pantalla completa en un televisor. En origen, el helpdesk de la Cámara de
Comercio de Valledupar en un HP de escritorio.

Sin escritorio, sin greeter, sin sesión que tocar, sin teclado después del primer
arranque. Un solo script, una sola pasada, y el equipo queda administrable por SSH.

## Uso

Toda la documentación va también dentro del script, para no depender del README
en el equipo destino:

```sh
bash install-kiosk.sh --ayuda
```


Arranca el live ISO de Arch en el equipo destino y conéctalo **por cable**. Desde
la consola física, ponle contraseña a root para poder entrar por SSH:

```sh
passwd
ip -brief address          # apunta la IP que le haya dado el DHCP
```

Si tu red no tiene DHCP, dale una dirección a mano antes de seguir:

```sh
ip link set enp3s0 up
ip address add 192.168.0.200/24 dev enp3s0
ip route add default via 192.168.0.100
resolvectl dns enp3s0 8.8.8.8 8.8.4.4
ping -c3 archlinux.org     # el DNS hace falta para el pacstrap
```

Ya desde tu PC, por SSH, y dentro de `tmux` para que un corte no mate el pacstrap:

```sh
ssh root@<ip>
tmux new -s inst

curl -fsSL -O https://raw.githubusercontent.com/jrdeavila/arch-kiosk-tv-helpdesk/main/install-kiosk.sh
less install-kiosk.sh      # léelo antes: formatea un disco entero
lsblk                      # identifica el disco

DISK=/dev/sda bash install-kiosk.sh
```

Pide confirmación escribiendo el nombre del disco y una contraseña, y a partir de
ahí va solo. Al terminar, `reboot` y quita el USB.

**Ojo con las dos IP**, que se confunden con facilidad: la del live ISO es temporal
y es a la que haces `ssh` durante la instalación; `IP_ADDR` es la estática que el
script escribe en el sistema instalado y que no entra en vigor hasta reiniciar. Si
le pones al live la misma que va a llevar después, la dirección no cambia en ningún
momento y te ahorras el lío.

## Variables

| Variable | Por defecto | |
|---|---|---|
| `DISK` | — | **obligatoria**. `/dev/sda`, `/dev/nvme0n1`… |
| `URL` | `https://helpdesk.ccvalledupar.org.co` | la página del televisor |
| `KIOSK_HOST` | `kiosco` | hostname |
| `ADMIN_USER` | `jricardo` | usuario con sudo y SSH |
| `KIOSK_USER` | `kiosco` | usuario sin privilegios que abre el navegador |
| `IP_MODE` | `static` | `static` o `dhcp` |
| `IP_ADDR` | `192.168.0.200/24` | **fuera del pool DHCP del router** |
| `IP_GW` / `IP_DNS` | `192.168.0.100` y `8.8.8.8 8.8.4.4` | |
| `TIMEZONE` / `LOCALE` / `KEYMAP` | `America/Bogota`, `es_CO.UTF-8`, `la-latin1` | |

Detecta solo el firmware (systemd-boot en UEFI, GRUB en BIOS legacy), el
microcódigo (Intel o AMD) y el nombre de la interfaz de red (`Type=ether`).

## Si falla

El live ISO vive en RAM: al reiniciar se pierde todo. Por eso el script deja un
log completo, con traza de cada orden ejecutada (`set -x`), incluida la etapa de
dentro del chroot.

Dónde acaba, por orden:

1. **Junto al script**, si lo lanzaste desde un USB — es decir, si el directorio
   del script es escribible y no es tmpfs. Lo tienes ya en la mano.
2. Si no, en `/tmp/kiosco-install-<fecha>.log`, que es RAM. Al fallar, el script
   **busca un USB extraíble escribible y copia el log solo**, y te dice a cuál.
3. Si no hay ninguno, imprime las órdenes exactas para montar uno y copiarlo.

Además, cuando la instalación termina bien, el log queda dentro del propio equipo
en `/var/log/kiosco-install.log`, para consultarlo por SSH sin USB de por medio.

Junto al log, al fallar se vuelca un diagnóstico: `lsblk -f`, montajes, estado de
la red, las últimas 40 líneas de `pacman.log` del sistema a medio instalar y el
final de `dmesg`. Con eso suele bastar para saber qué pasó sin volver al equipo.

Con `LOG=/ruta/fichero.log` se fuerza dónde escribirlo.

La contraseña no aparece en el log: la traza se desactiva en los tramos que la
manejan.

## Cómo queda montado

`greetd` con `initial_session` entra solo al arrancar, sin greeter ni contraseña,
y lanza `cage` — un compositor Wayland que solo sabe enseñar una ventana a
pantalla completa — con Chromium en modo kiosco dentro.

Si Chromium se cae, cage termina, greetd relanza la sesión y la pantalla vuelve
sola. La recuperación sale gratis, sin watchdog.

```
/etc/kiosco.conf                  la URL, y nada más
/usr/local/bin/kiosco-navegador   chromium con sus flags
/etc/greetd/config.toml           autologin + cage
/etc/systemd/network/20-cable.network
```

## Después

```sh
ssh jricardo@192.168.0.200
ssh-copy-id jricardo@192.168.0.200    # y luego quita PasswordAuthentication

# cambiar la página
sudoedit /etc/kiosco.conf && sudo systemctl restart greetd
```

Dos cosas que no hace el script y conviene hacer a mano:

- En la BIOS del HP, **"Restore on AC power loss" → Power On**, para que tras un
  corte de luz vuelva solo.
- Reserva DHCP por MAC en el router, además de la IP estática. Redundante a
  propósito: si algún día alguien resetea el router, el equipo sigue localizable.

No pongas actualizaciones desatendidas. Un `pacman -Syu` automático en un equipo
sin pantalla útil es la forma más rápida de quedarte sin kiosco un lunes.
