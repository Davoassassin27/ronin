# Ronin — marca oficial

**Ronin** es el OS portable (CachyOS + Omarchy). La marca oficial combina dos piezas:

- **A · Kasa** — la silueta de perfil. Marca principal para fondos claros y piezas grandes.
- **C · Mon oscuro** — el sello de disco casi negro con perfil en oro. Marca principal para iconos, barra y fondos oscuros.

## Archivos

### `logo/`

| Archivo | Fondo | Uso |
| --- | --- | --- |
| `ronin-kasa.svg` | Claro | Kasa en tinta, detalles en blanco (marca principal) |
| `ronin-kasa-gold.svg` | Oscuro | Kasa en oro, detalles en tinta |
| `ronin-kasa-white.svg` | Oscuro | Kasa en blanco, detalles en tinta |
| `ronin-mon-dark.svg` | Oscuro | **Mon oficial**: disco `#141414`, perfil oro |
| `ronin-mon-mono.svg` | Claro / una tinta | Disco tinta, perfil blanco |
| `ronin-mon-light.svg` | Claro | Disco hueso, perfil tinta |

`_source-*.svg` son los archivos de trazabilidad; no usar en producción.

### `icons/`

- `ronin-app-icon.svg` — icono de app (tile redondeado con el mon).
- `ronin-favicon.svg` / `favicon.svg` — favicon vectorial.
- `favicon.ico`, `favicon-16.png`, `favicon-32.png`, `favicon-48.png`.
- `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `maskable-512.png`.
- `site.webmanifest`, `head-snippet.html`.

### `png/`

Exports a 1024 px de los SVG principales, fondo transparente.

## Paleta

| Token | Hex | Uso |
| --- | --- | --- |
| Ink | `#111111` | Kasa, texto, detalles |
| Near-black | `#141414` | Disco del mon |
| Gold | `#E6C384` | Perfil en oscuro, acento del tema |
| Bone | `#F2EFE7` | Fondo claro, disco claro |
| White | `#FFFFFF` | Reversed / una tinta |

El oro sobre `#141414` tiene buen contraste para gráfica; no usarlo para texto pequeño.

## Uso

- **Fondo claro:** `ronin-kasa.svg` o `ronin-mon-light.svg`.
- **Fondo oscuro:** `ronin-kasa-gold.svg`, `ronin-kasa-white.svg` o `ronin-mon-dark.svg`.
- **Barra / app / favicon:** `ronin-mon-dark.svg` (o `icons/ronin-app-icon.svg`).
- **Una tinta / impresión:** `ronin-mon-mono.svg`.
- **Motion / detalle:** `ronin-kasa-gold.svg` o `ronin-kasa-white.svg`; el perfil y el trigo están separados por `id`.

### Tamaños mínimos

- Mon: **24 px** digital, **10 mm** impresión.
- Kasa: **48 px** digital, **18 mm** impresión.
- Favicon: usar `favicon.svg`/`.ico`; a 16 px el mon se simplifica a disco + kasa.

### Espacio libre

Dejar al menos **1/4 de la altura del mon** (o 1/4 de la altura de la kasa) libre alrededor. No poner texto ni bordes dentro de ese margen.

## SVG y motion

IDs disponibles en los maestros:

`mark`, `disc`, `face`, `hat`, `wheat`, `grain`, `awn`, `band`, `eye`, `collar`.

Sugerencias:

- `hat` entra desde arriba con `y: -12 → 0`.
- `wheat` oscila ±2° con `transform-origin` en la boca.
- `eye` parpadea con opacidad `1 → 0 → 1` en 120 ms.
- No animar `disc` y `mark` en sentidos opuestos.

Los trazos de `wheat`, `band`, `collar` y `awn` están como stroke. Para print/embroidery, expandirlos a contornos antes de producir.

## Tipografía recomendada

- Display: **Cormorant Garamond** o **Cinzel** (serif, para “RONIN”).
- UI / docs: **IBM Plex Mono** o **IBM Plex Sans**.
- No están incluidas; son recomendaciones, no un lockup cerrado.

## Origen

Perfil basado en una silueta de **dominio público (CC0)** del Met Museum, adaptada con kasa, trigo y busto. La referencia visual del usuario no se copió: se usó como dirección de aura.

Fuente: [The Met — Silhouette of a man in profile to the right (CC0)](https://commons.wikimedia.org/wiki/File:Silhouette_of_a_man_in_profile_to_the_right_Met_DP887354.jpg).

## Pendiente

- Wordmark/lockup oficial “RONIN”.
- Expandir strokes para impresión.
- Probar el favicon a 16 px en la barra de Omarchy.
