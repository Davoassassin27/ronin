# Architecture Decision Records (ADRs)

Formato: contexto → decisión → consecuencias → estado. Los ADRs se actualizan, no se borran.

---

## ADR-001: Integración de Omarchy sobre CachyOS

**Fecha:** 2026-11-12
**Estado:** Proposed (decision gate F2.0)

### Contexto

PROJECT.md pide “CachyOS + entorno Omarchy”. Al momento de planificar, Omarchy 4.5 se distribuye como **distro completa** (Arch + Hyprland + Limine + LUKS por defecto). Su instalador, en `install/preflight/guard.sh`, aborta si detecta `/etc/cachyos-release`, exige Arch vanilla, exige Limine y exige Btrfs. No existe un camino soportado “Omarchy sobre CachyOS”.

### Opciones

1. **Overlay (elegida para el spike):** CachyOS base + repo `[omarchy]` para paquetes `omarchy-*` + clon de configuraciones. No se ejecuta el instalador.
2. **Distro Omarchy + kernel CachyOS:** instalar Omarchy y luego reemplazar kernel/repos. Rompe el requisito de base CachyOS y su layout.
3. **Hyprland puro:** dots propios inspirados en Omarchy. Máximo control, pero no es Omarchy.

### Decisión

Adoptar la opción 1 **si y solo si** el spike de F2.0 demuestra:

- Hyprland inicia y la barra/launcher de Omarchy funciona.
- No hay conflictos críticos de paquetes con CachyOS.
- El repo de Omarchy no reemplaza los mirrors CachyOS.

Si falla, se elige opción 3 (Hyprland puro) y se documenta la desviación; la opción 2 se descarta por contradecir el objetivo de performance/base.

### Consecuencias

- (+) Mantiene `linux-cachyos`, `x86-64-v3`, Btrfs y el layout pedido.
- (+) Permite fijar commit y auditar cambios.
- (−) Integración no soportada; los updates de Omarchy pueden romper.
- (−) Hay que mantener un parche propio para `hyprland.conf` y dependencias.
- (−) Algunas features de Omarchy (migraciones, Limine snapshots, keyring) no estarán.

### Mitigación

- Pin de `OMARCHY_REF` + registro de commit en el manifiesto.
- Snapshot Btrfs antes de actualizar Omarchy.
- Suite de verificación de escritorio.
- Fallback documentado a Hyprland puro.

---

## ADR-002: `systemd-boot` con ruta extraíble

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

PROJECT.md permite `systemd-boot` o GRUB forzando ruta extraíble. Omarchy usa Limine. La migración cambia los números de partición (ESP de p2 a p3) y no queremos reinstalar el bootloader.

### Decisión

Usar `systemd-boot` instalado en el ESP y copiar el binario a `EFI/BOOT/BOOTX64.EFI`. Entry `ronin` con `root=UUID=...` y `rootflags=subvol=@`.

### Consecuencias

- (+) No depende de NVRAM ni de `efibootmgr`.
- (+) Funciona aunque el firmware no conserve variables EFI.
- (+) La migración no requiere reinstalar bootloader.
- (−) No tiene integración nativa con snapshots Btrfs.
- (−) Omarchy/Limine no se usan; si se quieren snapshots en boot, evaluar en post-MVP.

### Implementación

`bootctl --esp-path=/boot install` + copia explícita a `EFI/BOOT/BOOTX64.EFI` (idempotente). `loader.conf` con `default ronin.conf`, `timeout 3`, `editor no`.

---

## ADR-003: Sin swap física, `zram` al 50 %

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

Cargas de Python/Docker/LLM consumen RAM y pueden castigar el NVMe USB-C. PROJECT.md prohíbe swap física y pide `zram-generator` al 50 % con zstd.

### Decisión

No crear partición swap. `/etc/systemd/zram-generator.conf`:

```ini
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
```

### Consecuencias

- (+) Menos escrituras al NVMe, mejor latencia.
- (+) Swap comprimido rápido.
- (−) Si la carga supera RAM + zram, OOM kill.
- (−) Modelos LLM grandes pueden requerir más RAM que la disponible; no es un problema de swap.

### Mitigación

- `vm.swappiness=180`, `vm.page-cluster=0`, `vm.watermark_scale_factor=125`.
- Monitoreo con `btop`/`zramctl`.
- Documentar límites de modelos según RAM.

---

## ADR-004: Imagen cruda de 120 GiB en el host

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

PROJECT.md pide una imagen `.img` cruda de 120–430 GiB. El host tiene ~152 GB libres en `E:` y ~137 GB en `C:`. Una imagen de 430 GiB no entra. La migración final requiere un root de ~430 GiB, pero se puede expandir en destino.

