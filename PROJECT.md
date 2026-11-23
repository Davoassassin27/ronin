# OBJETIVO DEL PROYECTO

**Nombre del sistema: Ronin** (el samurái sin amo). Filosofía: sin amo, sin hogar fijo; adaptarse al hardware en cada arranque, con disciplina, ligereza y registro de todo lo que ocurre. Ver [README.md](README.md#nombre-y-filosofía).

Construir e instalar un sistema operativo Linux portátil, de grado ingeniería y alto rendimiento basado en \*\*CachyOS\*\* (kernel optimizado con scheduler BORE/EEVDF y repositorios `x86-64-v3`) con el entorno \*\*Omarchy\*\* (Hyprland + flujo centrado en teclado/terminal).

\*\*Prioridad de diseño:\*\*

1. \*\*Núcleo principal (80%):\*\* Software Engineering, DevOps, Ciencia de Datos y AI Engineering (inferencia local acelerada por GPU, contenedores, pipelines de datos, compilación).

2. \*\*Módulo secundario (20%):\*\* Gaming ocasional aprovechando el mismo stack Vulkan/Mesa.

El sistema debe ser \*\*100% portable entre dos computadoras físicas distintas\*\* (una PC de escritorio principal y una notebook), adaptándose automáticamente al hardware en cada arranque y dejando registro auditado.

---

# ESTRATEGIA DE CONSTRUCCIÓN Y DESPLIEGUE (2 FASES)

## Fase 1: Construcción y pruebas en disco local de la PC (Entorno Actual)

- \*\*No escribir todavía sobre el SSD M.2 externo.\*\*

- Todo el armado, particionado inicial, instalación y validación se realizará sobre una \*\*imagen cruda (`.img`) alojada en el disco interno de la PC host\*\* (ej. `ronin.img` de `120 GiB` a `430 GiB`) ejecutada bajo QEMU (arranque UEFI + `-cpu host`) y controlada por SSH (`root@localhost -p 2222`).

- \*\*Particiones dentro de la imagen de construcción (Tabla GPT):\*\*

  1. \*\*Partición 1 (`1 GiB`):\*\* `FAT32`, flag `esp`/`boot`, punto de montaje `/boot` (partición EFI).

  2. \*\*Partición 2 (`Resto de la imagen`):\*\* `Btrfs`, etiqueta `CACHY_ROOT`.

## Fase 2: Migración al M.2 NVMe externo (1 TB por USB-C)

- Dejar listo en `/root/build-scripts/[migrate-to-nvme.sh](http://migrate-to-nvme.sh)` el procedimiento exacto para volcar el sistema al NVMe externo de 1 TB con esta tabla GPT final:

  1. \*\*Partición 1 (`~500 GiB`):\*\* `exFAT`, etiqueta `DATOS` (primera en la tabla para compatibilidad plug-and-play con Windows y Android/OTG).

  2. \*\*Partición 2 (`4 GiB`):\*\* Clon de la partición `EFI` (`FAT32`). Se amplió de 1 a 4 GiB para dar margen a Limine/`limine-snapper-sync` del ecosistema Omarchy; el clon es bit a bit, así que el UUID no cambia.

  3. \*\*Partición 3 (`Resto del disco ~427 GiB`):\*\* Clon de `CACHY_ROOT` (`Btrfs`), ejecutando `btrfs filesystem resize max /` para absorber todo el espacio restante.

- \*\*Preservación de UUIDs:\*\* Conservar los UUIDs originales al clonar las particiones 2 y 3 para mantener intactos `/etc/fstab` y el bootloader.

---

# SUBVOLÚMENES BTRFS Y OPTIMIZACIÓN DE I/O (CLAVE PARA USB-NVME)

El tráfico pesado de Docker, modelos LLM y datasets sobre USB-C requiere aislar escrituras y evitar Copy-on-Write en bases de datos/imágenes. Configurar los siguientes subvolúmenes en `CACHY_ROOT` con `noatime,compress=zstd:3,ssd,discard=async,space_cache=v2`:

- `@` -&gt; `/`

- `@home` -&gt; `/home`

- `@var_cache` -&gt; `/var/cache`

- `@var_log` -&gt; `/var/log`

- `@docker` -&gt; `/var/lib/docker` (aplicar atributo `chattr +C` / `nodatacow` para evitar degradación de rendimiento con capas de contenedores e imágenes).

- `@snapshots` -&gt; `/.snapshots`

\*(No crear partición Swap física; configurar `zram-generator` con compresión `zstd` en RAM al 50% de la memoria física para soportar cargas pesadas de Python/Docker/LLMs sin castigar el NVMe).\*

---

# DAEMON DE ACOPLAMIENTO Y AUDITORÍA DE HARDWARE (`hw-adapt.service`)

Crear e instalar un servicio `systemd` obligatorio que se ejecute \*\*en cada arranque antes del entorno gráfico\*\* (`Before=display-manager.service greetd.service sddm.service`, `After=[local-fs.target](http://local-fs.target) systemd-udev-settle.service`).

## Especificaciones de `/usr/local/bin/[hw-adapt.sh](http://hw-adapt.sh)` y `/etc/systemd/system/hw-adapt.service`

1. \*\*Detección completa de entorno:\*\*

   - Identificar placa base (`/sys/class/dmi/id/board_name`), CPU (`lscpu`), RAM total, presencia de batería (`BAT*` en `/sys/class/power_supply/` para distinguir desktop vs. notebook), GPUs activas (`lspci -nn | grep -E "VGA|3D"`) y VRAM disponible.

2. \*\*Acoplamiento dinámico de cómputo, energía y gráficos:\*\*

   - \*\*Perfil Energía y Cómputo:\*\* En modo notebook (con batería), activar perfil equilibrado/eficiente (`powerprofilesctl set balanced`) y limitar turbo agresivo si no está conectada a corriente; en desktop, activar perfil `performance` y gobernadores de CPU de máxima respuesta.

   - \*\*Aceleración AI / GPU dinámica:\*\* Detectar el vendor de la GPU activa (AMD ROCm/Vulkan, Intel SYCL/Level-Zero/Vulkan o NVIDIA) y exportar variables de entorno limpias en `/etc/profile.d/[ai-gpu-env.sh](http://ai-gpu-env.sh)` y `~/.config/hypr/hardware-auto.conf` (ej. `HSA_OVERRIDE_GFX_VERSION` si aplica para AMD, backend de Vulkan/VA-API y escalado de monitores conectados).

   - \*\*Saneamiento entre máquinas:\*\* Si el `board_name` cambió respecto al último arranque, limpiar estados huérfanos de Bluetooth/audio y re-indexar interfaces de red.

3. \*\*Registro persistente (Logging):\*\*

   - Escribir log cronológico en `/var/log/hw-adapt.log` y generar `/var/log/hw-adapt-last.json` con el inventario exacto del hardware detectado, perfil aplicado y variables exportadas en ese boot.

---

# REGLAS CRÍTICAS DE PORTABILIDAD (2 PCs DIFERENTES)

1. \*\*Bootloader extraíble:\*\* Instalar `systemd-boot` o `GRUB` forzando la ruta EFI estándar (`--removable` en GRUB o `EFI/BOOT/BOOTX64.EFI`).

2. \*\*Initramfs universal:\*\* Incluir `uas`, `usb_storage`, `nvme`, `xhci_pci`, `ahci` y drivers gráficos (`amdgpu`, `i915`, `xe`, `nouveau`) en `mkinitcpio` (`MODULES`), evitando que `autodetect` recorte módulos necesarios para la segunda máquina.

3. \*\*Montaje estricto por UUID:\*\* Todo `/etc/fstab` y `root=UUID=...` deben usar UUIDs reales (`blkid`).

4. \*\*Estabilidad USB-C NVMe:\*\* Incluir `usbcore.autosuspend=-1` en los parámetros del kernel (`CMDLINE`) para evitar desconexiones por ahorro de energía USB.

5. \*\*Compatibilidad binaria:\*\* Fijar repositorios de CachyOS en \*\*`x86-64-v3`\*\* e instalar \*\*ambos microcodes\*\* (`amd-ucode` e `intel-ucode`).

---

# STACK DE SOFTWARE A INSTALAR Y CONFIGURAR

## 1. Base CachyOS y Entorno Omarchy

- Kernel `linux-cachyos` + `linux-cachyos-headers`, `pipewire`, `wireplumber`, `networkmanager`, `bluez`, `power-profiles-daemon`, `pciutils`, `usbutils`, `jq`.

- Desplegar \*\*Omarchy\*\* sobre el usuario principal, integrando `source = ~/.config/hypr/hardware-auto.conf` en Hyprland.

## 2. Software Engineering &amp; DevOps

- \*\*Contenedores y Orquestación:\*\* `docker`, `docker-compose`, `docker-buildx`, `kubectl`, `helm`, `lazydocker` (habilitar `docker.service` y añadir usuario al grupo `docker`).

- \*\*Lenguajes, Runtimes y Tooling:\*\* `git`, `github-cli`, `uv`, `python`, `rustup`, `go`, `nodejs`, `npm`, `tmux`, `neovim`, `openssh`, `rclone`, `btop`, `ripgrep`, `fd`, `fzf`, `jq`, `yq`.

- \*\*Clientes de Datos:\*\* `postgresql-libs`, `sqlite`, `duckdb` (CLI).

## 3. Ciencia de Datos &amp; AI Engineering (Local-First)

- \*\*Aceleración y Compute:\*\* Stack Vulkan completo (`vulkan-icd-loader`, `vulkan-tools`, `mesa`, `vulkan-radeon`, `vulkan-intel`) + herramientas de monitoreo de GPU (`nvtop`, `radeontop`).

- \*\*Inferencia Local y Entornos ML:\*\* Instalar `ollama` (habilitar `ollama.service` configurado para escuchar localmente) y preparar estructura de directorios en `/home/<usuario>/ai-models` y `/home/<usuario>/workspace` con entornos virtuales aislados vía `uv` (evitando contaminar el Python del sistema).

## 4. Gaming (Módulo Complementario)

- Instalar `cachyos-gaming-meta` (Steam, Proton-CachyOS, Gamemode, MangoHud, dependencias `lib32`) sin habilitar servicios pesados en segundo plano al arranque (que se activen solo bajo demanda al abrir Steam/juegos).

---

# PROTOCOLO DE EJECUCIÓN Y VERIFICACIÓN DEL AGENTE

1. \*\*Inspección previa:\*\* Verificar discos con `lsblk -f` en QEMU antes de tocar particiones.

2. \*\*Auditoría:\*\* Guardar todos los scripts ejecutados en `/root/build-scripts/`.

3. \*\*Verificación obligatoria antes de cerrar Fase 1:\*\*

   - Confirmar existencia de `/boot/EFI/BOOT/BOOTX64.EFI` y código de salida `0` en `mkinitcpio -P`.

   - Ejecutar `/usr/local/bin/[hw-adapt.sh](http://hw-adapt.sh)` y mostrar `/var/log/hw-adapt-last.json` para validar la detección de hardware y generación de perfiles.

   - Verificar que `docker.service`, `ollama.service`, `NetworkManager.service` y `hw-adapt.service` están habilitados (`enabled`).