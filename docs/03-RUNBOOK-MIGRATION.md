# Runbook — migración al NVMe externo (F7)

> **Operación destructiva.** El script es **dry-run por defecto** (no acepta `--dry-run`): solo escribe con `--yes` y confirmación interactiva. El disco origen (`ronin.img`) **no se modifica**. Todo fallo de montaje o migración se registra en `/var/log/ronin/ux-trace.jsonl`.

## 1. Objetivo

Volcar la imagen validada de 120 GiB a un NVMe de 1 TB USB-C con esta tabla GPT final:

| # | Tamaño | FS | Label | Contenido |
| --- | --- | --- | --- | --- |
| 1 | ~500 GiB | exFAT | `DATOS` | datos plug-and-play (Windows/Android) |
| 2 | 4 GiB | FAT32 | `ESP` | clon del ESP original (margen para Limine/snapshots de Omarchy) |
| 3 | resto (~427 GiB) | Btrfs | `CACHY_ROOT` | clon del root, expandido |

> El ESP pasó de 1 GiB a 4 GiB porque el ecosistema Omarchy/CachyOS se movió a Limine + `limine-snapper-sync`, que pide ~4 GiB. Con systemd-boot 1 GiB alcanzaba, pero el margen es gratis en un disco de 1 TB. El UUID no cambia: la ESP se recrea con `mkfs.fat -F32 -i <volume-id>` y se copian sus archivos (un `dd` dejaría los 3 GiB extras sin filesystem).

Requisitos:

- Conservar UUID de filesystem del ESP y del root (para no tocar `fstab` ni `root=UUID=`).
- El bootloader debe seguir siendo extraíble (`EFI/BOOT/BOOTX64.EFI`), porque el ESP cambia de partición 2 a 3.
- No crear swap.
- `DATOS` no se usa para `/home` ni Docker.

## 2. Antes de empezar: snapshot y decisión de cifrado

1. **Snapshot Btrfs del origen** (punto de retorno cómodo, además de que el `.img` queda intacto):
   ```bash
   sudo btrfs subvolume snapshot -r / /.snapshots/pre-migracion-$(date +%Y%m%d)
   sudo btrfs subvolume snapshot -r /home /.snapshots/home-pre-migracion-$(date +%Y%m%d)
   sudo btrfs subvolume list /
   ```
2. **Decisión de cifrado: CERRADA — SIN CIFRADO para Ronin v1.** Confirmado explícitamente por el usuario el 19/11 y registrado en ADR-017. No se requiere rebuild ni cambios de initramfs/fstab/UUIDs. Cualquier mecanismo de protección se evalúa en una versión posterior, no en la v1. (Si esto cambiara, tendría que decidirse antes de este paso: cambia initramfs, `fstab`, UUIDs y el entry de boot, y después de migrar es casi un rebuild.)

## 3. Ensayo en QEMU (obligatorio antes del hardware real)

### 3.1 Crear un segundo disco de 1 TB

```powershell
& "C:\Program Files\QEMU\qemu-img.exe" create -f raw E:\work-os\images\nvme-test.img 1000G
```

> Es sparse; ocupa poco al inicio. Para el ensayo también se puede usar qcow2, pero el script espera un disco de bloque; QEMU lo expone igual.

### 3.2 Arrancar la VM con el disco origen y el destino

```powershell
.\build.ps1 up -ExtraDisk E:\work-os\images\nvme-test.img
```

Dentro del guest, el destino será `/dev/vdb` (o `/dev/vdc` si hay más discos). Verificar:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
```

**Nunca** ejecutar el script sobre `/dev/vda` (origen). El script aborta si detecta que el destino contiene el root montado.

### 3.3 Dry-run

```bash
cd /root/build-scripts
bash guest/migrate-to-nvme.sh --target /dev/vdb
```

Debe imprimir:

- tamaño del destino y espacio libre,
- tabla GPT propuesta,
- UUIDs origen/destino,
- comandos `sgdisk`, `mkfs.exfat`, `dd`, `btrfs resize`,
- advertencia de que no hay vuelta atrás en el destino.

### 3.4 Ejecución

```bash
bash guest/migrate-to-nvme.sh --target /dev/vdb --yes
```

Pasos del script:

1. `wipefs -a /dev/vdb`, `sgdisk --zap-all`.
2. GPT final y `partprobe`.
3. `mkfs.exfat -n DATOS /dev/vdb1`.
4. `mkfs.fat -F32 -i <volume-id original> -n ESP /dev/vdb2` + `cp -a` del contenido de la ESP origen (UUID preservado, filesystem de 4 GiB completo).
5. `dd if=<ROOT_ORIGEN> of=/dev/vdb3 bs=64M conv=fsync status=progress`.
6. `blkid` y comparación de UUIDs; abortar si no coinciden.
7. `mount -o subvol=@ /dev/vdb3 /mnt`; `btrfs filesystem resize max /mnt`; `umount`.
8. `fsck.fat -n /dev/vdb2`; `btrfs check --readonly` (opcional, lento).
9. Reporte `/var/log/ronin-migration.json`.

> `dd` copia los 120 GiB completos, incluido espacio libre. Tarda ~15–40 min según USB-C. No desenchufar.

### 3.5 Validar el disco migrado antes de desconectar el origen

**Validar primero con ambos discos presentes**: apagar, arrancar desde `nvme-test.img` pero dejando el origen conectado como segundo disco:

```powershell
.\build.ps1 down
.\build.ps1 up -Image E:\work-os\images\nvme-test.img -ExtraDisk E:\work-os\images\ronin.img
```

> Ojo: origen y destino tienen el **mismo UUID de root** (es lo que se preservó a propósito). Con ambos conectados hay que confirmar que el root montado es realmente el NVMe: `findmnt -no SOURCE /` debe mostrar `/dev/vda3` (el destino en esta VM), no el disco origen. Si el firmware/kernel eligió el origen, apagar, desconectar el origen y repetir solo con el NVMe.

Verificar:

```bash
lsblk -f
# vda1 DATOS exfat
# vda2 ESP vfat
# vda3 CACHY_ROOT btrfs
df -h /
# ~427 GiB disponibles
blkid
# UUID del root == UUID original
bootctl status
findmnt --verify
```

Pasar la suite:

```bash
bash /root/build-scripts/guest/90-verify.sh
```

## 4. Migración al hardware real

### 4.1 Preparación

- Backup de cualquier dato del NVMe (se va a borrar).
- Conectar por USB-C, preferentemente con cable corto y puerto directo (sin hub).
- Confirmar que el kernel lo ve:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN
sudo dmesg | tail -50
```

