# Roadmap F0 → MVP

> Fuente funcional: [PROJECT.md](../PROJECT.md).
> Este documento convierte la especificación en fases ejecutables, con entregables y criterios de salida verificables.

## 1. Definición de MVP

El MVP está terminado cuando **una imagen cruda de 120 GiB**, construida y validada íntegramente en QEMU, cumple todo esto:

1. Arranca en UEFI con `systemd-boot` extraíble (`/boot/EFI/BOOT/BOOTX64.EFI`) y `root=UUID=...`.
2. Monta la tabla GPT y los 6 subvolúmenes Btrfs con las opciones definidas, sin swap física y con `zram` activo.
3. `hw-adapt.service` corre antes del login, detecta hardware, aplica perfil de energía/GPU, escribe `/var/log/hw-adapt-last.json` y sobrevive a un cambio simulado de placa.
4. El escritorio Omarchy/Hyprland inicia y el usuario puede abrir terminal, lanzar aplicaciones y usar los keybinds básicos.
5. Docker, Ollama, el toolchain de desarrollo y Vulkan funcionan; `docker run hello-world` y la API de Ollama responden.
6. Gaming está instalado pero no arranca servicios pesados al boot.
7. `90-verify.sh` devuelve `FAIL=0` en el sistema recién instalado.
8. `migrate-to-nvme.sh` migra la imagen a un segundo disco de 1 TB **simulado en QEMU**, conserva UUIDs, expande Btrfs y el disco migrado arranca y pasa la misma verificación.

Todo lo que no sea necesario para esos 8 puntos queda fuera del MVP (ver §10).

## 2. Convenciones

PROJECT.md usa “Fase 1” (construcción en QEMU) y “Fase 2” (migración al NVMe). Para no ambigüedad, este roadmap usa **F0–F7**:

| Fase del roadmap | Mapa a PROJECT.md |
| --- | --- |
| F0 | Preparación del host (previa a Fase 1) |
| F1–F6 | Fase 1: construcción y pruebas en la imagen |
| F7 | Fase 2: migración al M.2 externo |

Estimaciones en días de trabajo efectivos, no calendario. Incluyen pruebas, no solo escritura de scripts.

## 3. Resumen

| Fase | Objetivo | Estimación | Depende de | Estado |
| --- | --- | --- | --- | --- |
| F0 | Host listo, ISO verificada, imagen creada, SSH key | 0.5 d | — | ✅ |
| F1 | Imagen CachyOS base que arranca y acepta SSH | 2–3 d | F0 | 🟡 |
| F2 | Entorno Omarchy/Hyprland integrado | 2–4 d | F1 | 🟡 |
| F3 | Stack Dev/DevOps + Docker | 1 d | F1 | 🟡 |
| F4 | Stack AI local (Ollama, Vulkan, uv) | 1–2 d | F1, F3 | ⬜ |
| F5 | Gaming bajo demanda | 0.5 d | F1 | ⬜ |
| F6 | Portabilidad, hardening, pruebas de dos perfiles | 1–2 d | F2–F5 | ⬜ |
| F7 | Migración NVMe + aceptación MVP | 1–2 d | F6 | ⬜ |

**Total estimado: 9–15 días efectivos.** Los riesgos que más pueden mover la aguja son la integración de Omarchy (F2) y el rendimiento/estabilidad de QEMU con WHPX (F0/F1).

---

## F0 — Host y repositorio listos

**Objetivo:** eliminar incertidumbre del entorno antes de tocar la imagen.

### Tareas

