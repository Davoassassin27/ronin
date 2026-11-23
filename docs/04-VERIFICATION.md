# Verificación y aceptación

`build/scripts/guest/90-verify.sh` es la fuente de verdad. Este documento define qué se prueba, con qué comando y qué resultado es aceptable.

## 1. Cómo ejecutar

```powershell
.\build.ps1 verify
```

o dentro del guest:

```bash
sudo bash /root/build-scripts/guest/90-verify.sh
```

Salidas:

- Texto `PASS/FAIL/WARN` por check.
- `/var/log/ronin-verify.json` con el detalle.
- Copia en el host: `reports/verify-<timestamp>.json`.
- Traza UX (cada check y cada fallo de montaje/uso): `/var/log/ronin/ux-trace.jsonl`.

Código de salida: `0` si `fail=0`; `1` si hay fallos. Los `warn` no bloquean el MVP pero deben revisarse.

### Estado de aceptación (2026-11-18 / 19)

La suite se ejecutó como usuario con `sudo -n` **después** de `95-finalize`, que es la configuración final del sistema:

```
PASS=62 WARN=2 FAIL=0   (imagen dorada ronin.img, 20/11)
PASS=61 WARN=3 FAIL=0   (disco migrado en el ensayo QEMU, 20/11 00:08)
PASS=65 WARN=2 FAIL=0   (M2 real, sistema instalado con Omarchy completo, 22/11)
PASS=67 WARN=0 FAIL=0   (PC real, microcode y Vulkan resueltos, 22/11)
PASS=67 WARN=0 FAIL=0   (PC real, kernel 7.3.5 + tema Ronin tech, 23/11)
```

Evidencia: `reports/verify-ronin-final.json`, `reports/verify-migrated-final.json` y `reports/migration-rehearsal.md`.

En la imagen dorada solo quedan los dos warns inherentes a QEMU. En el disco migrado apareció además SEC-05 por permisos de `build-scripts` tras la copia manual; se corrigió y la imagen dorada volvió a 62/2/0.

### Trazabilidad UX

Además del reporte final, cada check y cada fallo de montaje/uso se escribe como JSONL en `/var/log/ronin/ux-trace.jsonl`:

```json
{"ts":"2026-11-19T00:00:00+00:00","level":"fail","component":"mount","message":"montar Btrfs migrado para resize","context":"...","code":32}
```

Los unit tests (`.\build.ps1 test-unit`) validan que `ux_log`, `ux_run` y la detección de disco funcionen, y dejan su propia traza en `logs/ronin-ux-*.jsonl` y `reports/unit-*.json`.

Los dos `WARN` restantes son propios de la VM de construcción y no bloquean:

| ID | Motivo | En hardware real |
| --- | --- | --- |
| BOOT-06 | QEMU no expone microcode de CPU a `journalctl -k` | AMD/Intel cargan `amd-ucode`/`intel-ucode` |
| AI-04 | No hay GPU física para `vulkaninfo` | Mesa/RADV o NVIDIA exponen Vulkan |

## 2. Matriz de aceptación

### 2.1 Imagen y arranque

| ID | Check | Comando | Esperado |
| --- | --- | --- | --- |
| BOOT-01 | Fallback UEFI | `test -f /boot/EFI/BOOT/BOOTX64.EFI` | existe |
| BOOT-02 | Bootloader operativo | `bootctl status` | exit 0, entry `ronin` |
| BOOT-03 | Entry con UUID | `grep -q 'root=UUID=' /boot/loader/entries/ronin.conf` | match |
| BOOT-04 | Kernel correcto | `pacman -Q linux-cachyos` | instalado |
| BOOT-05 | `mkinitcpio` | `mkinitcpio -P` | exit 0 |
| BOOT-06 | Microcode | `journalctl -k \| grep -i microcode` | AMD o Intel detectado |
| BOOT-07 | Secure Boot | `bootctl status \| grep 'Secure Boot'` | `disabled` (esperado) |

### 2.2 Discos y filesystems

| ID | Check | Comando | Esperado |
| --- | --- | --- | --- |
| FS-01 | GPT | `sgdisk -p /dev/vda` | 2 particiones (build) |
| FS-02 | ESP | `lsblk -f /dev/vda1` | `vfat`, label `ESP` |
| FS-03 | Root | `lsblk -f /dev/vda2` | `btrfs`, label `CACHY_ROOT` |
| FS-04 | Sin swap | `lsblk -o FSTYPE -n \| grep -q '^swap$'` | no match |
| FS-05 | Subvolúmenes | `btrfs subvolume list /` | `@`, `@home`, `@var_cache`, `@var_log`, `@docker`, `@snapshots` |
| FS-06 | Root subvol | `findmnt -no OPTIONS /` | `subvol=/@` |
| FS-07 | Opciones | `findmnt -no OPTIONS /` | `noatime`, `compress=zstd:3`, `ssd`, `discard=async`, `space_cache=v2` |
| FS-08 | Docker nodatacow | `lsattr -d /var/lib/docker` | flag `C` |
| FS-09 | fstab UUID | `grep -v '^#' /etc/fstab \| grep -q PARTUUID` | no match |
| FS-10 | fstab válido | `findmnt --verify` | exit 0 |
| FS-11 | zram | `zramctl` y `swapon --show` | `/dev/zram0`, ~50 % RAM, zstd |
| FS-12 | Espacio root | `df -h /` | > 60 GiB libres tras build |

