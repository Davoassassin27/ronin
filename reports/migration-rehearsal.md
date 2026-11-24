# Ensayo de migración a NVMe — QEMU (2026-11-19/20)

Ejecución real de `build/guest/migrate-to-nvme.sh` sobre un disco de prueba de 1000 GiB adjunto a la VM, con el live ISO de CachyOS como entorno de ejecución. Es la primera vez que el script corre de punta a punta (antes solo había tests con mocks).

## Comando

```bash
CONFIRM_MIGRATE=YES bash /root/build-scripts/guest/migrate-to-nvme.sh \
  --target /dev/vdb \
  --source-disk /dev/vda \
  --source-esp /dev/vda1 \
  --source-root /dev/vda2 \
  --yes
```

## Origen y destino

| Item | Valor |
| --- | --- |
| Origen | `/dev/vda` (imagen `ronin.img`, 120 GiB) |
| ESP origen | `/dev/vda1`, UUID `C6B0-4875` |
| Root origen | `/dev/vda2`, UUID `3eaf056b-315b-4155-bc57-1d0bbdbff996` |
| Destino | `/dev/vdb`, 1000 GiB (archivo sparse `nvme-test.img`) |

## Tabla creada

| Partición | Tamaño | Tipo | FS | Resultado |
| --- | --- | --- | --- | --- |
| `/dev/vdb1` | 500G | `0700` | exFAT | `DATOS` |
| `/dev/vdb2` | 4G | `ef00` | FAT32 | ESP recreada con el mismo volume ID, 1046524 clusters (~4 GiB) |
| `/dev/vdb3` | resto (496G en el disco de prueba) | `8300` | Btrfs | clon + `btrfs filesystem resize max` |

> En el NVMe real de 1 TB (~931 GiB útiles) el root queda en ~427 GiB. En el disco de prueba de 1000 GiB quedó en 496 GiB.

## Resultado

- `dd` del root: 127774211584 bytes (119 GiB) en 987,8 s (~129 MB/s).
- UUIDs preservados (verificación del script: `UUIDs preservados`).
- Resize: `Resize device id 1 (/dev/vdb3) from 119.00GiB to max` → 496G, 13G usados, 483G libres.
- ESP: `fsck.fat` sin advertencias con el script final (la primera pasada con `dd` sí había dado *boot sector/backup differences* y *dirty bit*; se corrigió recreando la ESP con `mkfs.fat -F32 -i <volume-id>` y copiando archivos).
- Resultado del script: `MIGRACIÓN OK` (00:01:10).

## Arranque desde el disco migrado (sin origen)

```text
vda1 exfat DATOS   7BFF-E9E0
vda2 vfat  ESP     C6B0-4875   4.0G  -> /boot
vda3 btrfs CACHY_ROOT 3eaf... 496G   -> /
findmnt -no SOURCE /  ->  /dev/vda3[/@]
hostname              ->  ronin
```

Suite de aceptación sobre el disco migrado: **61 PASS / 3 WARN / 0 FAIL** (`reports/verify-migrated-final.json`). Los checks FS-01/02/03 pasaron con el layout de 3 particiones, confirmando que `detect_disk_layout` reemplaza correctamente el `/dev/vda3` hardcodeado.

Los 3 WARN son los esperados: BOOT-06 (microcode en QEMU), AI-04 (Vulkan sin GPU) y SEC-05 (permisos de `build-scripts` por la copia manual posterior a `finalize`; ya corregido en `rename-to-ronin.sh`).