### Decisión

Construir `ronin.img` cruda de **120 GiB** en `E:`. La migración copia esos 120 GiB al root final de ~430 GiB y ejecuta `btrfs filesystem resize max`.

### Consecuencias

- (+) Entra en el host con margen.
- (+) Los 120 GiB son suficientes para el stack MVP (sin modelos gigantes).
- (−) El root de construcción es más chico que el final; hay que probar la expansión.
- (−) Un raw sparse en NTFS puede crecer; monitorear espacio.

### Mitigación

- `build.ps1 doctor` exige imagen + 15 GB libres.
- `qemu-img info` y `df` periódicos.
- Si el espacio se agota, mover la imagen a otra unidad o usar qcow2 (fuera del MVP).

---

## ADR-005: Instalación con `pacstrap`, no instalador gráfico

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

El instalador de CachyOS es interactivo y no garantiza el layout exacto de subvolúmenes, bootloader y paquetes. Necesitamos reproducibilidad y auditoría.

### Decisión

Arrancar la ISO live, particionar con `sgdisk`/`mkfs`, montar subvolúmenes y ejecutar `pacstrap`. La configuración se hace en `arch-chroot` con scripts versionados.

### Consecuencias

- (+) Control total de paquetes, fstab, initramfs y bootloader.
- (+) Cada paso queda en `/root/build-scripts/`.
- (+) Fácil de repetir y diffear.
- (−) Más pasos manuales/automatizados que un instalador.
- (−) Dependemos de que la ISO live tenga los repos CachyOS correctos.

---

## ADR-006: Docker en subvolumen `@docker` con `nodatacow`

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

Las capas de Docker y las imágenes generan muchas escrituras pequeñas. Btrfs CoW degrada el rendimiento y fragmenta. PROJECT.md pide aislar Docker y evitar CoW.

### Decisión

Subvolumen `@docker` montado en `/var/lib/docker` con las opciones base. Se aplica `chattr +C` al directorio (nodatacow heredado) antes de que Docker escriba. No se usan `nodatacow`/`compress=no` como opciones de montaje porque Btrfs las aplica al superbloque completo, no por subvolumen.

### Consecuencias

- (+) Mejor rendimiento de Docker sobre Btrfs.
- (+) Aislado de root; se puede borrar/recrear.
- (−) `nodatacow` implica `nodatasum`; no hay checksums para esos datos.
- (−) No se puede comprimir; el espacio usado es mayor.

### Mitigación

- Backups de volúmenes importantes fuera de Docker.
- `docker system prune` periódico.
- No usar `@docker` para datos persistentes críticos.

---

## ADR-007: Sin cifrado de disco en el MVP

**Fecha:** 2026-11-12
**Estado:** Accepted for MVP / revisit

### Contexto

PROJECT.md no menciona cifrado y prioriza portabilidad/automatización. Omarchy por defecto cifra con LUKS, pero nuestro flujo no lo usa. Un dispositivo portable sin cifrado es un riesgo alto si se pierde o roba.

### Decisión

MVP sin LUKS. Documentar el riesgo y planificar LUKS2 para post-MVP.

### Consecuencias

- (+) Arranque desatendido, `hw-adapt` sin depender de desbloqueo, migración simple.
- (−) Cualquiera con acceso físico lee todos los datos.
- (−) No apto para datos sensibles fuera de casa.

### Mitigación / siguiente paso

- Evaluar LUKS2 con passphrase + `systemd-cryptenroll` (TPM opcional por máquina).
- Si se adopta, el initramfs necesita `encrypt`/`sd-encrypt` y el entry cambia.
- Mientras tanto: no guardar secretos de producción; usar `age`/`sops` para datos sensibles.

---

## ADR-008: Orquestación PowerShell + bash, sin WSL

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

El host es Windows 11. WSL2 existe pero puede estar detenido, consumir RAM y agregar una capa de indirección. QEMU corre nativo en Windows.

### Decisión

Host: PowerShell 5.1+ (`build.ps1`, scripts en `build/scripts/host/`). Guest: bash (`build/scripts/guest/`). La comunicación es SSH/SCP.

### Consecuencias

- (+) Menos dependencias; funciona con Windows nativo.
- (+) Los scripts de guest son los mismos que se usan en el sistema final.
- (−) PowerShell 5.1 tiene quirks de quoting; se encapsula en helpers.
- (−) El lint local de bash requiere Git Bash o WSL; CI lo cubre.

---