### 2.3 Servicios

| ID | Check | Comando | Esperado |
| --- | --- | --- | --- |
| SVC-01 | NetworkManager | `systemctl is-enabled NetworkManager` | `enabled` |
| SVC-02 | SSH | `systemctl is-enabled sshd` | `enabled` |
| SVC-03 | Docker | `systemctl is-enabled docker` | `enabled` |
| SVC-04 | Ollama | `systemctl is-enabled ollama` | `enabled` |
| SVC-05 | hw-adapt | `systemctl is-enabled hw-adapt` | `enabled` |
| SVC-06 | SDDM | `systemctl is-enabled sddm` | `enabled` |
| SVC-07 | UFW | `systemctl is-enabled ufw` | `enabled` |
| SVC-08 | timesyncd | `systemctl is-enabled systemd-timesyncd` | `enabled` |
| SVC-09 | Activos | `systemctl is-active docker ollama NetworkManager` | `active` |
| SVC-10 | hw-adapt ejecutado | `systemctl status hw-adapt` | `active (exited)` |

### 2.4 Hardware y portabilidad

| ID | Check | Comando | Esperado |
| --- | --- | --- | --- |
| HW-01 | JSON válido | `jq -e . /var/log/hw-adapt-last.json` | exit 0 |
| HW-02 | Schema | `jq -e '.schema, .board, .cpu, .gpus, .profile'` | no nulos |
| HW-03 | Board real | `jq -r .board` vs `/sys/class/dmi/id/board_name` | iguales |
| HW-04 | Perfil coherente | `jq -r .profile` | `performance` desktop / `balanced` laptop |
| HW-05 | Log | `test -s /var/log/hw-adapt.log` | existe |
| HW-06 | Env GPU | `bash -n /etc/profile.d/ai-gpu-env.sh` | sintaxis OK |
| HW-07 | Hypr source | `grep -q 'require("hypr.hardware-auto")' ~/.config/hypr/hyprland.lua` | match |
| HW-08 | Initramfs USB | `lsinitcpio /boot/initramfs-linux-cachyos.img \| grep -q uas` | match |
| HW-09 | Initramfs NVMe | ídem `nvme` | match |
| HW-10 | Initramfs GPU | ídem `amdgpu`, `i915`, `xe`, `nouveau` | match |
| HW-11 | Cambio de placa | boot con `HW_ADAPT_FAKE_BOARD=...` | `changed_board=true` |
| HW-12 | Batería simulada | `HW_ADAPT_FAKE_BATTERY=1` | `mode=laptop` |
| HW-13 | Omarchy accesible | `test -f /usr/share/omarchy/default/hypr/bootstrap.lua` | existe (symlink overlay) |
| HW-14 | `OMARCHY_PATH` | `grep '^OMARCHY_PATH=' /etc/environment` | definido |
| HW-15 | Shell Omarchy | `command -v omarchy-launch-shell && test -f /usr/share/omarchy/shell/shell.qml` | existe |

> La suite fuerza `LC_ALL=C`: con `es_AR.UTF-8`, `pacman -Qi` traduce los campos (`Arquitectura` en vez de `Architecture`) y REPO-03 daba un falso fallo.

### 2.5 Dev / AI / Gaming

| ID | Check | Comando | Esperado |
| --- | --- | --- | --- |
| DEV-01 | Toolchain | `uv --version && rustc --version && go version && node --version` | todas responden |
| DEV-02 | DB clients | `duckdb --version && sqlite3 --version` | responden |
| DEV-03 | Docker root | `docker info --format '{{.DockerRootDir}}'` | `/var/lib/docker` |
| DEV-04 | Docker smoke | `docker run --rm hello-world` | exit 0 |
| DEV-05 | Docker grupo | `id -nG <user> \| grep -q docker` | match (requiere re-login) |
| AI-01 | Ollama activo | `systemctl is-active ollama` | `active` |
| AI-02 | API | `curl -fsS 127.0.0.1:11434/api/tags` | JSON |
| AI-03 | Modelos dir | `findmnt`/`ls -ld ~/ai-models/ollama` | existe y permisos |
| AI-04 | Vulkan | `vulkaninfo --summary` | exit 0 |
| AI-05 | GPU monitor | `command -v nvtop radeontop` | existen |
| AI-06 | Sin Python sistema | `python -c 'import sys; print(sys.prefix)'` | no usar `uv` global; venv por proyecto |
| GAME-01 | Meta | `pacman -Q cachyos-gaming-meta` | instalado |
| GAME-02 | Sin autostart | `systemctl list-unit-files --state=enabled \| grep -Ei 'steam|gog|heroic'` | no match |
| GAME-03 | MangoHud | `command -v mangohud` | existe |

### 2.6 Seguridad

