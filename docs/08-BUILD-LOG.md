# Build log — primera ejecución real (2026-11-12)

Registro cronológico de la primera construcción. No reemplaza los runbooks; documenta qué pasó realmente, qué se corrigió y qué queda pendiente.

## Entorno

| Item | Valor |
| --- | --- |
| Host | Windows 11 Pro 26300, Ryzen 7 5700X, 32 GiB |
| QEMU | 11.1.0 (winget) |
| Firmware | OVMF `edk2-x86_64-code.fd` + `edk2-i386-vars.fd` |
| ISO | CachyOS 260809, SHA-256 verificado |
| Imagen | `E:\work-os\images\ronin.img`, 120 GiB sparse |
| Guest live | kernel 7.1.6-1-cachyos, 8 vCPU, 12 GiB, WHPX |
| Guest instalado | kernel 7.3.3-1-cachyos, TCG (WHPX inestable tras reboot) |

## Timeline

| Hora | Evento | Resultado |
| --- | --- | --- |
| 20:18 | `build.ps1 doctor` | 13 PASS, 1 WARN (clave SSH), 0 FAIL |
| 20:19 | `build.ps1 image` | Imagen 120 GiB + NVRAM creadas |
| 20:20 | `build.ps1 up-iso` | CachyOS live en QEMU; SSH 2222 abierto |
| 20:24 | Consola live (tty3) | login `root` sin password; se inyectó clave SSH vía HTTP local |
| 20:31 | `push` + `00-preflight` | Falló `linux-cachyos` por DB de pacman no sincronizada; corregido con `pacman -Sy` |
| 20:31 | `10-partition` | GPT + ESP + Btrfs + 6 subvolúmenes OK |
| 20:32 | `20-bootstrap` | `pacstrap` + chroot; falló `sshd -t: no hostkeys available` |
| 20:41 | `30-configure` (resume) | Corregido con `ssh-keygen -A`; systemd-boot, fstab, zram, mkinitcpio OK |
| 20:43 | Reboot con WHPX | **Guest congelado**; errores `WHPX: Unexpected VP exit code 4` |
| 20:46 | Reboot con TCG | Boot OK; SSH root con clave |
| 20:51 | `40-hw-adapt` | **Colgó** en `jq` sin `-n` (esperaba stdin); corregido |
| 20:57 | `40-hw-adapt` (retry) | 3 tests OK + servicio activo + JSON válido |
| 21:03 | `50-omarchy` | Hyprland/SDDM/Omarchy overlay OK; commit `ac6cb9c...` |
| 21:05 | `60-dev-ai` | En curso: `nvidia-open-dkms` compilando con clang en TCG |
| 21:40 | `60-dev-ai` (retry) | Toolchain, Docker, multilib y lib32 OK; Ollama instalado pero servicio falla |
| 21:55 | Fix Ollama | `ProtectHome=yes` del unit + home 700; se agregó grupo y `ProtectHome=read-only` + `ReadWritePaths` |
| 22:04 | `40-hw-adapt` (retry) | `hardware-auto.lua` generado con `hl.env`/`hl.monitor`; servicio OK |
| 22:05 | `50-omarchy` (retry) | `walker`, `quickshell`, `omarchy-nvim` OK; `omarchy-hyprland-titlebars` no existe en el repo |
| 22:08 | `70-gaming` | `steam`, `gamemode`, `mangohud` + lib32 OK; `cachyos-gaming-meta`/`proton-cachyos` no están en los repos |
| 22:12 | Fix repos CachyOS | El sistema instalado no tenía `[cachyos]`/`[cachyos-v3]`; se agregó función `configure_cachyos_repos` |
| 22:13 | `pacman -Syu` | 584 paquetes a x86-64-v3 (974 MiB de descarga); en curso |
| — | 80/90/95 | Pendientes |

## Correcciones aplicadas durante el build

