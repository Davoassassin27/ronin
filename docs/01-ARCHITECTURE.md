# Arquitectura

## 1. Vista general

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ HOST WINDOWS 11 (Ryzen 7 5700X, 32 GB, WHPX)                                │
│                                                                             │
│  build.ps1 ──► QEMU (q35 + OVMF + virtio)                                  │
│                    │                                                        │
│                    ├── ISO CachyOS 260809 (solo instalación)                │
│                    ├── ronin.img (120 GiB, crudo, virtio-blk)       │
│                    └── hostfwd 127.0.0.1:2222 → guest:22                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │ SSH / consola
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ GUEST RONIN                                                               │
│                                                                             │
│  UEFI ──► systemd-boot (EFI/BOOT/BOOTX64.EFI) ──► linux-cachyos            │
│                                                       │                     │
│                                          initramfs universal (sin autodetect)│
│                                                       │                     │
│                                          Btrfs CACHY_ROOT                   │
│                                          ├── @            /                 │
│                                          ├── @home        /home             │
│                                          ├── @var_cache   /var/cache        │
│                                          ├── @var_log     /var/log          │
│                                          ├── @docker      /var/lib/docker   │
│                                          └── @snapshots   /.snapshots        │
│                                                                             │
│  hw-adapt.service (pre-login) ──► perfil + GPU env + JSON audit             │
│  SDDM ──► Hyprland/Omarchy                                                   │
│  Docker · Ollama · toolchain · gaming bajo demanda                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2. Principios de diseño

1. **Reproducible:** todo cambio de sistema nace de un script versionado; nada se “arregla a mano” sin dejarlo en `build/`.
2. **Auditable:** cada fase escribe logs y un manifiesto con versiones, commit de Omarchy, UUIDs y paquetes.
3. **Portable:** el disco no depende de la máquina. Bootloader extraíble, initramfs universal, `fstab` por UUID, drivers de ambas vendors.
4. **Separación de responsabilidades:** el host orquesta QEMU; el guest se configura con scripts bash. No se depende de WSL ni de Docker del host.
5. **Fallo seguro:** las operaciones destructivas exigen `CONFIRM_WIPE=YES` y `--dry-run` por defecto en migración.
6. **MVP primero:** todo lo que no sea necesario para arrancar, trabajar y migrar queda fuera.

## 3. Hardware objetivo

| Componente | Desktop (host actual) | Notebook | Implicancia |
| --- | --- | --- | --- |
| CPU | Ryzen 7 5700X (x86-64-v3) | por confirmar (¿v3?) | CachyOS v3 requiere soporte en ambas |
| GPU | por confirmar (¿AMD?) | por confirmar (¿Intel/AMD/NVIDIA?) | initramfs y env dinámico |
| RAM | 32 GB | por confirmar | zram 50 %, modelos |
| Disco | imagen 120 GiB | NVMe externo 1 TB | migración F7 |
| Firmware | UEFI | UEFI | sin Secure Boot |

> **Pendiente:** completar modelos exactos en [07-OPEN-QUESTIONS.md](07-OPEN-QUESTIONS.md). Sin eso, la matriz de drivers se valida solo en QEMU.

## 4. Layout de disco

### 4.1 Imagen de construcción (F1)

GPT, 2 particiones:

| # | Tamaño | Tipo | FS | Label | Mount |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 GiB | `ef00` ESP | FAT32 | `ESP` | `/boot` |
| 2 | resto (~119 GiB) | `8300` Linux | Btrfs | `CACHY_ROOT` | `/` (subvol `@`) |

### 4.2 NVMe final (F7)

GPT, 3 particiones, en este orden:

| # | Tamaño | Tipo | FS | Label | Contenido |
| --- | --- | --- | --- | --- | --- |
| 1 | ~500 GiB | `0700` Microsoft basic data | exFAT | `DATOS` | intercambio Windows/Android, modelos, datasets |
| 2 | 4 GiB | `ef00` ESP | FAT32 | `ESP` | clon del ESP (margen para Limine/snapshots) |
| 3 | resto (~427 GiB) | `8300` Linux | Btrfs | `CACHY_ROOT` | clon de `@` + resize max |

`DATOS` va primero por compatibilidad plug-and-play. No se usa como `/home` ni para Docker: exFAT no tiene permisos POSIX ni CoW.

### 4.3 Subvolúmenes Btrfs

