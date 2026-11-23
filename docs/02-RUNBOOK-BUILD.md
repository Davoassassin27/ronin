# Runbook — construcción en QEMU (F0 → F6)

> **Regla de oro:** el SSD M.2 externo **no se conecta** ni se menciona en QEMU durante este runbook. Todo ocurre sobre `E:\work-os\images\ronin.img`.

## 0. Precondiciones

- Windows 10/11 x64 con virtualización habilitada.
- QEMU 11.x (`winget install SoftwareFreedomConservancy.QEMU`).
- 32 GB de RAM (mínimo 16 GB; el guest usa 12 GB).
- ~140 GB libres en `E:` (imagen 120 GiB + ISO + logs).
- ISO `cachyos-desktop-linux-260809.iso` verificada.
- Clave SSH `%USERPROFILE%\.ssh\ronin_ed25519`.

## 1. Diagnóstico del host

```powershell
cd C:\Users\davos\orca\projects\work-os
.\build.ps1 doctor
```

Debe terminar en `READY` sin `FAIL`. Los `WARN` aceptables son:

- WHPX no disponible (se usará TCG, mucho más lento).
- RAM < 16 GB.
- Imagen aún no creada.

Si WHPX falla y querés habilitarlo (requiere admin y reboot):

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
# reiniciar Windows
```

> Docker Desktop/WSL2 usan Hyper-V. QEMU puede usar WHPX si `HypervisorPlatform` está habilitado. Si no, `build.ps1` cae a TCG automáticamente.

## 2. Crear la imagen y la NVRAM UEFI

```powershell
.\build.ps1 image
```

Resultado:

```
E:\work-os\images\ronin.img     120 GiB (crudo, sparse)
E:\work-os\images\edk2-vars.fd          4 MiB (NVRAM)
```

Verificar:

```powershell
& "C:\Program Files\QEMU\qemu-img.exe" info E:\work-os\images\ronin.img
```

> El archivo puede reportar 120 GiB de tamaño lógico y ocupar mucho menos en disco al inicio. Windows NTFS lo asigna a medida que se escribe. Monitorear `E:` durante el build.

## 3. Arrancar la ISO

```powershell
.\build.ps1 up-iso
```

Esto lanza QEMU con:

- `q35` + OVMF (`edk2-x86_64-code.fd` + `edk2-vars.fd`)
- `-cpu host` (WHPX) o `-cpu max` (TCG). **Default actual: TCG**, porque WHPX congeló el kernel instalado tras el reboot (ver `docs/08-BUILD-LOG.md`).
- 8 vCPU, 12 GiB RAM
- disco virtio `ronin.img`
- CD-ROM con la ISO
- red user con `127.0.0.1:2222 → guest:22`
- `-boot once=d` (la ISO solo para esta sesión)

En el menú de CachyOS elegir **UEFI** y arrancar el entorno live.

## 4. Preparar el entorno live y habilitar SSH

La ISO arranca con `sshd` escuchando en el puerto 22, pero root no tiene clave. Hay dos caminos:

**A. Inyección de clave por HTTP (recomendada, automatizada)**

En el host:

```powershell
.\build.ps1 live-ssh
```

En la consola del live, cambiar a tty3 (`Ctrl+Alt+F3`), entrar como `root` (sin password) y ejecutar exactamente lo que imprime el script:

```bash
curl -s http://10.0.2.2:8000/bootstrap.sh -o /tmp/b.sh
bash /tmp/b.sh
# BOOTSTRAP_DONE
```

**B. Password temporal**

En la consola live:

```bash
sudo systemctl start sshd
sudo passwd root
```

Luego, desde el host:

```powershell
ssh -i $env:USERPROFILE\.ssh\ronin_ed25519 -p 2222 `
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@127.0.0.1
```

> El login gráfico de la ISO (SDDM/Plasma X11) puede fallar en QEMU. Usar tty3 (`Ctrl+Alt+F3`) y login `root` sin password es el camino estable. Si la ISO no trae `sshd`, montar un disco FAT con `build/guest` y ejecutar los scripts desde la consola.