## ADR-009: Validación de portabilidad con dos perfiles SMBIOS

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

No siempre se tienen las dos máquinas físicas disponibles durante el desarrollo. Hay que probar la lógica de “desktop vs notebook” y “cambió la placa”.

### Decisión

QEMU permite inyectar DMI/SMBIOS. Probar:

```powershell
# Perfil desktop
qemu-system-x86_64 ... -smbios type=1,manufacturer=Test,product=Desktop -smbios type=2,manufacturer=Test,product=BoardA

# Perfil laptop
qemu-system-x86_64 ... -smbios type=1,manufacturer=Test,product=Notebook -smbios type=2,manufacturer=Test,product=BoardB
```

Para batería, `hw-adapt.sh` acepta `HW_ADAPT_FAKE_BATTERY=1` y `HW_ADAPT_FAKE_AC=0|1`. Para placa, `HW_ADAPT_FAKE_BOARD`.

### Consecuencias

- (+) Se prueba la lógica sin hardware real.
- (+) Se puede forzar `changed_board=true`.
- (−) No reemplaza la validación de drivers/GPU reales.
- (−) Los tests de batería son sintéticos.

---

## ADR-010: Datos y modelos en `/home`, `DATOS` solo intercambio

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

La partición `DATOS` exFAT es la primera del NVMe para compatibilidad con Windows/Android. exFAT no tiene permisos POSIX ni CoW. PROJECT.md pide `~/ai-models` y `~/workspace`.

### Decisión

Mantener `/home` en Btrfs (`@home`) para modelos, datasets y workspace. `DATOS` se usa para intercambio manual y backups, no para Docker ni bases de datos.

### Consecuencias

- (+) Permisos, CoW y snapshots funcionan en `/home`.
- (+) Windows/Android pueden leer `DATOS` sin drivers.
- (−) Los modelos ocupan espacio del root Btrfs (120 GiB de build, 430 GiB final).
- (−) Mover modelos a `DATOS` requiere symlinks y aceptar limitaciones.

---

## ADR-011: Repos CachyOS `x86-64-v3`

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

CachyOS ofrece repos optimizados `x86-64-v3`. PROJECT.md los exige. No todas las CPUs los soportan; la notebook es desconocida.

### Decisión

Usar los repos v3 que trae la ISO/`pacman.conf` de CachyOS. `00-preflight.sh` verifica soporte con `ld-linux --help`. Si la notebook no soporta v3, se debe decidir: usar `x86-64` genérico o cambiar de notebook.

### Consecuencias

- (+) Mejor rendimiento en CPUs compatibles.
- (−) La imagen no arranca en CPUs sin v3.
- (−) Hay que confirmar la CPU de la notebook antes de F7.

---

## ADR-013: Configuración de Hyprland en Lua (Omarchy 4.5)

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

Omarchy 4.5 migró su configuración de Hyprland a **Lua** (`hyprland.lua`, `hl.env`, `hl.monitor`). PROJECT.md asume `source = ~/.config/hypr/hardware-auto.conf`. Un `.conf` no es parseado por este stack.

### Decisión

`hw-adapt.sh` genera `~/.config/hypr/hardware-auto.lua` con llamadas `hl.env(...)` y `hl.monitor({...})`. `hyprland.lua` termina con `require("hypr.hardware-auto")`. El path `.conf` de la especificación se considera obsoleto para esta versión.

### Consecuencias

- (+) Integración real con Omarchy 4.5.
- (−) Desviación literal de PROJECT.md; documentada acá.
- (−) Si Omarchy vuelve a `.conf`, hay que adaptar el generador.

---

## ADR-012: `hw-adapt` como oneshot pre-login, no daemon permanente

**Fecha:** 2026-11-12
**Estado:** Accepted

### Contexto

La detección y el ajuste de hardware ocurren una vez por boot, antes del entorno gráfico. No hace falta un daemon que consuma recursos.

### Decisión

`Type=oneshot`, `RemainAfterExit=yes`, `Before=display-manager.service greetd.service sddm.service`. Sin timer, sin socket, sin polling.

### Consecuencias

- (+) Cero overhead después del boot.
- (+) Fácil de testear y loguear.
- (−) No reacciona a cambios en caliente (conectar GPU externa, cambiar de AC). Para eso se puede correr manualmente o agregar un timer en post-MVP.
- (−) Si falla, el boot sigue (no bloquea) pero el perfil puede quedar incompleto; el JSON lo refleja.

---

## ADR-014: TCG por defecto; WHPX experimental

**Fecha:** 2026-11-12
**Estado:** Accepted (temporal)