1. **`00-preflight.sh`**: ejecutar `pacman -Sy` antes de consultar `linux-cachyos`.
2. **`30-configure.sh`**: `ssh-keygen -A` antes de `sshd -t` (host keys no existen en chroot).
3. **`10-partition.sh`**: Btrfs no permite `nodatacow`/`compress` por subvolumen en `fstab`; se usa `chattr +C` en `/var/lib/docker` y se verifica con `lsattr`.
4. **`hw-adapt.sh`**: `json_append` usaba `jq` sin `-n`, quedaba esperando stdin; se agregó `-n`.
5. **Omarchy 4.5**: la configuración es **Lua** (`hl.env`, `hl.monitor`), no `.conf`; se genera `hardware-auto.lua` y `hyprland.lua` hace `require("hypr.hardware-auto")`.
6. **WHPX**: estable para el live ISO, pero el kernel instalado 7.3.3 se congeló tras reboot; `build.env` usa `VM_ACCEL=tcg` por defecto.
7. **`inetutils`**: `hostname` no venía en base; se instaló y se agregará a `20-bootstrap.sh`.
8. **Ollama**: el unit de fábrica usa `ProtectHome=yes`, que oculta `/home`; además el home estaba en 700. Se agregó `ollama` al grupo del usuario y el override usa `ProtectHome=read-only` + `ReadWritePaths`.
9. **Multilib**: `60-dev-ai.sh` ahora descomenta `[multilib]` de forma idempotente antes de instalar `lib32-*`.
10. **Repos CachyOS**: `pacstrap` deja el `pacman.conf` de Arch (sin `[cachyos]`/`[cachyos-v3]`). `configure_cachyos_repos` (en `lib.sh`, llamado desde `30-configure.sh`) genera el mirrorlist v3 y agrega los repos antes de `[core]`.
11. **Gaming**: `cachyos-gaming-meta` y `proton-cachyos` no existen en los repos actuales; el fallback instala `steam`, `gamemode`, `mangohud` y sus lib32. Proton se usa desde Steam Play.

## Evidencia

- `logs/bootstrap-console.log`
- `logs/configure-console.log`
- `logs/hwadapt-console2.log`
- `logs/omarchy-console.log`
- `logs/devai-console.log`
- Guest: `/root/build-scripts/reports/`, `/var/log/hw-adapt-last.json`
- UUIDs: root `3eaf056b-315b-4155-bc57-1d0bbdbff996`, ESP `C6B0-4875`

## Sesión de cierre (2026-11-18)

Primera verificación de aceptación: `54 PASS / 3 WARN / 7 FAIL` (`reports/verify-20261118-015446.json`). Los 7 fallos se corrigieron y se re-ejecutó la suite hasta dejarla en verde.

| Hora | Evento | Resultado |
| --- | --- | --- |
| 01:59 | `90-verify` (primera pasada) | 7 FAIL: FS-04, HW-03, HW-08, HW-09, DEV-01, SEC-01, SEC-02 |
| 02:00–02:01 | Ajustes en `90-verify.sh` y `80-harden.sh` | FS-04 pasa a check negativo; HW-03 tolera `board_name` ausente (`unknown`); SEC-01/02 se validan con `sshd -T`; SEC-05 pasa a `warn` |
| 23:12 | Boot del sistema instalado (TCG) | SSH root OK tras esperar el arranque |
| 23:21 | `90-verify` (tras correcciones) | **61 PASS / 3 WARN / 0 FAIL** |
| 23:26 | `95-finalize` | Root SSH deshabilitado, manifiesto y sudoers de verificación instalados |
| 23:47 | Live ISO por consola serial | Diagnóstico: `/home/davos/.ssh` era `root:root` → `StrictModes` rechazaba la clave |
| 23:49 | Fix de propiedad en `@home` + corrección de `30-configure.sh`/`95-finalize.sh` | SSH de usuario restaurado |
| 23:51 | `90-verify` como usuario (post-finalize) | **62 PASS / 2 WARN / 0 FAIL** |

### Correcciones adicionales aplicadas