| ID | Check | Comando | Esperado |
| --- | --- | --- | --- |
| SEC-01 | SSH root | `sshd -T \| grep '^permitrootlogin'` | `no` (tras 95) |
| SEC-02 | Password SSH | `sshd -T \| grep '^passwordauthentication'` | `no` |
| SEC-03 | UFW | `ufw status` | `Status: active` |
| SEC-04 | Sysctl | `sysctl kernel.kptr_restrict kernel.dmesg_restrict` | `2`, `1` |
| SEC-05 | Secretos | `find /root/build-scripts -name '*.env' -perm -o+r` | sin secretos legibles |
| SEC-06 | Credenciales | `stat -c '%a' /root/build-credentials.txt` | `600` |
| SEC-07 | Sudoers | `visudo -cf /etc/sudoers` | exit 0 |

### 2.7 Migración (F7)

| ID | Check | Comando | Esperado |
| --- | --- | --- | --- |
| MIG-01 | GPT final | `sgdisk -p /dev/vda` | 3 particiones en orden DATOS/ESP/ROOT |
| MIG-02 | DATOS | `lsblk -f /dev/vda1` | `exfat`, label `DATOS` |
| MIG-03 | ESP clonado | `blkid -s UUID -o value /dev/vda2` | igual al origen |
| MIG-04 | Root clonado | `blkid -s UUID -o value /dev/vda3` | igual al origen |
| MIG-05 | Root expandido | `df -h /` | ~427 GiB |
| MIG-06 | Boot sin origen | arranque con solo el destino | OK |
| MIG-07 | Verificación | `90-verify.sh` | `FAIL=0` |

## 3. Formato del reporte

```json
{
  "schema": 1,
  "timestamp": "2026-11-12T18:00:00-03:00",
  "hostname": "ronin",
  "kernel": "6.x.x-cachyos",
  "summary": { "pass": 42, "warn": 2, "fail": 0 },
  "checks": [
    { "id": "BOOT-01", "status": "pass", "detail": "/boot/EFI/BOOT/BOOTX64.EFI" },
    { "id": "AI-04", "status": "warn", "detail": "lavapipe (sin GPU real en QEMU)" }
  ]
}
```

## 4. Criterio de MVP

- `fail = 0`.
- Los `warn` están justificados por el entorno QEMU (por ejemplo, GPU virtual) y documentados.
- La migración simulada pasa `MIG-01..07`.
- El reporte queda versionado en `reports/` (sin datos sensibles).

## 5. Pruebas manuales que no automatiza el script

| Prueba | Cómo | Criterio |
| --- | --- | --- |
| Keybinds Omarchy | En la sesión: terminal, launcher, workspaces, cerrar ventana | responden |
| Audio | Reproducir un video | PipeWire/WirePlumber sin errores |
| Bluetooth | Emparejar un dispositivo | funciona tras cambio de placa |
| Suspensión | Cerrar tapa / `systemctl suspend` | despierta y red vuelve |
| USB-C NVMe | Conectar/desconectar en caliente | sin reset del bus |
| Multimonitor | Conectar HDMI/USB-C | layout automático y sin tearing |
| Gaming | Abrir Steam y un juego Proton | MangoHud/GameMode funcionan |

### 5.1 Portabilidad entre dos máquinas

El MVP exige arrancar en la desktop y en la notebook sin reinstalar. La prueba se apoya en `hw-adapt` y su historial:

1. En la máquina actual: `jq '{board,product,mode,profile,changed_board,gpus}' /var/log/hw-adapt-last.json`.
2. Apagar, mover el NVMe a la otra máquina y arrancar (si hay panic, elegir `Ronin (safe mode - noapic)`).
3. En la otra máquina, guardar la evidencia **antes de volver a mover el disco**:
   ```bash
   sudo bash /root/build-scripts/guest/91-portability-snapshot.sh
   ```
   El script archiva `/var/log/hw-adapt-<fecha>-<board>.json` y `/var/log/ronin-verify-<fecha>-<board>.json`, y muestra el resumen de `board`, `mode`, `profile` y GPUs.
4. Volver a la notebook, copiar los JSON a `reports/` y comparar.

Criterios:

- `board`/`product` cambian y `changed_board=true` en el primer boot.
- `mode` cambia (`laptop` → `desktop` o viceversa) y `profile` es coherente.
- `/var/log/hw-adapt.log` registra `board-changed from=... to=...`.
- `90-verify.sh` sigue en `FAIL=0` (los warns de GPU/microcode dependen del hardware).

**Estado 23/11:** notebook validada (`0C3WG4`, modo `laptop`, perfil `balanced`, Vulkan RADV). Boot en la desktop pendiente.

## 6. Evidencia a guardar

- `reports/verify-*.json`
- `reports/migration-*.json`
- `reports/portability-laptop-20261123.json` (línea base de la notebook)
- `/var/log/hw-adapt-last.json` de dos perfiles distintos
- `/var/log/hw-adapt.log` (historial de `board-changed`)
- `build-state.env` (UUIDs, sin secretos)
- `pacman -Qqe > /var/log/ronin/packages.txt`
- commit de Omarchy (`git -C ~/.local/share/omarchy rev-parse HEAD`)