- [x] Estructura del repositorio, `.gitignore`, `.editorconfig`.
- [x] `build.env` con parámetros de imagen, usuario, timezone, ISO.
- [x] CLI `build.ps1` con `doctor`, `install-qemu`, `fetch-iso`, `image`, `up-iso`, `ssh`, `provision`, `verify`.
- [x] Scripts de host: diagnóstico, instalación QEMU, descarga/verificación ISO, creación de imagen, arranque/parada.
- [x] Scripts de guest: preflight, particionado, bootstrap, configuración, hw-adapt, Omarchy, stack, verificación.
- [x] Documentación: arquitectura, runbooks, ADRs, riesgos, preguntas abiertas.
- [x] QEMU 11.1.0 instalado en el host.
- [x] ISO CachyOS 260809 descargada (3.0 GiB) y checksum registrado.
- [ ] Ejecutar `.\build.ps1 doctor` y dejar el reporte en verde.
- [ ] Verificar WHPX (o dejar documentado el fallback TCG).
- [ ] Crear `E:\work-os\images\ronin.img` (120 GiB) y `edk2-vars.fd`.
- [ ] Generar clave SSH `%USERPROFILE%\.ssh\ronin_ed25519` y copiar la pública a `build/ssh/authorized_keys`.
- [ ] Primera prueba de arranque de la ISO en QEMU y acceso a consola.
- [ ] Confirmar que el SSD M.2 externo **no está conectado** o que QEMU no lo ve.

### Criterios de salida

```powershell
.\build.ps1 doctor
# READY, 0 FAIL, 0 WARN críticos
```

- `qemu-system-x86_64.exe --version` responde.
- `edk2-x86_64-code.fd` y `edk2-i386-vars.fd` existen.
- SHA-256 de la ISO coincide.
- Espacio libre en `E:` ≥ tamaño de imagen + 15 GB.
- La ISO llega a GRUB/consola en QEMU.

### Riesgos de fase

- WHPX no disponible → TCG es 5–20× más lento; la instalación puede tardar horas.
- Espacio en NTFS: un `.img` crudo puede crecer hasta 120 GiB; monitorear `E:` durante el build.

---

## F1 — Imagen base CachyOS

**Objetivo:** un sistema CachyOS mínimo, portable y arrancable, con SSH, red, Btrfs y bootloader extraíble.

### Tareas

- [ ] Arrancar la ISO con `-boot once=d` y UEFI.
- [ ] En la consola live: `systemctl start sshd`, `passwd root`, verificar `ip a`.
- [ ] Copiar `build/` al guest con el seed disk o `scp`.
- [ ] `00-preflight.sh`: UEFI, disco objetivo, red, soporte `x86-64-v3`, herramientas.
- [ ] `10-partition.sh`: GPT (ESP 1 GiB + Btrfs), 6 subvolúmenes, montajes.
- [ ] `20-bootstrap.sh`: `pacstrap` con `base`, `linux-cachyos`, firmware, microcodes y herramientas.
- [ ] `30-configure.sh`: locale, teclado, hostname, usuario, sudo, SSH, fstab por UUID, zram, mkinitcpio universal, `systemd-boot` extraíble.
- [ ] Primer arranque desde el disco (sin ISO).
- [ ] Verificar SSH por clave a `root@127.0.0.1:2222`.
- [ ] Snapshot del estado base (documentar `btrfs subvolume snapshot` o `snapper`; todavía no automatizado).

### Criterios de salida

- `/boot/EFI/BOOT/BOOTX64.EFI` existe.
- `mkinitcpio -P` termina con código 0.
- `bootctl status` muestra el entry `ronin`.
- `findmnt --verify` sin errores.
- `lsblk -f` muestra `ESP` FAT32 y `CACHY_ROOT` Btrfs; no hay swap.
- `findmnt /` muestra `subvol=/@` y las opciones pactadas.
- `journalctl -k | grep -i microcode` confirma microcode cargado.
- `ssh -i ... root@127.0.0.1 -p 2222` funciona.
- El sistema reinicia solo y vuelve a levantar sin la ISO.

### Entregables

- `build/scripts/guest/10-partition.sh`, `20-bootstrap.sh`, `30-configure.sh` ejecutados y auditados en `/root/build-scripts/`.
- `build-state.env` con UUIDs reales.
- Reporte `preflight` y `mkinitcpio` guardados.