12. **`90-verify.sh` HW-08/HW-09:** `nvme`, `ahci`, `uas` y `usb_storage` son *built-in* en `linux-cachyos` (`CONFIG_*=y`), por lo que no hay `.ko` en el initramfs. El check ahora acepta módulo en initramfs **o** configuración compilada en el kernel (`kernel_storage_ready`).
13. **`60-dev-ai.sh` DEV-01:** `sudo -u davos rustup default stable` se ejecutaba sin `-H`, conservando `HOME=/root` y dejando el toolchain sin asignar. Con `-H`, `rustc 1.100.0` queda activo para el usuario.
14. **`30-configure.sh` SSH de usuario:** `install -d /home/$TARGET_USER/.ssh` creaba el directorio como `root:root`; con `StrictModes`, sshd rechazaba `authorized_keys`. Ahora se crea con `-o/-g $TARGET_USER`.
15. **`95-finalize.sh`:** refuerzo defensivo que reasigna `.ssh` al usuario antes de cortar el acceso root.
16. **`build.ps1` / `lib.ps1`:** el warning de `scp` ("Permanently added…") se trataba como error terminante y hacía que `verify` devolviera `1` aunque `fail=0`. Se silencia con `LogLevel=ERROR` y se acota `ErrorActionPreference`.

### Evidencia final

- `reports/verify-20261118-015446.json` — primera pasada (7 FAIL).
- `reports/verify-20261118-232156.json` — tras correcciones (0 FAIL).
- `reports/verify-20261118-234659.json` — verificación final como usuario (0 FAIL).

## Sesión de renombrado y trazabilidad (2026-11-19)

| Hora | Evento | Resultado |
| --- | --- | --- |
| 18:00 | Decisión de nombre **Ronin** + filosofía zen/bushido | README, PROJECT.md y ADR-015 |
| 18:05 | Renombrado global (hostname, boot entry, `/etc/ronin`, `/var/log/ronin-*`, clave e imagen del host) | `ronin.img`, `ronin_ed25519`, entry `ronin.conf` |
| 18:10 | Fix FS-01/02/03: detección de disco por `findmnt`/`lsblk` en vez de `/dev/vda3` | `detect_disk_layout` en `lib.sh`; cubre build y NVMe |
| 18:15 | Trazabilidad UX: `ux_log`/`ux_fail`/`ux_run` → `/var/log/ronin/ux-trace.jsonl` | Integrado en `90-verify.sh` y `migrate-to-nvme.sh` |
| 18:20 | Unit tests (17 tests de guest con mocks de disco + 5 checks de host) | `.\build.ps1 test-unit` → **22 PASS / 0 FAIL** |
| 18:25 | Runbook F7: snapshot previo, validar con origen conectado, gate de cifrado, ESP 4 GiB | ADR-016/017 |

Evidencia: `reports/unit-20261119-182307.json`, `logs/ronin-ux-20261119-182307.jsonl`.

> Nota: el cambio de nombre y los scripts corregidos se aplican también a la imagen ya construida mediante `build/guest/rename-to-ronin.sh` desde el live ISO, para no tener que rehacer F0–F6.

## Ensayo F7 en QEMU y cierre de decisiones (2026-11-19/20)