| Subvol | Mount | Opciones | Razón |
| --- | --- | --- | --- |
| `@` | `/` | `noatime,compress=zstd:3,ssd,discard=async,space_cache=v2` | sistema base |
| `@home` | `/home` | idem | datos de usuario |
| `@var_cache` | `/var/cache` | idem | cache de pacman/AUR, se puede borrar |
| `@var_log` | `/var/log` | idem | logs separados, no llenan root |
| `@docker` | `/var/lib/docker` | mismas que `@` + `chattr +C` en el directorio | capas/imágenes Docker; CoW degrada I/O |
| `@snapshots` | `/.snapshots` | idem base | snapshots futuros |

Notas:

- Las opciones de montaje de Btrfs son por superbloque, no por subvolumen: `nodatacow`/`compress` en una línea de `fstab` afectarían a todo el filesystem. El aislamiento de Docker se logra con `chattr +C` en `/var/lib/docker` (nodatacow heredado por los archivos nuevos); el script lo verifica con `lsattr`.
- `discard=async` evita stalls de TRIM en USB-C.
- No se crea swap físico. `zram-generator` crea `/dev/zram0` al 50 % de RAM con zstd y prioridad 100.

## 5. Flujo de arranque

```
Firmware UEFI
  └─► /boot/EFI/BOOT/BOOTX64.EFI        (ruta extraíble, no depende de NVRAM)
        └─► loader/loader.conf          (default ronin, timeout 3s)
              └─► loader/entries/ronin.conf
                    ├─ linux /vmlinuz-linux-cachyos
                    ├─ initrd /intel-ucode.img
                    ├─ initrd /amd-ucode.img
                    ├─ initrd /initramfs-linux-cachyos.img
                    └─ options root=UUID=<ROOT> rw rootflags=subvol=@ \
                                usbcore.autosuspend=-1
                          └─► systemd
                                ├─ local-fs.target
                                ├─ systemd-udev-settle.service
                                └─ hw-adapt.service (Before=display-manager/sddm)
                                      └─► sddm.service
                                            └─► Hyprland (Omarchy)
```

### Por qué `systemd-boot` y no Limine/GRUB

- Ruta extraíble estándar (`EFI/BOOT/BOOTX64.EFI`) sin depender de `efibootmgr`.
- La migración cambia números de partición (ESP pasa de p2 a p3); con la ruta extraíble y UUIDs, no hay que reinstalar el bootloader.
- Omarchy usa Limine, pero el MVP desacopla el bootloader del escritorio. Si en el futuro se quieren snapshots con Limine, se evalúa en post-MVP.

### Initramfs universal

`mkinitcpio.conf`:

```conf
MODULES=(btrfs usb_storage uas nvme xhci_pci ahci virtio_blk virtio_pci virtio_net
         amdgpu i915 xe nouveau)
HOOKS=(base udev modconf block keyboard filesystems fsck)
COMPRESSION="zstd"
```

- **Sin hook `autodetect`**: evita que el initramfs se recorte a los módulos de la máquina de construcción.
- `btrfs` explícito porque el hook `filesystems` no siempre lo fuerza.
- `kms` se omite a propósito para no atar el initramfs a una GPU; los drivers están en `MODULES`.
- Ambos microcodes se cargan como initrd separados; cada CPU ignora el que no corresponde.

## 6. `hw-adapt.service`

### Orden de arranque

```ini
After=local-fs.target systemd-udev-settle.service
Before=display-manager.service greetd.service sddm.service
Type=oneshot
RemainAfterExit=yes
```

### Detección

| Dato | Fuente |
| --- | --- |
| Placa | `/sys/class/dmi/id/board_name`, `product_name`, `sys_vendor` |
| Chasis | `/sys/class/dmi/id/chassis_type` |
| CPU | `lscpu -J` (modelo, núcleos, flags) |
| RAM | `/proc/meminfo` |
| Batería | `/sys/class/power_supply/BAT*` |
| AC | `/sys/class/power_supply/A{C,DP}*` |
| GPU | `lspci -Dnn | grep -E 'VGA|3D|Display'` + driver en sysfs |
| VRAM | `mem_info_vram_total` (AMD), `nvidia-smi` (NVIDIA), compartida (Intel) |

### Perfiles

| Modo | Condición | `power-profiles-daemon` | CPU EPP | Turbo |
| --- | --- | --- | --- | --- |
| Desktop | sin batería / chasis desktop | `performance` | `performance` | habilitado |
| Notebook AC | batería + AC online | `balanced` | `balance_performance` | habilitado |
| Notebook batería | batería + AC offline | `balanced` | `balance_performance` | limitado |
| Batería crítica | < 15 % y offline (opcional) | `power-saver` | `power` | limitado |

