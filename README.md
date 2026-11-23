# Ronin — CachyOS portable de ingeniería

Sistema Linux portable (desktop + notebook) basado en **CachyOS** (`linux-cachyos`, `x86-64-v3`) con el entorno **Omarchy** (Hyprland, teclado/terminal first), stack de Software Engineering, DevOps, Data Science y AI local, más un módulo de gaming opcional.

El objetivo de este repositorio es que la construcción sea **reproducible, auditable y verificable**, no una sucesión de comandos manuales.

## Nombre y filosofía

**Ronin** — el samurái sin amo. El sistema no pertenece a una máquina: se mueve entre la desktop y la notebook, reconoce el terreno en cada arranque y se adapta sin preguntar ni depender de un hogar fijo.

Los principios de diseño (zen / bushido) que gobiernan el proyecto:

- **Sin amo:** ningún hardware, proveedor ni instalador interactivo decide por nosotros. Boot extraíble, UUIDs reales y repositorios fijos.
- **Cambia, no se rompe:** `hw-adapt.service` lee el entorno en cada boot, aplica el perfil de energía/GPU correcto y lo deja registrado. Como el rōnin, no resiste el cambio de terreno.
- **Disciplina antes que velocidad:** cada paso tiene un script, un log y una verificación. La reproducibilidad manda sobre la ocurrencia.
- **Ligero y afilado:** zram en vez de swap, Btrfs con subvolúmenes aislados, initramfs universal sin `autodetect`, servicios de juego que solo despiertan cuando se los necesita.
- **Deja rastro:** todo fallo de montaje o de uso se escribe en un log estructurado (`/var/log/ronin/ux-trace.jsonl`) para que la experiencia sea trazable y depurable.

- [PROJECT.md](PROJECT.md) — especificación original (fuente de verdad funcional).
- [docs/00-ROADMAP.md](docs/00-ROADMAP.md) — plan F0 → MVP, tareas y criterios de salida.
- [docs/01-ARCHITECTURE.md](docs/01-ARCHITECTURE.md) — arquitectura, particiones, subvolúmenes, boot y flujos.
- [docs/02-RUNBOOK-BUILD.md](docs/02-RUNBOOK-BUILD.md) — procedimiento de construcción en QEMU.
- [docs/03-RUNBOOK-MIGRATION.md](docs/03-RUNBOOK-MIGRATION.md) — migración al NVMe externo.
- [docs/04-VERIFICATION.md](docs/04-VERIFICATION.md) — matriz de aceptación y verificación automática.
- [docs/05-ADRS.md](docs/05-ADRS.md) — decisiones de arquitectura.
- [docs/06-RISKS.md](docs/06-RISKS.md) — riesgos y mitigaciones.
- [docs/07-OPEN-QUESTIONS.md](docs/07-OPEN-QUESTIONS.md) — preguntas a resolver antes/durante el build.
- [docs/08-BUILD-LOG.md](docs/08-BUILD-LOG.md) — bitácora de la primera construcción real e incidencias.

## Estado actual (2026-11-23)

| Fase | Estado | Notas |
| --- | --- | --- |
| F0 — Host y repositorio | ✅ completada | QEMU 11.1.0, ISO verificada, imagen 120 GiB, clave SSH, primer boot live |
| F1 — Imagen base CachyOS | ✅ completada | GPT, ESP, Btrfs + 6 subvolúmenes, fstab por UUID, initramfs universal, systemd-boot extraíble, `mkinitcpio -P` OK |
| F2 — Entorno Omarchy | ✅ completada | Overlay + SDDM + Hyprland + `hardware-auto.lua`; la validación gráfica queda limitada por la GPU virtual (TCG) |
| F3 — Dev / DevOps | ✅ completada | Toolchain (uv/rust/go/node), Docker, kubectl/helm, `x86-64-v3` |
| F4 — AI local | ✅ completada | Ollama activo en `127.0.0.1:11434`, stack Vulkan y directorios `ai-models`/`workspace`; Vulkan no verificable en QEMU |
| F5 — Gaming | ✅ completada | Steam, gamemode, MangoHud y lib32; sin launchers al arranque |
| F6 — Portabilidad y hardening | ✅ completada | `hw-adapt.service`, microcodes, `usbcore.autosuspend=-1`, UFW, sysctl, root SSH deshabilitado |
| F7 — Migración NVMe / MVP | 🟡 casi completa | Migración real al NVMe y boot en la Inspiron OK (67/0/0); falta el boot de validación en la desktop para cerrar la portabilidad |

**Verificación final en la PC real (kernel 7.3.5, 23/11):** `67 PASS / 0 WARN / 0 FAIL` ([`reports/verify-ronin-final-20261123.json`](reports/verify-ronin-final-20261123.json)), con Hyprland/Quickshell, tema **Ronin tech** (Kanagawa), wallpaper del duelo de **Miyamoto Musashi** (ukiyo-e de Utagawa Yoshifusa, dominio público), barra, zram y Vulkan (AMD RADV) funcionando. Sin warnings.