---

## F2 — Entorno Omarchy (decision gate)

**Objetivo:** escritorio Hyprland con la experiencia Omarchy (barra, terminal, launcher, temas, keybinds), integrado con `hardware-auto.conf`.

### Decisión bloqueante

Omarchy 4.5 es una **distribución completa** y su instalador (`install/preflight/guard.sh`) rechaza CachyOS, exige Arch vanilla, Limine y Btrfs. No se puede ejecutar el instalador tal cual.

Rutas posibles:

| Ruta | Descripción | Pros | Contras |
| --- | --- | --- | --- |
| **A. Overlay (recomendada)** | CachyOS + paquetes `omarchy-*` + configuración de Omarchy clonada y parchada | Mantiene kernel CachyOS y el layout pedido | Integración no soportada; hay que resolver dependencias |
| B. Distro Omarchy + kernel CachyOS | Instalar Omarchy y reemplazar kernel/repos | Escritorio “oficial” | Rompe el requisito “basado en CachyOS”; layout/encryption de Omarchy |
| C. Hyprland puro | Dots propios inspirados en Omarchy | Máximo control, menos riesgo | No es “Omarchy” y requiere más trabajo de UX |

**Gate F2.0:** hacer un spike de 4–6 horas con la ruta A en un snapshot descartable. Si Hyprland inicia, barra/launcher funcionan y no hay conflictos de paquetes, se adopta A. Si falla, se elige B o C con registro en ADR-001.

### Tareas (ruta A)

- [ ] Agregar el repo `[omarchy]` sin reemplazar los mirrors de CachyOS.
- [ ] Instalar keyring y paquetes `omarchy-*` necesarios (`omarchy-nvim`, `omarchy-walker`, shell/barra).
- [ ] Instalar Hyprland, SDDM, `uwsm`, portal XDG, utilidades (grim/slurp/wl-clipboard, etc.).
- [ ] Clonar Omarchy en `~/.local/share/omarchy` con `OMARCHY_REF` fijado y registrar commit.
- [ ] Copiar `config/` y `default/bashrc`; **no** ejecutar el instalador completo.
- [ ] Copiar `default/wayland-sessions/omarchy.desktop` y configurar SDDM (Wayland + autologin opcional).
- [ ] Añadir `require("hypr.hardware-auto")` al final de `hyprland.lua` (Omarchy 4.5 usa Lua).
- [ ] Validar que el escritorio inicia en QEMU (VNC/GTK) o documentar la limitación de render.
- [ ] Validar keybinds básicos: terminal, launcher, workspace, cerrar ventana.

### Criterios de salida

- `systemctl is-enabled sddm` = `enabled`.
- `hyprctl version` responde en la sesión.
- La barra/launcher de Omarchy aparece y responde.
- `~/.config/hypr/hardware-auto.lua` se genera en cada boot y es leído por Hyprland.
- No hay paquetes de CachyOS reemplazados por versiones incompatibles de Omarchy (auditar `pacman -Qo` y `pacman -Syu` en seco).

### Riesgos de fase

- Dependencias de Omarchy no disponibles o con versiones incompatibles.
- SDDM/Wayland no arranca en QEMU por falta de GPU/EGL.
- El repo de Omarchy cambia; por eso se fija `OMARCHY_REF` y se registra el commit.

---

## F3 — Software Engineering & DevOps

**Objetivo:** toolchain diario y Docker funcionando con datos en `@docker`.

### Tareas

- [ ] Instalar Git, GitHub CLI, tmux, Neovim, ripgrep, fd, fzf, jq, yq, btop, rclone.
- [ ] Instalar `uv`, Python, Rust, Go, Node/npm.
- [ ] Instalar Docker, compose, buildx, kubectl, helm, lazydocker.
- [ ] `daemon.json`: data-root, log rotation, live-restore.
- [ ] Habilitar `docker.service`, agregar usuario a `docker`.
- [ ] Clientes de datos: `postgresql-libs`, `sqlite`, `duckdb`.
- [ ] Crear `~/workspace` y un proyecto de ejemplo con `uv` (sin contaminar el Python del sistema).
- [ ] Smoke test: `docker run --rm hello-world`.