### Variables GPU

Se escriben en `/etc/profile.d/ai-gpu-env.sh` y en `~/.config/hypr/hardware-auto.lua`:

| Vendor | Variables |
| --- | --- |
| AMD | `AMD_VULKAN_ICD=RADV`, `VK_ICD_FILENAMES=.../radeon_icd.x86_64.json`, `LIBVA_DRIVER_NAME=radeonsi` |
| Intel | `VK_ICD_FILENAMES=.../intel_icd.x86_64.json`, `LIBVA_DRIVER_NAME=iHD|i965`, `ONEAPI_DEVICE_SELECTOR=level_zero:gpu` |
| NVIDIA | `VK_ICD_FILENAMES=.../nvidia_icd.json`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `LIBVA_DRIVER_NAME=nvidia` |

`HSA_OVERRIDE_GFX_VERSION` **no se hardcodea**: solo se exporta si `AMD_GFX_VERSION` está definido en `/etc/hw-adapt.conf`. Un valor incorrecto rompe ROCm.

### Cambio de máquina

`/var/lib/hw-adapt/state.json` guarda `board` y `product` del último boot. Si cambian:

1. `changed_board=true` en el JSON.
2. Se intenta reiniciar Bluetooth (limpia cache de dispositivos huérfanos).
3. Se invalida el estado de ALSA (`/var/lib/alsa/asound.state`).
4. Se registra que NetworkManager reindexa interfaces en el boot (no se reinicia por defecto para no cortar SSH).
5. Se conserva el historial en `/var/log/hw-adapt.log`.

### Contrato de `/var/log/hw-adapt-last.json`

```json
{
  "schema": 1,
  "timestamp": "2026-11-12T12:00:00-03:00",
  "boot_id": "...",
  "hostname": "ronin",
  "board": "B650M ...",
  "product": "...",
  "chassis": "desktop",
  "mode": "desktop",
  "cpu": { "model": "...", "cores": 8, "threads": 16 },
  "memory_kib": 32768000,
  "battery": { "present": false, "capacity": null, "status": null },
  "ac_online": null,
  "gpus": [
    { "pci": "0000:03:00.0", "vendor": "AMD", "model": "...", "driver": "amdgpu", "vram_bytes": 8589934592 }
  ],
  "profile": "performance",
  "env": { "VK_ICD_FILENAMES": "...", "LIBVA_DRIVER_NAME": "radeonsi" },
  "hypr_config": "/home/davosoler/.config/hypr/hardware-auto.lua",
  "changed_board": false,
  "actions": ["profile=performance", "gpu-env=AMD"],
  "version": "1.0.0"
}
```

Cualquier consumidor (script de verificación, soporte, agente) puede leer este archivo sin parsear logs.

## 7. Stack de software

### Base

`linux-cachyos`, `linux-cachyos-headers`, `linux-firmware`, `amd-ucode`, `intel-ucode`, `btrfs-progs`, `dosfstools`, `exfatprogs`, `efibootmgr`, `NetworkManager`, `openssh`, `sudo`, `zram-generator`, `pciutils`, `usbutils`, `jq`, `git`, `nano`, `vim`, `tmux`, `htop`, `btop`, `ripgrep`, `fd`, `fzf`, `zstd`, `bash-completion`, `man-db`, `pacman-contrib`.

### Dev/DevOps

`docker`, `docker-compose`, `docker-buildx`, `kubectl`, `helm`, `lazydocker`, `github-cli`, `uv`, `python`, `rustup`, `go`, `nodejs`, `npm`, `neovim`, `openssh`, `rclone`, `yq`, `postgresql-libs`, `sqlite`, `duckdb`.

### AI

`vulkan-icd-loader`, `vulkan-tools`, `mesa`, `vulkan-radeon`, `vulkan-intel`, `libva`, `libva-utils`, `nvtop`, `radeontop`, `ollama`. NVIDIA opcional (`nvidia-open-dkms`, `nvidia-utils`, `lib32-nvidia-utils`).

### Gaming

`cachyos-gaming-meta` (Steam, Proton-CachyOS, GameMode, MangoHud, lib32). Sin autostart de launchers; GameMode es un servicio ligero y se documenta como excepción.

## 8. Omarchy

### Estrategia (ADR-001)

Omarchy 4.5 es una distro; su instalador exige Arch vanilla + Limine y **rechaza CachyOS**. El MVP usa **overlay**:

```
CachyOS base
  + repo [omarchy] (solo paquetes omarchy-*)
  + Hyprland/SDDM/uwsm/utilidades
  + ~/.local/share/omarchy (clone pinneado)
  + ~/.config/* (configs de Omarchy)
  + ~/.config/hypr/hardware-auto.lua (generado)
```

No se ejecuta `install.sh` completo ni se reemplaza `/etc/pacman.conf` (eso borraría los mirrors CachyOS y `x86-64-v3`).

### Integración con hardware

Omarchy 4.5 usa configuración **Lua** de Hyprland (`hl.env`, `hl.monitor`), no el formato `.conf`. `hw-adapt.sh` escribe `hardware-auto.lua` con `hl.env(...)` y, opcionalmente, `hl.monitor({...})`. `50-omarchy.sh` garantiza que `hyprland.lua` termine con:

```lua
require("hypr.hardware-auto")
```

El `hardware-auto.conf` que menciona PROJECT.md se conserva como concepto; la implementación real usa `.lua` por la versión de Omarchy. Ver ADR-013.

Así el usuario puede sobreescribir con reglas más específicas después.

### SDDM

- `DisplayServer=wayland`
- `CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.conf`
- Sesión `omarchy` en `/usr/local/share/wayland-sessions/omarchy.desktop`
- Autologin configurable (`OMARCHY_AUTOLOGIN=yes|no`); por defecto sí, para un equipo personal.

## 9. Build pipeline

```
Host                                Guest live                    Guest instalado
────                                ──────────                    ───────────────
doctor ──► install-qemu
       ──► fetch-iso (sha256)
       ──► image (raw + NVRAM)
       ──► up-iso ──────────────────► 00-preflight
                                      10-partition
                                      20-bootstrap ──► arch-chroot 30-configure
                                                          │
                                                          └─► reboot
       ──► wait-ssh ───────────────────────────────────────► ssh root
       ──► provision ─────────────────────────────────────► 40 hw-adapt
                                                              50 omarchy
                                                              60 dev/ai
                                                              70 gaming
                                                              80 harden
                                                              90 verify
                                                              95 finalize
       ──► verify ◄────────────────────────────────────────── report JSON
```

`provision` copia `build/guest`, `build/config` y `build.env` a `/root/build-scripts/`. El host no necesita WSL ni Docker.

## 10. Migración

```
Imagen origen (120 GiB)                     NVMe destino (1 TB)
┌──────────────┬──────────────────┐        ┌──────────────┬──────┬──────────────────┐
│ ESP 1 GiB    │ CACHY_ROOT       │        │ DATOS 500 GiB│ ESP  │ ROOT resto       │
│ FAT32        │ Btrfs @...       │        │ exFAT        │ 4 GiB│ Btrfs @...       │
└──────────────┴──────────────────┘        └──────────────┴──────┴──────────────────┘
        │                                          ▲
        └──────── dd particiones (UUID intactos) ──┘
                                                   │
                                    btrfs filesystem resize max
```

- `DATOS` se crea nueva (no se copia).
- ESP y root se copian con `dd` para preservar UUID de filesystem.
- El root destino es más grande que el origen: se copian solo los primeros 120 GiB y se expande Btrfs.
- El bootloader está en `EFI/BOOT/BOOTX64.EFI`; no importa que el ESP cambie de `p2` a `p3`.
- `fstab` y `root=UUID=` no se editan.

## 11. Verificación

`90-verify.sh` es la fuente de verdad. Cubre:

- Boot/EFI/loader/initramfs.
- fstab, UUIDs, subvolúmenes, opciones, zram.
- Servicios habilitados/activos.
- `hw-adapt` JSON y cambio de perfil.
- Docker, Ollama, Vulkan, toolchain.
- Omarchy/SDDM/Hyprland.
- Gaming sin autostart.
- Seguridad (UFW, SSH, sysctl).

El detalle está en [04-VERIFICATION.md](04-VERIFICATION.md).

## 12. Supuestos y límites

- El host tiene virtualización anidada suficiente para WHPX; si no, TCG.
- El guest QEMU no tiene GPU real: Hyprland puede requerir render por software/VirGL; la validación final de GPU se hace en hardware real.
- No hay cifrado de disco en el MVP.
- No hay Secure Boot.
- La ISO de CachyOS se usa solo como entorno live; el sistema se instala con `pacstrap`, no con el instalador gráfico.
- Los repos de CachyOS y Omarchy pueden cambiar; el manifiesto registra versiones y commit para reproducir.