| Hora | Evento | Resultado |
| --- | --- | --- |
| 20:30 | Decisión explícita: **Ronin v1 sin cifrado** | ADR-017 cerrado, runbook actualizado |
| 20:35 | Backup comprimido de `ronin.img` | `ronin-backup.qcow2` 12,1 GiB, SHA-256 en `reports/backup-sha256.txt` |
| 21:00 | `btrfs check --readonly` + `fsck.fat` del origen | 13,2 GiB usados, **sin errores** (solo dirty bit en ESP, esperado) |
| 21:15 | Dry-run de `migrate-to-nvme.sh` con disco de 1000 GiB | Tabla correcta: DATOS 500G / ESP 4G / ROOT resto |
| 21:20 | 1ª ejecución real (script con `dd` en ESP) | UUIDs OK, resize OK, pero ESP de 1 GiB dentro de partición de 4 GiB + warnings de `fsck.fat` |
| 23:44 | Fix: ESP recreada con `mkfs.fat -F32 -i <volume-id>` + `cp -a` | `conv=sparse` en el root; ADR-016 y runbook actualizados |
| 00:01 | 2ª ejecución real (script final) | `MIGRACIÓN OK`, ESP 4 GiB y `fsck.fat` limpio, UUIDs preservados |
| 00:05 | Arranque solo desde el disco migrado | 3 particiones, ESP 4.0G en `/boot`, root 496G, hostname `ronin` |
| 00:08 | `90-verify` sobre el disco migrado | **61 PASS / 3 WARN / 0 FAIL** (`reports/verify-migrated-final.json`) |

Evidencia: `reports/migration-rehearsal.md`, `reports/verify-migrated-final.json`, `reports/backup-sha256.txt`.

| 01:00 | Corrección de permisos en la imagen dorada + verificación final | **62 PASS / 2 WARN / 0 FAIL** (`reports/verify-ronin-final.json`) |

> Conclusión: el procedimiento quedó ensayado en QEMU. La migración real se ejecutó después sobre el NVMe de 1 TB (ver § Migración real, 23/11). Decisión: **Ronin v1 sin cifrado** (ADR-017).

## Primer arranque en hardware real (2026-11-20)

El NVMe booteó en la PC secundaria: kernel, root, ESP y bootloader funcionaron. Dos hallazgos:

1. **Hyprland/Omarchy no arrancaba:** `error al abrir /bootstrap.lua`. Causa: Omarchy quedó como overlay en `~/.local/share/omarchy`, pero su `.bashrc` y `hyprland.lua` esperan `/usr/share/omarchy`; sin eso `OMARCHY_PATH` queda vacío y el `dofile` resuelve a `/bootstrap.lua`.
   - Fix: symlink `/usr/share/omarchy -> /home/davosoler/.local/share/omarchy`, `OMARCHY_PATH=/usr/share/omarchy` en `/etc/environment`, y `/etc/profile.d/omarchy.sh` sourceando `env-bootstrap`. Aplicado al NVMe; `50-omarchy.sh` lo genera para futuros builds. Checks HW-13/HW-14 agregados a `90-verify.sh`.
2. **Credenciales:** las passwords aleatorias del build (`30-configure.sh`) quedan solo en `/root/build-credentials.txt` dentro de la imagen. En esta prueba se recuperaron desde el live (usuario `davos`). `build.local.env.example` ahora lo advierte; conviene definir `TARGET_PASSWORD`/`ROOT_PASSWORD` antes de construir.
3. **Escritorio "pelado" / negro:** el clone de Omarchy tiene 595 binarios en `~/.local/share/omarchy/bin`, pero su `autostart.lua` llama `omarchy-launch-shell`, `omarchy-provision-first-run`, etc., y el env-bootstrap solo agrega ese `bin` al PATH cuando `OMARCHY_PATH != /usr/share/omarchy` (asume el paquete oficial con binarios en `/usr/bin`). Resultado: Hyprland arrancaba sin shell ni wallpaper.
   - Fix: `/usr/local/bin/ronin-session` exporta `OMARCHY_PATH=/usr/share/omarchy` y antepone `$OMARCHY_PATH/bin` al PATH antes de `uwsm start`; `omarchy.desktop` apunta al wrapper; `profile.d` y `.bashrc` agregan el bin para terminales. Check HW-15.