## 5. Copiar scripts al guest

Desde el host, en otra terminal:

```powershell
.\build.ps1 push
```

Equivale a:

```powershell
scp -i $env:USERPROFILE\.ssh\ronin_ed25519 -P 2222 -r `
  build\guest build\config build\build.env `
  root@127.0.0.1:/root/build-scripts/
```

Verificar en el guest:

```bash
ls -la /root/build-scripts/
# guest/ config/ build.env authorized_keys
```

## 6. Preflight (F1.1)

```bash
cd /root/build-scripts
chmod +x guest/*.sh
bash guest/00-preflight.sh
```

Comprueba:

- UEFI activo.
- `/dev/vda` existe y es el disco de 120 GiB (no la ISO).
- Red y DNS.
- Soporte `x86-64-v3` (`/lib/ld-linux-x86-64.so.2 --help`).
- Herramientas: `sgdisk`, `mkfs.btrfs`, `mkfs.fat`, `pacstrap`, `arch-chroot`.
- `CONFIRM_WIPE=YES` para operaciones destructivas.

Salida esperada: `PREFLIGHT OK`. Si `x86-64-v3` no está soportado en el CPU del host, **detener**: CachyOS v3 no arrancará en esa máquina.

## 7. Particionar y crear subvolúmenes (F1.2)

```bash
CONFIRM_WIPE=YES bash guest/10-partition.sh
```

Resultado:

```
/dev/vda1  1G   FAT32   ESP          /mnt/boot
/dev/vda2 119G  Btrfs   CACHY_ROOT   /mnt
  @, @home, @var_cache, @var_log, @docker, @snapshots
```

Verificar:

```bash
lsblk -f
findmnt -R /mnt
btrfs subvolume list /mnt
```

Guardar el estado:

```bash
cat /root/build-scripts/build-state.env
# TARGET_DISK=/dev/vda
# ESP_PART=/dev/vda1
# ROOT_PART=/dev/vda2
# ROOT_UUID=...
# ESP_UUID=...
```

## 8. Bootstrap CachyOS (F1.3)

```bash
bash guest/20-bootstrap.sh
```

Hace:

1. Verifica que `/mnt` es Btrfs y que los repos CachyOS están configurados.
2. `pacstrap -K /mnt base base-devel linux-cachyos ...`
3. Copia `build/` a `/mnt/root/build-scripts/`.
4. `genfstab -U` preliminar.
5. `arch-chroot /mnt /root/build-scripts/guest/30-configure.sh`.
6. Desmonta y reinicia.

Paquetes base: `linux-cachyos`, headers, firmware, microcodes, Btrfs, EFI, NetworkManager, SSH, zram, utilidades.

> Si `pacstrap` falla por keyring: `pacman-key --init && pacman-key --populate archlinux cachyos` y reintentar. Si `linux-cachyos` no aparece: revisar `grep -r cachyos /etc/pacman.conf /etc/pacman.d/`.

## 9. Configuración del sistema (F1.4)

`30-configure.sh` corre dentro de `arch-chroot` y configura:

- timezone, locale, teclado, hostname.
- usuario `davosoler`, grupos, sudo.
- password (o genera uno y lo guarda en `/root/build-credentials.txt`).
- SSH por clave, root solo con clave.
- `/etc/fstab` por UUID con las opciones de la arquitectura.
- `zram-generator` al 50 %.
- `mkinitcpio` universal sin `autodetect`.
- `systemd-boot` con entrada `ronin` y fallback `EFI/BOOT/BOOTX64.EFI`.
- `systemctl enable NetworkManager sshd systemd-timesyncd`.

Verificar dentro del chroot si algo falla:

```bash
arch-chroot /mnt
mkinitcpio -P
bootctl --esp-path=/boot status
findmnt --verify
```

## 10. Primer arranque (F1.5)

Al reiniciar, QEMU debe arrancar del disco (la ISO se usó con `once=d`). En el host:

```powershell
.\build.ps1 down      # si quedó la ISO corriendo
.\build.ps1 up        # arranca solo el disco
.\build.ps1 wait-ssh
.\build.ps1 ssh
```