- Identificar el dispositivo correcto (`/dev/nvme0n1` o `/dev/sda`). **No adivinar.**
- Verificar que no esté montado:

```bash
findmnt -S /dev/nvme0n1
```

### 4.2 Dry-run

```bash
sudo bash /root/build-scripts/guest/migrate-to-nvme.sh \
  --target /dev/nvme0n1
```

Revisar tamaño, modelo y tabla propuesta.

### 4.3 Ejecución

```bash
sudo bash /root/build-scripts/guest/migrate-to-nvme.sh \
  --target /dev/nvme0n1 --yes
```

El script pide escribir el modelo exacto del disco para confirmar.

### 4.4 Primer arranque desde el NVMe

1. Apagar.
2. **No desconectar todavía el disco interno**: seleccionar el NVMe en el menú UEFI y arrancar desde él.
3. Verificar de inmediato `findmnt -no SOURCE /` y pasar la suite (§4.5). Solo después de ver `FAIL=0`, apagar y desconectar el origen. Si por el UUID duplicado arrancó el disco interno, desconectarlo y repetir.
4. Conectar el NVMe por USB-C.
4. Arrancar con UEFI; seleccionar el dispositivo USB/NVMe.
5. Verificar que aparece `Ronin` y que arranca.

Si el firmware no lista el dispositivo como booteable, usar el menú de arranque UEFI y seleccionar `EFI/BOOT/BOOTX64.EFI` desde el disco.

### 4.5 Verificación post-migración

```bash
lsblk -f
findmnt -no SOURCE,FSTYPE,OPTIONS /
blkid
df -h /
systemctl is-enabled docker ollama NetworkManager hw-adapt sshd sddm ufw
curl -fsS http://127.0.0.1:11434/api/tags
docker run --rm hello-world
bash /root/build-scripts/guest/90-verify.sh
```

Criterios:

- `DATOS` es la primera partición.
- El root tiene ~427 GiB y conserva el UUID.
- `fstab` y `root=UUID=` no se editaron.
- Los servicios están `enabled`.
- `90-verify.sh` da `FAIL=0`.

## 5. Rollback

El disco origen queda intacto. Si la migración falla:

1. Apagar y volver a arrancar desde `ronin.img`.
2. No borrar el NVMe hasta decidir.
3. Si el fallo fue de hardware, probar otro cable/puerto.
4. Si el fallo fue de tabla, repetir el dry-run y revisar el modelo detectado.

## 6. Riesgos específicos

| Riesgo | Mitigación |
| --- | --- |
| USB-C se desconecta durante `dd` | `usbcore.autosuspend=-1`, cable corto, no usar hub, monitorear `dmesg` |
| El firmware no arranca desde USB | Usar ruta extraíble `EFI/BOOT/BOOTX64.EFI`; probar otro puerto |
| UUID no coincide | El script aborta antes de tocar el bootloader; comparar `blkid` |
| Root no expande | `btrfs filesystem resize max /`; verificar `btrfs filesystem usage /` |
| El disco aparece como `/dev/sda` en vez de `nvme0n1` | Usar el nombre real; el script no asume |
| Windows/Android no lee `DATOS` | exFAT con label `DATOS`; primera partición; sin cifrado |
| Pérdida de datos por error de target | Confirmación por modelo + `--dry-run` + origen intacto |

## 7. Post-migración

- Actualizar `PROJECT.md` con la tabla final y UUIDs (sin secretos).
- Guardar `reports/migration-*.json`.
- Opcional: mover modelos LLM/datasets a `DATOS` con symlinks, entendiendo que exFAT no tiene permisos POSIX.
- Programar `btrfs scrub` mensual y `fstrim` (aunque `discard=async` ya está activo).
- Evaluar cifrado LUKS2 en post-MVP (ADR-007).

## 8. Comandos de emergencia

```bash
# Ver UUIDs
sudo blkid

# Ver tabla GPT
sudo sgdisk -p /dev/nvme0n1

# Ver subvolúmenes del destino
sudo mount -o subvolid=5 /dev/nvme0n1p3 /mnt
sudo btrfs subvolume list /mnt

# Verificar ESP
sudo fsck.fat -n /dev/nvme0n1p2

# Verificar root (solo lectura; puede tardar)
sudo btrfs check --readonly /dev/nvme0n1p3

# Chroot de rescate desde la ISO
sudo mount -o subvol=@ /dev/nvme0n1p3 /mnt
sudo mount /dev/nvme0n1p2 /mnt/boot
sudo arch-chroot /mnt
```