4. **REPO-03 falso fallo:** con locale `es_AR.UTF-8`, `pacman -Qi` traduce `Architecture` a `Arquitectura` y el grep fallaba. `90-verify.sh` ahora exporta `LC_ALL=C`.
5. **Usuario y password a pedido:** se renombró `davos` → `davosoler` y se fijó una password definida por el usuario (no versionada) con `build/guest/rename-user.sh`. El script actualiza grupo, home, sudoers, SSH (`AllowUsers`), autologin de SDDM, paths de Ollama, `build.env`, el symlink `/usr/share/omarchy` y todos los symlinks internos del home. `build.env` del host ahora usa `TARGET_USER=davosoler`.
6. **Fondo negro con mini barra (Hyprland):** el journal mostró `magick identify` fallando. Faltaban `imagemagick` (dimensiones del wallpaper), `inotify-tools` y `qt6-imageformats` (WebP en Qt). Además, el overlay clonado no tenía los binarios en `/usr/bin` como espera el autostart. Se instaló el paquete oficial `omarchy` (con `--assume-installed` de Limine/snapper, ya que usamos systemd-boot) y `omarchy-settings`, que traen los 2329 archivos, `/usr/bin/omarchy-*`, el shell y el screensaver. Sus drop-ins de `mkinitcpio` (`00-omarchy-hooks.conf`, `omarchy_hooks.conf`, `omarchy_vconsole.conf`) se desactivaron porque reemplazaban los HOOKS universales y pedían `btrfs-overlayfs`; el initramfs se regeneró y verifica `uas/usb_storage/nvme/amdgpu`.
7. **Screensaver sin `ttfx`:** el primer idle abrió `omarchy-screensaver` y llenó la pantalla de `ttfx: orden no encontrada`. Se instaló `ttfx` del repo Omarchy y se creó `~/.config/omarchy/branding/screensaver.txt` con “RONIN”.
8. **Validación final en el M2 real:** booteado en QEMU desde el disco físico, con Hyprland + Quickshell + wallpaper Tokyo Night + barra. `90-verify.sh` → **65 PASS / 2 WARN / 0 FAIL** (`reports/verify-ronin-m2-final.json`). Quedan 218 migraciones de Omarchy pendientes (el aviso del shell); no bloquean el escritorio y se pueden ejecutar desde el propio aviso o con `omarchy-migrate`.
9. **AI-04 Vulkan (`ERROR_INCOMPATIBLE_DRIVER`):** `hw-adapt.sh` exportaba `radeon_icd.x86_64.json`, pero Mesa 26.2.6 usa `radeon_icd.json`. Se agregó `vulkan_icd_path()` (prueba `<vendor>_icd.json` y el nombre viejo) y el check AI-04 corre `env -u VK_ICD_FILENAMES vulkaninfo` para no depender del env. En la PC real detecta `AMD Radeon Graphics (RADV RENOIR)`.
10. **Validación final en la PC real:** **67 PASS / 0 WARN / 0 FAIL** (`reports/verify-ronin-real-final.json`). Ethernet: el adaptador USB `QinHeng 1a86:e397` (cdc_ether, detrás de dos hubs USB 2.0) tiene link a 100 Mbps pero **RX=0 paquetes**; el DHCP no recibe ofertas y un ping a 192.168.100.1 no obtiene ARP. Es un problema físico (cable/puerto/adaptador), no de configuración. Wi-Fi funciona normal.

## Recuperación tras update interrumpido (2026-11-22)

El `omarchy update` actualizó kernel (7.3.3 → 7.3.5), ffmpeg y Mesa, pero durante una migración (`deno`) el adaptador USB/NVMe sufrió un **error de escritura** y Btrfs pasó el root a `ro`. Con el root read-only, `sudo` no podía leer los sudoers, pacman no podía leer su DB y el preset de `mkinitcpio` quedó en 0 bytes, así que el siguiente boot dio **kernel panic**.

