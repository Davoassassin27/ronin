# Registro de riesgos

Probabilidad/Impacto: A = alto, M = medio, B = bajo. Cada riesgo tiene un disparador y una mitigación verificable.

| ID | Riesgo | P | I | Disparador | Mitigación | Fase |
| --- | --- | --- | --- | --- | --- | --- |
| R-01 | Omarchy 4.5 no es compatible con CachyOS (su instalador lo rechaza) | A | A | `guard.sh` aborta; conflictos de paquetes | Spike F2.0 + ADR-001; fallback Hyprland puro; pin de commit | F2 |
| R-02 | Hyprland no inicia en QEMU (sin GPU/EGL) | M | A | `Hyprland` crashea, `hyprctl` no responde | Probar `virtio-vga-gl`, VNC, render por software; validar en hardware real | F2 |
| R-03 | WHPX no disponible; TCG demasiado lento | M | A | QEMU cae a TCG; build de horas | Habilitar `HypervisorPlatform`; si no, construir en host Linux con KVM | F0/F1 |
| R-04 | Espacio insuficiente en `E:` (120 GiB + ISO) | M | A | `doctor` falla; NTFS sin espacio | Liberar espacio, mover imagen, usar qcow2 temporal | F0 |
| R-05 | La notebook no soporta `x86-64-v3` | M | A | `ld-linux --help` sin v3 | Confirmar CPU; decidir repos genéricos o cambiar de equipo | F1/F7 |
| R-06 | GPU NVIDIA no cubierta por el driver instalado | M | A | `nvidia-smi` falla; Ollama no usa GPU | `INSTALL_NVIDIA=yes`; detectar en hw-adapt; validar en hardware | F4/F6 |
| R-07 | Inestabilidad USB-C del NVMe | M | A | `dmesg` con resets; `dd` se corta | `usbcore.autosuspend=-1`, cable/puerto directo, no hub, monitorear | F7 |
| R-08 | Sin cifrado: pérdida/robo expone datos | M | A | Dispositivo fuera de casa | ADR-007; no guardar secretos; evaluar LUKS2 post-MVP | MVP |
| R-09 | `dd` de 120 GiB sobre USB-C tarda o falla | M | M | Progreso lento, I/O errors | Dry-run, checksum/UUID, reintentar, origen intacto | F7 |
| R-10 | Migración cambia números de partición y rompe boot | B | A | UEFI no encuentra bootloader | Ruta extraíble `EFI/BOOT/BOOTX64.EFI`; probar en QEMU con segundo disco | F7 |
| R-11 | `fstab`/`root=UUID` desactualizado tras clonar | B | A | Boot emergency shell | Clonar con `dd` preservando UUID; verificar `blkid` antes de reiniciar | F7 |
| R-12 | El root de 120 GiB se llena con modelos/Docker | M | M | `No space left on device` | Monitorear; `docker system df`; modelos pequeños; expandir en F7 | F4/F6 |
| R-13 | zram insuficiente para cargas LLM | M | M | OOM killer | Modelos acordes a RAM; `btop`; no usar zram como RAM infinita | F4 |
| R-14 | Repos CachyOS/Omarchy cambian y rompen reproducibilidad | M | M | `pacman -Syu` falla; versiones distintas | Manifiesto con versiones/commit; snapshots; pin de Omarchy | Todas |
| R-15 | SDDM/autologin deja sesión accesible | M | M | Cualquiera enciende y entra | `OMARCHY_AUTOLOGIN=no` si hay riesgo; LUKS post-MVP | F2/F6 |
| R-16 | Firewall/SSH mal configurado bloquea el build | M | M | `ssh` deja de responder tras `80-harden` | Probar `sshd -t` antes de reiniciar; mantener consola QEMU; orden 90→95 | F6 |
| R-17 | Docker `nodatacow` sin checksums corrompe datos | B | M | Errores silenciosos en volúmenes | No usar para datos críticos; backups; `btrfs scrub` de otros subvols | F3 |
| R-18 | Kernel/initramfs sin driver de la segunda máquina | B | A | Boot emergency shell en la notebook | Initramfs universal sin `autodetect`; probar dos SMBIOS; `lsinitcpio` | F6 |
| R-19 | `systemd-udev-settle` deprecated y no se ejecuta | B | B | hw-adapt corre antes de udev | `After=` no lo fuerza; agregar `Wants=systemd-udev-settle.service` o usar `udevadm settle` interno | F1 |
| R-20 | `chattr +C` falla en la raíz del subvolumen Docker | M | B | `Operation not supported` | Usar `nodatacow` en fstab; `chattr` es best-effort | F1 |
| R-21 | El host Windows duerme durante un build largo | M | M | SSH se corta, QEMU sigue | Configurar energía “nunca suspender”; usar `powercfg`; monitorear | F1 |
| R-22 | Antivirus/Defender escanea el `.img` y degrada I/O | M | B | QEMU lento | Exclusión de `E:\work-os\images` (con criterio) | F1 |
| R-23 | La ISO live no trae `sshd` | B | M | `systemctl start sshd` falla | Usar consola + seed FAT; o instalar `openssh` en live | F1 |
| R-24 | Autologin + SDDM Wayland falla y no hay login gráfico | M | A | Pantalla negra | Consola TTY (Ctrl+Alt+F2), `systemctl status sddm`, logs; fallback X11/start-hyprland | F2 |
| R-25 | Modelos de GPU no confirmados (AMD/Intel/NVIDIA) | A | M | hw-adapt elige env incorrecto | Completar 07-OPEN-QUESTIONS; probar en ambas máquinas | F0 |

## Riesgos aceptados explícitamente

- **Sin cifrado** (R-08): aceptado para MVP, revisar antes de usar el equipo fuera de casa.
- **Sin Secure Boot**: aceptado; el firmware debe tener Secure Boot off.
- **Omarchy no soportado**: aceptado con spike y fallback.
- **QEMU sin GPU real**: la validación de rendimiento GPU se hace en hardware.

## Matriz de calor (resumen)

```
Impacto
  A │ R-01 R-02 R-03 R-04 R-05 R-06 R-07 R-08 R-10 R-11 R-18 R-24
  M │ R-09 R-12 R-13 R-14 R-15 R-16 R-17 R-21 R-23 R-25
  B │ R-19 R-20 R-22
    └──────────────────────────────────────────── Probabilidad
        B            M            A
```
