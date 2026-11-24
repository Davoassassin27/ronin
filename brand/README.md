# Ronin + Kensei — sistema de marca

Dos marcas, un mismo ADN: **perfil de ronin, kasa y trigo**.

| Marca | Marca oficial | Uso |
| --- | --- | --- |
| **Ronin** | A · Kasa + C · Mon oscuro | OS portable CachyOS + Omarchy |
| **Kensei** | B · Mon rojo | CLI / SLM de terminal de Ronin |

La familia se lee como un sistema: Ronin es el continente (tinta, hueso, oro); Kensei es la herramienta (bermellón, oro, tinta).

## Mapa de carpetas

```
brand/
  brand-family.png          ← lámina de familia
  ronin/
    logo/                   ← SVG maestros y variantes
    icons/                  ← app icon, favicon, web icons
    png/                    ← exports 1024 px
    README.md               ← guía de marca
  README.md                 ← este archivo
kensei/
  brand/
    logo/
    icons/
    png/
    README.md
```

Los archivos de exploración quedan en `build/brand/` y **no** son oficiales.

## Reglas de familia

- **Ronin** usa tinta (`#111111`), oro (`#E6C384`) y hueso (`#F2EFE7`). El mon oficial es el de disco casi negro (`#141414`).
- **Kensei** usa bermellón (`#A63A2F`) y oro (`#E6C384`) sobre tinta. El mon rojo es exclusivo de Kensei.
- No intercambiar los mones: el rojo no representa a Ronin y el oscuro no representa a Kensei, salvo una pieza de co-branding explícita.
- El perfil, la kasa y el trigo no se redibujan ni se les agregan elementos. La diferencia entre marcas es color, contenedor y aplicación.
- Kensei hereda el perfil de Ronin: es una sub-marca, no una marca independiente.

## Origen del dibujo

El perfil está basado en una silueta de **dominio público (CC0)** del Met Museum, adaptada con kasa, trigo y el busto. La imagen de referencia que pasaste se usó solo como dirección de aura; el vector es una construcción nueva.

Fuente: [Silhouette of a man in profile to the right — The Met, CC0](https://commons.wikimedia.org/wiki/File:Silhouette_of_a_man_in_profile_to_the_right_Met_DP887354.jpg).

## SVG para motion

Todos los SVG maestros tienen grupos con `id` para animar en Framer Motion o CSS:

`mark`, `disc`, `face`, `hat`, `wheat`, `grain`, `awn`, `band`, `eye`, `collar`.

Ejemplo: animar `#wheat` con una rotación leve, `#eye` con un parpadeo de opacidad, `#hat` con una entrada desde arriba. No animar el `disc` y el `mark` a la vez en sentidos opuestos: se descentra el sello.

## Reproducir

- Maestros y variantes: `python brand/tools/build_brand.py` (lee los SVG base de `brand/sources/`; si `kensei/` está clonado, también genera su marca).
- Lámina de familia: `python brand/tools/make_family.py`.
- Los exports de iconos se generaron con `export_variants.py` del skill de logo design.

## Licencia

Los assets oficiales de `brand/` se publican bajo **CC BY 4.0**. Atribución: "Ronin — https://github.com/Davoassassin27/ronin". Las exploraciones de `build/brand/` no son oficiales y no se publican. Ver [`LICENSE-DOCS`](../LICENSE-DOCS) y [`NOTICE`](../NOTICE).

## Lo que falta (siguiente paso)

- Wordmark oficial de Ronin y de Kensei (hoy se recomienda tipografía, no hay lockup cerrado).
- Lockup horizontal/vertical mon + nombre.
- Prueba de impresión/embroidery: expandir los trazos de trigo, banda y cuello a contornos.