Dentro del guest:

```bash
bootctl status
findmnt -no SOURCE,FSTYPE,OPTIONS /
lsblk -f
systemctl is-enabled NetworkManager sshd
journalctl -k --no-pager | grep -i microcode
```

Criterio: el sistema arranca sin ISO y SSH responde.

## 11. Provisionar el stack (F2–F6)

```powershell
.\build.ps1 provision
```

Ejecuta en orden, por SSH:

| Script | Fase | Qué hace |
| --- | --- | --- |
| `40-hw-adapt.sh` | F1/F6 | instala y prueba `hw-adapt` |
| `50-omarchy.sh` | F2 | overlay Omarchy + SDDM |
| `60-dev-ai.sh` | F3/F4 | dev, Docker, Ollama, Vulkan |
| `70-gaming.sh` | F5 | gaming bajo demanda |
| `80-harden.sh` | F6 | UFW, sysctl, SSH |
| `90-verify.sh` | F6 | suite de aceptación |
| `95-finalize.sh` | F6 | deshabilita root SSH, manifiesto |

> `provision` se puede correr por partes:
> ```powershell
> .\build.ps1 run 40-hw-adapt.sh
> .\build.ps1 run 50-omarchy.sh
> ```

## 12. Verificación (F6)

```powershell
.\build.ps1 verify
```

El reporte queda en:

- guest: `/var/log/ronin-verify.json`
- host: `reports/verify-<timestamp>.json`

Criterio MVP: `fail = 0`. Los `warn` se revisan uno por uno.

## 13. Snapshot del estado base

Antes de F7, crear un snapshot Btrfs del root para poder volver:

```bash
sudo mount -o remount,rw /
sudo btrfs subvolume snapshot -r / /.snapshots/@pre-migration-$(date +%Y%m%d)
```

> `@snapshots` está montado en `/.snapshots`. Si se prefiere Snapper, queda para post-MVP.

## 14. Apagar y preservar

```powershell
.\build.ps1 down
```

- No borrar `ronin.img` hasta que F7 pase.
- No conectar el NVMe real todavía.
- Guardar `reports/` y `build-state.env` en el commit de cierre de fase.

## 15. Troubleshooting

| Síntoma | Causa probable | Acción |
| --- | --- | --- |
| QEMU no arranca: `WHPX unavailable` | HypervisorPlatform off | `Enable-WindowsOptionalFeature` o usar TCG |
| Bootea a UEFI Shell | Fallback no creado | `bootctl --esp-path=/boot install`; copiar `EFI/systemd/systemd-bootx64.efi` a `EFI/BOOT/BOOTX64.EFI` |
| `root=UUID` no encontrado | UUID mal copiado | comparar `blkid` con `loader/entries/ronin.conf` |
| `mkinitcpio` falla | Hook/módulo inexistente | revisar `mkinitcpio -P`; quitar módulo no disponible |
| SSH rechazado | `sshd` no inició o firewall | `systemctl status sshd`; `sshd -t`; `ufw status` |
| `pacstrap` 404 | mirror CachyOS desactualizado | `cachyos-rate-mirrors` en live; reintentar |
| Hyprland no inicia en QEMU | falta DRM/EGL | probar `-display gtk -device virtio-vga-gl`; o validar en hardware real |
| Disco lleno | imágenes Docker/modelos | `btrfs filesystem usage /`; `docker system df`; limpiar |
| Docker no arranca | `@docker` mal montado | `findmnt /var/lib/docker`; revisar fstab |
| Ollama no responde | servicio o modelos | `systemctl status ollama`; `journalctl -u ollama`; `curl 127.0.0.1:11434/api/tags` |

## 16. Comandos útiles del host

```powershell
.\build.ps1 status          # doctor + imagen + VM
.\build.ps1 up -Display none # headless
.\build.ps1 ssh             # shell root
.\build.ps1 run 90-verify.sh
.\build.ps1 lint            # sintaxis de scripts
.\build.ps1 down -Force     # matar QEMU si está colgado
```