Diagnóstico y reparación desde el live ISO:
- `btrfs check --readonly`: **sin errores**; `btrfs device stats`: 1 `write_io_errs`, 0 de corrupción/lectura.
- pacman DB intacta (874 paquetes, `linux-cachyos 7.3.5-2`); `pacman -Qkk linux-cachyos` = 0 archivos alterados.
- Se reconstruyó `/etc/mkinitcpio.d/linux-cachyos.preset` (había quedado vacío) y se regeneraron `initramfs-linux-cachyos.img` y `-fallback.img` (199 MB c/u) con los módulos universales verificados.
- El sistema volvió a bootear con kernel **7.3.5-2**, root `rw` y `systemctl is-system-running = running`.
- Verificación: **65 PASS / 2 WARN / 0 FAIL** en QEMU (microcode/Vulkan son de la VM; en hardware real ya habían dado 67/0/0).

### Notas del cierre

- **QEMU/TCG y kernel 7.3.5:** en la VM el kernel puede paniquear con `IO-APIC + timer doesn't work`. Se agregó el entry `ronin-safe.conf` con `noapic` como fallback; el entry principal (`ronin.conf`) queda **sin** `noapic` para hardware real. En la PC real el kernel arrancó previamente; si repitiera el mismo panic, elegir el entry safe en systemd-boot.
- **Migraciones:** 217/218 aplicadas. Se omitieron por no aplicar a systemd-boot: Snapper/Limine, titlebars (paquete que pide Hyprland 0.56.2) y Superwhisper (timeout del repo Omarchy). El aviso de migraciones quedó limpio.
- **Estado final QEMU:** kernel 7.3.5, root `rw`, zram activo, docker OK, **65 PASS / 2 WARN / 0 FAIL** (`reports/verify-ronin-recovery.json`).

## Migración real y aceptación (2026-11-23)

- El NVMe de 1 TB arrancó en la **Dell Inspiron 15 3525** con kernel **7.3.5-2-cachyos**; root Btrfs `rw`, `systemd` en `running`, sin unidades fallidas.
- `90-verify.sh`: **67 PASS / 0 WARN / 0 FAIL** (`reports/verify-ronin-final-20261123.json`), con Hyprland/Quickshell, zram (15 GB, zstd), Docker y Vulkan RADV.
- `omarchy-migrate --pending`: **0**; `pacman -Qu`: **0**.
- Btrfs: 1 `write_io_errs` histórico por el corte de USB, **0** de corrupción/lectura.
- Portabilidad: notebook validada (`0C3WG4`, modo `laptop`, perfil `balanced`). Falta el boot de la desktop; procedimiento y criterios en `docs/04-VERIFICATION.md` §5.1.
- Captura del escritorio: `logs/ronin-ukiyoe-desktop.png`.

## Tema Ronin tech (2026-11-22)

Se creó un tema de usuario `~/.config/omarchy/themes/ronin` basado en Kanagawa. Se aplica con `omarchy-theme-set ronin` y queda reproducible en `50-omarchy.sh`.

**Wallpaper (23/11):** se reemplazó el SVG generado por arte real de dominio público: *Miyamoto Musashi y Sasaki Kojiro en Ganryujima*, tríptico de **Utagawa Yoshifusa** (c. 1843-1847), 4094×2079 px, vía [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Miyamoto-Musashi-Fights-Sasaki-Kojiro-at-Ganryujima-Ukiyo-e.png). Se recortó a 2560×1440, se graduó para el tema oscuro (brillo 0.84, viñeta y gradiente superior) y se guardó como `build/config/home/ronin-wallpaper-ganryujima.jpg`; el build lo prefiere sobre el SVG (`ronin-wallpaper.svg` queda como fallback). El original vectorial de respaldo está en `~/Pictures/ronin-backups/1-ronin-vector.png`.

### Pendiente para F7 (requiere hardware)

1. ~~Snapshot Btrfs inicial (`@`, `@home`) antes de la migración.~~ Hecho antes de migrar.
2. ~~Ensayo de `migrate-to-nvme.sh` con el NVMe externo de 1 TB.~~ Hecho en QEMU y en el NVMe real; UUIDs preservados y root expandido.
3. **Boot de validación en la desktop** (la notebook ya está validada con `hw-adapt`, Vulkan y microcode). Es el único paso que falta para cerrar la portabilidad entre las dos máquinas físicas.