### Criterios de salida

- `docker info` muestra `Docker Root Dir: /var/lib/docker`.
- El usuario ejecuta Docker sin `sudo` tras re-login.
- `uv --version`, `rustc --version`, `go version`, `node --version` responden.
- `duckdb --version`, `sqlite3 --version`, `psql --version` (cliente) responden.
- `hello-world` pasa.

---

## F4 — AI local

**Objetivo:** inferencia local con Ollama, GPU detectada dinámicamente y aislamiento de entornos Python.

### Tareas

- [ ] Instalar stack Vulkan/Mesa/VA-API y monitores (`nvtop`, `radeontop`).
- [ ] Instalar `ollama`, habilitar servicio local-only.
- [ ] Redirigir modelos a `~/ai-models/ollama` con permisos correctos.
- [ ] Generar `/etc/profile.d/ai-gpu-env.sh` desde `hw-adapt.sh`.
- [ ] Crear `~/ai-models/{ollama,huggingface,datasets}` y `~/workspace` con `uv`.
- [ ] Smoke test de API (`/api/tags`) y de inferencia con un modelo pequeño.
- [ ] Documentar cómo cambiar de backend (ROCm/CUDA/Vulkan/CPU) sin romper portabilidad.

### Criterios de salida

- `systemctl is-active ollama` = `active`.
- `curl -fsS http://127.0.0.1:11434/api/tags` responde JSON.
- `ollama run qwen2.5:0.5b "ping"` responde en CPU (QEMU) o GPU (hardware real).
- `vulkaninfo --summary` detecta al menos un dispositivo (aunque sea lavapipe en QEMU).
- `ai-gpu-env.sh` es sintácticamente válido y coherente con la GPU detectada.

---

## F5 — Gaming bajo demanda

**Objetivo:** stack de gaming instalado sin servicios pesados al arranque.

### Tareas

- [ ] Instalar `cachyos-gaming-meta` (Steam, Proton-CachyOS, GameMode, MangoHud, lib32).
- [ ] Verificar que no se habilita Steam/GOG/etc. al login.
- [ ] Documentar excepciones (GameMode puede ser servicio ligero).
- [ ] Smoke test: paquetes instalados, `vulkaninfo`, `mangohud` disponible.

### Criterios de salida

- `pacman -Q cachyos-gaming-meta` responde.
- `systemctl list-unit-files --state=enabled` no muestra Steam ni launchers pesados.
- `vulkaninfo` sigue funcionando.
- No se agregaron autostart entries de juegos.

---

## F6 — Portabilidad, hardening y ensayo de dos máquinas

**Objetivo:** que la misma imagen arranque en dos hardware distintos y se comporte distinto pero correctamente.

### Tareas

- [ ] Initramfs universal sin `autodetect`; incluir `uas`, `usb_storage`, `nvme`, `xhci_pci`, `ahci`, `amdgpu`, `i915`, `xe`, `nouveau`, `virtio_*`.
- [ ] Ambos microcodes (`amd-ucode`, `intel-ucode`).
- [ ] `usbcore.autosuspend=-1` en el kernel cmdline.
- [ ] `systemd-boot` en ruta extraíble; verificar que no depende de variables EFI.
- [ ] `fstab` 100 % por UUID; `root=UUID=`.
- [ ] Probar arranque con dos perfiles SMBIOS: “desktop” y “laptop” (QEMU `-smbios`).
- [ ] Simular batería (`HW_ADAPT_FAKE_BATTERY=1`) y cambio de placa (`HW_ADAPT_FAKE_BOARD=...`).
- [ ] Verificar limpieza de estados huérfanos (Bluetooth/audio/red) al cambiar de placa.
- [ ] UFW activo, SSH solo claves, root SSH deshabilitado al final.
- [ ] `sysctl` de hardening y journald con límites.
- [ ] Documentar el procedimiento de recuperación (root console, snapshot).

