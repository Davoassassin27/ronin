"""Genera los SVG maestros de Ronin y, si está clonado, de Kensei.

Uso, desde la raíz del repositorio:

    python brand/tools/build_brand.py

Los trazados base viven en brand/sources/. El script no depende de
build/brand/ (exploraciones internas que no se publican).
"""
from pathlib import Path
import shutil

ROOT = Path('.')
BRAND = ROOT / 'brand'
SOURCES = BRAND / 'sources'
RONIN = BRAND / 'ronin'
KENSEI = ROOT / 'kensei' / 'brand'


def write_svg(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


def add_meta(svg, label, title, desc):
    svg = svg.replace('aria-label="Ronin mon"', f'aria-label="{label}"')
    svg = svg.replace('aria-label="Ronin"', f'aria-label="{label}"')
    head_end = svg.index('>') + 1
    return svg[:head_end] + f'\n  <title>{title}</title>\n  <desc>{desc}</desc>' + svg[head_end:]


def add_ids(svg, profile, detail):
    svg = svg.replace('<circle cx="128"', '<circle id="disc" cx="128"', 1)
    svg = svg.replace(f'<path fill="{profile}" d="M174.9', f'<path id="face" fill="{profile}" d="M174.9', 1)
    svg = svg.replace(f'<path fill="{profile}" d="M16 100', f'<path id="hat" fill="{profile}" d="M16 100', 1)
    svg = svg.replace(f'<path fill="{profile}" d="M20 98', f'<path id="hat" fill="{profile}" d="M20 98', 1)
    svg = svg.replace('<path d="M180 182', '<path id="wheat" d="M180 182', 1)
    svg = svg.replace(f'<g fill="{profile}">', f'<g id="grain" fill="{profile}">', 1)
    svg = svg.replace('<path d="M239 157', '<path id="awn" d="M239 157', 1)
    svg = svg.replace('<path d="M24 94', f'<path id="band" d="M24 94', 1)
    svg = svg.replace('<path d="M162 140', f'<path id="eye" d="M162 140', 1)
    svg = svg.replace('<path d="M130 205', f'<path id="collar" d="M130 205', 1)
    if '<g transform=' in svg:
        svg = svg.replace('<g transform=', '<g id="mark" transform=', 1)
    else:
        start = svg.index('>') + 1
        end = svg.rindex('</svg>')
        svg = svg[:start] + '\n  <g id="mark">' + svg[start:end] + '\n  </g>\n' + svg[end:]
    return svg


def recolor(svg, pairs):
    for old, new in pairs:
        svg = svg.replace(old, new)
    return svg


def main():
    for p in [RONIN / 'logo', RONIN / 'icons', RONIN / 'png']:
        p.mkdir(parents=True, exist_ok=True)

    base_a = (SOURCES / 'ronin-kasa-master.svg').read_text(encoding='utf-8')
    base_b = (SOURCES / 'kensei-mon-master.svg').read_text(encoding='utf-8')
    base_c = (SOURCES / 'ronin-mon-master.svg').read_text(encoding='utf-8')

    a = add_meta(base_a, 'Ronin — Kasa', 'Ronin — Kasa', 'Perfil de ronin con kasa y espiga de trigo.')
    a = add_ids(a, '#111111', '#ffffff')
    a = a.replace('<g id="mark">', '<g id="mark" transform="translate(-5 0)">', 1)
    b = add_meta(base_b, 'Kensei — Mon', 'Kensei — Mon', 'Mon de Kensei: perfil de ronin, kasa y trigo.')
    b = add_ids(b, '#e6c384', '#a63a2f')
    c = add_meta(base_c, 'Ronin — Mon', 'Ronin — Mon', 'Mon de Ronin: perfil de ronin, kasa y trigo.')
    c = add_ids(c, '#e6c384', '#141414')

    write_svg(RONIN / 'logo/ronin-kasa.svg', a)
    write_svg(RONIN / 'logo/ronin-kasa-gold.svg', recolor(a, [('#111111', '#E6C384'), ('#ffffff', '#111111')]))
    write_svg(RONIN / 'logo/ronin-kasa-white.svg', recolor(a, [('#111111', '#FFFFFF'), ('#ffffff', '#111111')]))
    write_svg(RONIN / 'logo/ronin-mon-dark.svg', c)
    write_svg(RONIN / 'logo/ronin-mon-mono.svg', recolor(c, [('#141414', '#111111'), ('#e6c384', '#FFFFFF')]))
    write_svg(RONIN / 'logo/ronin-mon-light.svg', recolor(c, [('#141414', '#F2EFE7'), ('#e6c384', '#111111')]))

    if KENSEI.is_dir():
        for p in [KENSEI / 'logo', KENSEI / 'icons', KENSEI / 'png']:
            p.mkdir(parents=True, exist_ok=True)
        write_svg(KENSEI / 'logo/kensei-mon.svg', b)
        write_svg(KENSEI / 'logo/kensei-mon-mono.svg', recolor(b, [('#a63a2f', '#111111'), ('#e6c384', '#FFFFFF')]))
        write_svg(KENSEI / 'logo/kensei-mon-light.svg', recolor(b, [('#a63a2f', '#F2EFE7'), ('#e6c384', '#111111')]))
        write_svg(KENSEI / 'logo/kensei-mon-dark.svg', recolor(b, [('#a63a2f', '#141414')]))
        write_svg(KENSEI / 'logo/kensei-profile-gold.svg', recolor(a, [('#111111', '#E6C384'), ('#ffffff', '#A63A2F')]))
        shutil.copy2(SOURCES / 'kensei-mon-master.svg', KENSEI / 'logo/_source-kensei-mon.svg')

    shutil.copy2(SOURCES / 'ronin-kasa-master.svg', RONIN / 'logo/_source-ronin-kasa.svg')
    shutil.copy2(SOURCES / 'ronin-mon-master.svg', RONIN / 'logo/_source-ronin-mon.svg')
    print('ok')


if __name__ == '__main__':
    main()
