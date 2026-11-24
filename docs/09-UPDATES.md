# Actualizaciones y sincronización

Ronin se actualiza con **Omarchy**, no con un updater propio. Omarchy envuelve
`pacman`, las migraciones, los hooks y la verificación de boot; `pacman -Syu`
directo está bloqueado a propósito.

## Sistema

```bash
ronin update            # actualiza con `omarchy update` (manual)
ronin update --check    # solo chequea paquetes + migraciones
ronin status            # host, hardware, updates, último log, Kensei
```

El chequeo automático corre **una vez por día** con un timer de usuario
(`ronin-update-check.timer`) y notifica si hay updates. La aplicación sigue
siendo manual: `ronin update`.

No se activa auto-apply por defecto. En una notebook con NVMe portátil,
actualizar sin mirar puede meter un kernel nuevo y dejar el boot a medias. Si
se quiere full-auto, primero hay que aceptar el riesgo y definir política de
reboot; Snapper ya quedó configurado para snapshots de root.

El update real es:

```bash
omarchy update
```

`ronin update` solo agrega preflight, log en
`~/.local/state/ronin/updates/`, notificación y el chequeo diario.

## Kensei / código del proyecto

Kensei es un repositorio separado y **no** forma parte del update del sistema.
Para desarrollar contra Ronin, clonalo en `kensei/`:

```bash
git clone https://github.com/Davoassassin27/kensei.git kensei
```

Si no está vendorizado, `build/guest/65-kensei.sh` lo clona durante el
provisioning usando `KENSEI_REPO` y `KENSEI_REF` de `build/build.env`. Para
llevar cambios al NVMe, hacé commit/push en Kensei y actualizá el clon; no hay
sync automático dentro de este repositorio.

GitHub no es necesario para actualizar el sistema, solo para versionar y
distribuir el código.

## Notas del 2026-11-24

- Se instaló `snapper` y se creó `/etc/snapper/configs/root` usando el
  subvolumen `@snapshots` existente; `snapper-cleanup.timer` quedó activo.
- El update de paquetes terminó con 0 pendientes. La migración de Grok quedó
  frenada por un prompt de `mise` al correr como root; no afecta las
  migraciones del usuario (`omarchy-migrate --pending` = 0).
- Kensei: CLI en `~/.local/bin/kensei`, modelo base `kensei` en Ollama
  (`qwen2.5-coder:7b` + parámetros de Kensei). El GGUF fine-tune no está en el
  M.2; cuando exista, se reemplaza con `ollama create`.