### Criterios de salida

- Dos boots con SMBIOS distintos generan `hw-adapt-last.json` con `mode` y `profile` correctos.
- El segundo boot con placa distinta registra `changed_board=true` y ejecuta las acciones.
- `lsinitcpio` contiene todos los drivers requeridos.
- `bootctl status` sigue OK tras el cambio de perfil.
- `sshd -T` no permite password ni root.
- `ufw status` activo.

---

## F7 — Migración al NVMe y aceptación MVP

**Objetivo:** volcar la imagen al disco final de 1 TB conservando UUIDs y demostrar que arranca.

> **Estado 24/11:** migración real completada y booteada en la Dell Inspiron 15 3525 (**67 PASS / 0 WARN / 0 FAIL**) y en la desktop **B450M DS3H-CF** (`mode=desktop`, `profile=performance`, GPU AMD). Portabilidad validada; el `90-verify.sh` nativo de la desktop queda como comprobación opcional.

### Tareas

- [x] Implementar `build/scripts/guest/migrate-to-nvme.sh` con `--dry-run` por defecto.
- [x] Probar en QEMU con un **segundo disco de 1 TB** (sparse/qcow2) adjuntado como `/dev/vdb`.
- [x] Crear GPT final: `DATOS` exFAT ~500 GiB (primera), `ESP` 4 GiB, `ROOT` resto.
- [x] Clonar ESP y root preservando UUIDs (`dd` de las particiones).
- [x] `btrfs filesystem resize max /` en el destino.
- [x] Verificar que `fstab` y `root=UUID=` siguen válidos sin edición.
- [x] Arrancar desde el disco migrado (QEMU `-boot order=c` con el segundo disco como principal).
- [x] Pasar `90-verify.sh` en el disco migrado y en hardware real.
- [x] Boot nativo en la segunda máquina física (desktop B450M DS3H-CF; `hw-adapt` mode=desktop/performance).
- [ ] Ensayar rollback (la imagen original queda intacta). No se ejecutó un rollback formal porque la migración no falló; el `.img` original sigue disponible.

### Criterios de salida

- El disco migrado arranca sin la ISO y sin el disco original.
- `lsblk -f` muestra `DATOS` exFAT, `ESP` FAT32, `CACHY_ROOT` Btrfs.
- `blkid` del root migrado coincide con el original.
- `df -h /` muestra ~427 GiB disponibles.
- `90-verify.sh` = `FAIL=0`.
- `PROJECT.md` actualizado con el estado final y desviaciones.

---

## 4. Orden de ejecución recomendado

```
F0 ──► F1 ──► F2 (gate) ──► F3 ──► F4 ──► F5 ──► F6 ──► F7
             │
             └── si el gate falla: decisión ADR-001 antes de seguir
```

F3/F4/F5 pueden ejecutarse en paralelo después de F1 si hay tiempo, pero F6 necesita F2–F5 estables.

## 5. Hitos y fechas tentativas

| Hito | Contenido | Fecha objetivo |
| --- | --- | --- |
| M0 | Host doctor verde + ISO + imagen | Día 1 |
| M1 | Sistema base arranca y SSH | Día 3–4 |
| M2 | Escritorio Omarchy estable | Día 6–8 |
| M3 | Stack dev + AI + gaming | Día 9–11 |
| M4 | Portabilidad probada | Día 12–13 |
| MVP | Migración NVMe validada | Día 14–15 |

Fechas relativas; ajustar al calendario real.

## 6. Decision gates

