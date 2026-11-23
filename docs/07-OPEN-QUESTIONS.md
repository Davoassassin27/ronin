# Preguntas abiertas

Responder antes de la fase indicada. Las que bloquean el MVP están marcadas con 🔴.

## Hardware

| # | Pregunta | Por qué | Default si no se responde | Fase |
| --- | --- | --- | --- | --- |
| H-01 | 🔴 ¿Modelo exacto del desktop y de la notebook? | Drivers, DMI, batería, GPU | Ryzen 5700X + QEMU para desktop; notebook desconocida | F0/F6 |
| H-02 | 🔴 ¿La CPU de la notebook soporta `x86-64-v3`? | CachyOS v3 no arranca sin eso | Asumir que sí y verificar en preflight | F1/F7 |
| H-03 | 🔴 ¿GPU del desktop y de la notebook? (AMD/Intel/NVIDIA, integrada/discreta) | `hw-adapt`, Vulkan, Ollama | Instalar drivers de todas; env dinámico | F4/F6 |
| H-04 | ¿La notebook tiene batería y AC detectables por sysfs? | Perfil laptop | Simular con `HW_ADAPT_FAKE_BATTERY` | F6 |
| H-05 | ¿Hay TPM 2.0 en alguna? | Cifrado post-MVP | No asumir | Post-MVP |
| H-06 | ¿El NVMe externo es USB-C 3.2/Thunderbolt? ¿Cable y puerto? | Estabilidad de migración | Cable corto, puerto directo | F7 |

## Sistema y seguridad

| # | Pregunta | Por qué | Default | Fase |
| --- | --- | --- | --- | --- |
| S-01 | 🔴 ¿Aceptás que el MVP no tenga cifrado de disco? | Riesgo alto en portable | Sí, con ADR-007; revisar antes de salir de casa | F1 |
| S-02 | ¿Querés autologin en SDDM? | Comodidad vs seguridad | `OMARCHY_AUTOLOGIN=yes` | F2 |
| S-03 | ¿SSH debe escuchar solo en localhost/LAN o en todas las interfaces? | Superficie de ataque | UFW permite 22 con clave; sin password | F6 |
| S-04 | ¿Usuario `davos` y timezone `America/Argentina/Buenos_Aires`? | Configuración base | Sí | F0 |
| S-05 | ¿Teclado `latam` o `us`? | Consola/SDDM | `la-latin1` | F0 |
| S-06 | ¿Idioma `es_AR.UTF-8` o `en_US.UTF-8`? | Locale | `es_AR.UTF-8` | F0 |
| S-07 | ¿Aceptás perder root password recovery por SSH? | Hardening | Root local habilitado, SSH root no | F6 |

## Omarchy / escritorio

| # | Pregunta | Por qué | Default | Fase |
| --- | --- | --- | --- | --- |
| O-01 | 🔴 ¿Omarchy overlay (ADR-001) o preferís Omarchy distro + kernel CachyOS? | Cambia toda la F2 | Overlay; gate F2.0 | F2 |
| O-02 | ¿Qué features de Omarchy son imprescindibles? (barra, launcher, temas, keybinds, AI menu) | Priorizar el overlay | Barra + launcher + terminal + keybinds | F2 |
| O-03 | ¿Aceptás SDDM + autologin, o preferís greetd? | Login | SDDM | F2 |
| O-04 | ¿Querés el tema Tokyo Night u otro? | UX | Tokyo Night | F2 |

## Datos y modelos

| # | Pregunta | Por qué | Default | Fase |
| --- | --- | --- | --- | --- |
| D-01 | ¿Qué modelos LLM pensás correr? | RAM/VRAM/espacio | Modelos ≤7B cuantizados | F4 |
| D-02 | ¿Los modelos van en `/home` o en `DATOS`? | exFAT sin permisos; espacio | `/home` (ADR-010) | F4/F7 |
| D-03 | ¿Necesitás datasets grandes (>50 GiB) en el equipo? | Espacio root | No en MVP; `DATOS` para intercambio | F4 |
| D-04 | ¿Docker va a correr muchos contenedores? | `@docker` tamaño, RAM | Uso normal de dev | F3 |

## Build / operación

| # | Pregunta | Por qué | Default | Fase |
| --- | --- | --- | --- | --- |
| B-01 | ¿El build se hace en esta PC Windows o preferís un host Linux con KVM? | Rendimiento | Windows + WHPX | F0 |
| B-02 | ¿Podés dejar la PC encendida sin suspender durante 2–4 h? | Builds largos | Sí; ajustar energía | F1 |
| B-03 | ¿Hay espacio para liberar en `E:` si hace falta? | Imagen 120 GiB | Sí, 152 GB libres | F0 |
| B-04 | ¿Querés versionar los reportes de verificación? | Trazabilidad | Sí, en `reports/` (sin secretos) | F6 |
| B-05 | ¿Aceptás QEMU sin GPU real para el MVP y validar GPU en hardware? | Hyprland/Ollama | Sí, con limitaciones documentadas | F2/F4 |

## Respuestas sugeridas para arrancar ya

Si no hay respuesta en 24 h, se usan estos defaults y se registran en el commit:

```text
H-01 desktop: Ryzen 7 5700X / GPU a confirmar
H-02 asumir v3 y verificar
H-03 instalar AMD+Intel+NVIDIA open, env dinámico
S-01 MVP sin cifrado (riesgo aceptado)
S-02 autologin sí
S-03 SSH con clave, UFW allow 22
S-04 davos / America/Argentina/Buenos_Aires
S-05 la-latin1
S-06 es_AR.UTF-8
O-01 overlay (gate)
O-03 SDDM
D-01 modelos ≤7B
D-02 /home
B-01 Windows + WHPX
```