### Contexto

Con WHPX, el live ISO arrancó y funcionó, pero el kernel instalado 7.3.3 se congeló tras el primer reboot. QEMU registró `failed to get xsave state` y `WHPX: Unexpected VP exit code 4`. Con TCG (`-cpu max`) el mismo disco arrancó y aceptó SSH.

### Decisión

`build.env` usa `VM_ACCEL=tcg`. El flag `-Whpx` permite probar WHPX cuando se actualice QEMU/kernel. El build es más lento pero reproducible.

### Consecuencias

- (+) Estabilidad del entorno de construcción.
- (-) Builds y compilaciones (DKMS) mucho más lentas.
- (-) No se puede validar rendimiento real de CPU/GPU en QEMU.
- (+) El sistema final en hardware real no usa TCG; solo afecta al host de build.

### Revisión

Probar WHPX de nuevo cuando QEMU > 11.1 o kernel CachyOS > 7.3.3. Si funciona, cambiar `VM_ACCEL=whpx`.

---

## ADR-015: Nombre "Ronin" y filosofía de diseño

**Fecha:** 2026-11-19
**Estado:** Accepted

### Contexto

El proyecto necesita una identidad propia coherente con la filosofía zen / bushido que el usuario aplica a sus proyectos. Hasta ahora se lo denominaba con un nombre descriptivo, sin carga conceptual ni identidad propia.

### Decisión

El sistema se llama **Ronin** (el samurái sin amo): no pertenece a una máquina, reconoce el terreno en cada arranque y se adapta sin dependencias fijas. Se renombran hostname, entry de systemd-boot, paths `/etc/ronin` y `/var/log/ronin-*`, manifiesto y documentación. Se provee `build/guest/rename-to-ronin.sh` para aplicar la identidad sobre una imagen ya construida sin rebuild.

### Consecuencias

- (+) Identidad alineada con el resto de proyectos del usuario.
- (+) El nombre refuerza la propiedad central: portabilidad sin amo.
- (−) Cambio de paths en logs y manifiestos; los reportes históricos mantienen sus nombres de archivo.
- (−) La imagen ya construida requiere ejecutar el script de renombrado (o un rebuild).

---

## ADR-016: ESP de 4 GiB en el NVMe final

**Fecha:** 2026-11-19
**Estado:** Accepted

### Contexto

La especificación original pedía una ESP de 1 GiB. El ecosistema Omarchy/CachyOS se movió a Limine con `limine-snapper-sync`, que requiere ~4 GiB para kernels/snapshots. Nuestro build usa systemd-boot (1 GiB suficiente), pero el disco destino tiene 1 TB y el margen es gratuito.

### Decisión

`NVME_ESP_SIZE=4G` en `build.env`. La ESP se **recrea** con `mkfs.fat -F32 -i <volume-id original>` y se copian sus archivos (un `dd` de 1 GiB dejaría 3 GiB sin filesystem). El UUID se preserva igual; el root final pasa a ~427 GiB.

### Consecuencias

- (+) Margen para migrar a Limine en el futuro sin reparticionar.
- (+) UUID y fstab intactos.
- (−) ~3 GiB menos para el root (de ~430 a ~427 GiB).

---

## ADR-017: Sin cifrado en el MVP; decisión antes de F7

**Fecha:** 2026-11-19
**Estado:** Accepted — decidido explícitamente por el usuario: **Ronin v1 sin cifrado**. Se evaluará otra forma de protección en una versión posterior; no se bloquea F7.

### Contexto

ADR-007 ya dejaba LUKS2 fuera del MVP. Un dispositivo portable tiene riesgo real de pérdida/robo, y el cifrado altera initramfs, `fstab`, UUIDs y el entry de boot: implementarlo después de la migración es casi un rebuild completo.

### Decisión

La migración a F7 se ejecuta **sin cifrar**, confirmando ADR-007. El usuario lo decidió explícitamente el 19/11/2026: *"para esta primera versión de Ronin no hagamos cifrado, ya vemos de meter otra cosa después"*. Por lo tanto el gate del runbook queda **cerrado: SIN CIFRADO**, y no se requiere rebuild antes de migrar. Cualquier mecanismo de protección se evalúa como una versión posterior (no como LUKS2 sobre la v1).

### Consecuencias

- (+) MVP sin cambios de última hora y con la verificación ya en verde.
- (−) Riesgo de exposición de datos si se pierde el NVMe.
- (−) La decisión debe revisarse antes de salir con el equipo a la calle (H-01/S-01 en `07-OPEN-QUESTIONS.md`).