| Gate | Cuándo | Decisión | Si falla |
| --- | --- | --- | --- |
| G0 | Fin F0 | ¿WHPX funciona? ¿espacio suficiente? | TCG lento o mover imagen a otra unidad |
| G1 | Fin F1 | ¿arranca sin ISO y SSH estable? | no avanzar a F2 |
| G2 | F2.0 | ¿Omarchy overlay es viable? | ruta B o C (ADR-001) |
| G3 | Fin F4 | ¿Ollama responde en QEMU? | modo CPU documentado; GPU se valida en hardware real |
| G4 | Fin F6 | ¿dos perfiles de hardware OK? | corregir initramfs/hw-adapt antes de migrar |
| G5 | Fin F7 | ¿MVP? | no declarar MVP |

## 7. Definition of Done global

- [ ] Todos los scripts se ejecutan de forma idempotente o fallan con mensaje claro.
- [ ] Cada fase deja log en `/root/build-scripts/reports/` y, si aplica, en `/var/log/`.
- [ ] `90-verify.sh` es la única fuente de verdad para “funciona”.
- [ ] `PROJECT.md` y este roadmap reflejan el estado real.
- [ ] No hay secretos versionados.
- [ ] El SSD externo real nunca se tocó durante F0–F6.

## 8. Backlog post-MVP (no bloqueante)

- Cifrado LUKS2 + TPM/clevis o passphrase (ADR-007).
- Snapshots automáticos con Snapper y entradas de boot.
- `fwupd` para firmware.
- Perfiles de hardware por `board_name` con overrides persistentes.
- Telemetría local de builds (`/var/log/ronin/`).
- CI con shellcheck/PSScriptAnalyzer y build reproducible en un runner Linux con KVM.
- Soporte NVIDIA propietario vs open según GPU concreta.
- Modelos LLM descargados en `DATOS` con verificación de integridad.
- Secure Boot (requiere firmar kernel/initramfs; hoy explícitamente deshabilitado).

## 9. Qué NO se hace en este MVP

- Instalar en el SSD físico real sin ensayo previo en QEMU.
- Cifrado de disco (queda como decisión posterior).
- Dual boot con Windows.
- Pass-through de GPU o audio.
- Configuración completa de Omarchy (todos los plugins/temas/apps).
- Descarga masiva de modelos LLM.
- Automatización del instalador live de CachyOS (se usa `pacstrap` manual/scriptado).

## 10. Estado de ejecución

Actualizar esta sección al cerrar cada fase.

| Fecha | Fase | Resultado | Evidencia |
| --- | --- | --- | --- |
| 2026-11-12 | F0 | QEMU 11.1.0; ISO 260809 verificada; imagen 120 GiB; SSH key; primer boot live | `logs/`, `docs/08-BUILD-LOG.md` |
| 2026-11-12 | F1 | GPT+Btrfs+6 subvols, pacstrap, fstab, initramfs, systemd-boot; boot TCG y SSH | `/root/build-scripts/reports/`, UUIDs en build-state |
| 2026-11-12 | F2 | Hyprland 0.57 + SDDM + Omarchy overlay (commit `ac6cb9c`) | `logs/omarchy-console.log` |
| 2026-11-19 | F3–F6 | Toolchain, Docker, Ollama, Steam, `hw-adapt`, UFW y hardening; verify en QEMU | `reports/verify-ronin-final.json` |
| 2026-11-20 | F7 | Migración al NVMe de 1 TB; primer boot real en la Inspiron y fixes de Omarchy | `docs/08-BUILD-LOG.md` |
| 2026-11-22 | F7 | Microcode y Vulkan (RADV) resueltos en hardware real: **67 PASS / 0 WARN / 0 FAIL** | `reports/verify-ronin-real-final.json` |
| 2026-11-23 | F7 | Kernel 7.3.5, 0 migraciones/updates y tema Ronin con ukiyo-e de Musashi | `reports/verify-ronin-final-20261123.json` |
| 2026-11-24 | F7 | Boot nativo en desktop B450M DS3H-CF; `mode=desktop`, `profile=performance`, GPU AMD | `reports/hw-adapt-log-portability-20261124.txt` |