**Verificación de la imagen dorada:** `62 PASS / 2 WARN / 0 FAIL` ([`reports/verify-ronin-final.json`](reports/verify-ronin-final.json)).

**Migración real al NVMe (23/11):** el disco de 1 TB arrancó en la **Dell Inspiron 15 3525** con kernel 7.3.5-2, root Btrfs `rw`, zram, Docker, **0 migraciones**, **0 updates** y **67 PASS / 0 WARN / 0 FAIL** ([`reports/verify-ronin-final-20261123.json`](reports/verify-ronin-final-20261123.json)). La tabla final quedó DATOS/ESP/ROOT con UUIDs preservados. Falta un único boot en la desktop para cerrar la validación de portabilidad entre las dos máquinas físicas.

**Ensayo F7 en QEMU:** la migración se ejecutó de punta a punta sobre un disco de prueba de 1 TB y arrancó sola con **61 PASS / 3 WARN / 0 FAIL** ([`reports/verify-migrated-final.json`](reports/verify-migrated-final.json), [`reports/migration-rehearsal.md`](reports/migration-rehearsal.md)). El ensayo validó el procedimiento; la migración real lo superó.

> **Hallazgo importante:** WHPX congeló el guest instalado (kernel 7.3.3) tras el reboot. `build.env` usa `VM_ACCEL=tcg` por defecto; el build es más lento pero estable. Ver [docs/08-BUILD-LOG.md](docs/08-BUILD-LOG.md).

## Inicio rápido (host Windows)

Requisitos: Windows 10/11 x64, virtualización habilitada, 32 GB de RAM recomendados, ~140 GB libres en la unidad de imágenes, QEMU y curl.

```powershell
# 1. Diagnóstico del host
.\build.ps1 doctor

# 2. Instalar/verificar QEMU (si falta)
.\build.ps1 install-qemu

# 3. Descargar y verificar la ISO de CachyOS
.\build.ps1 fetch-iso

# 4. Crear el disco crudo de 120 GiB y la NVRAM UEFI
.\build.ps1 image

# 5. Arrancar la ISO en QEMU (UEFI + WHPX)
.\build.ps1 up-iso

# 6. En la consola de la ISO: habilitar SSH y ejecutar el preflight
#    systemctl start sshd
#    passwd root
#    curl -fsSL .../bootstrap-live.sh | bash   (ver runbook)
```

Después del primer arranque del sistema instalado:

```powershell
.\build.ps1 ssh          # consola root en el guest
.\build.ps1 provision    # copia scripts y ejecuta 40 → 95
.\build.ps1 verify       # suite de aceptación
.\build.ps1 test-unit    # tests de disco/UX + reports/unit-*.json
```

## Mapa del repositorio

```
build.ps1                     CLI del host (PowerShell 5.1+)
build/
  build.env                   parámetros versionados (sin secretos)
  build.local.env.example     plantilla de secretos locales
  iso/                        ISO (ignorada por git)
  config/                     archivos que se instalan en el guest
    etc/                      systemd, hw-adapt, docker, zram, sysctl...
    usr/local/bin/            hw-adapt.sh
    home/                     README de workspace
  scripts/host/               diagnóstico, QEMU, ISO, imagen, SSH
  scripts/guest/              particionado, pacstrap, configuración, stack, verificación
docs/                         plan, arquitectura, runbooks, ADRs, riesgos
tests/                        lint + unit tests (disco/UX) y trazabilidad
```

## Decisiones críticas ya tomadas

1. **La imagen se construye en QEMU, nunca sobre el SSD externo.** El disco externo solo se toca en F7 con `migrate-to-nvme.sh` y confirmación explícita.
2. **Instalación manual con `pacstrap`, no el instalador interactivo de CachyOS.** Permite fijar paquetes, subvolúmenes, kernel e initramfs de forma reproducible.
3. **`systemd-boot` con ruta extraíble** (`EFI/BOOT/BOOTX64.EFI`), en lugar de Limine/GRUB. La migración conserva UUIDs y el bootloader no depende del número de partición.
4. **Sin swap física; `zram` al 50 % con zstd.**
5. **Omarchy se integra como overlay de escritorio, no con su instalador.** El instalador de Omarchy 4.5 aborta explícitamente en CachyOS y exige Limine. Ver [ADR-001](docs/05-ADRS.md#adr-001-integración-de-omarchy-sobre-cachyos) y el *decision gate* de F2.

## Estado de la ISO

- Archivo: `build/iso/cachyos-desktop-linux-260809.iso`
- SHA-256 esperado: `959f6577f45e25ee9fd8c220fd221b08e4ea79412c7315c0f922dd6d86d5e33c`
- Verificación: `.\build.ps1 fetch-iso` (idempotente; no vuelve a descargar si el hash coincide).

## Seguridad

Esta especificación **no incluye cifrado de disco**. Para un dispositivo portable eso es un riesgo alto (pérdida/robo). El MVP respeta la especificación, pero [ADR-007](docs/05-ADRS.md#adr-007-sin-cifrado-de-disco-en-el-mvp) deja el cifrado LUKS2 como decisión pendiente para post-MVP. No guardar credenciales reales en el repositorio.
