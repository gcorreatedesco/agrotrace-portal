#!/usr/bin/env python3
"""Sanity check de los archivos HTML de la app AgroTrace.

Detecta errores gruesos antes de publicar: JS que no parsea, CSS con
llaves desbalanceadas, IDs duplicados y handlers que llaman a funciones
inexistentes. No valida lógica de negocio.

Uso: python3 ci/sanity_check.py
Sale con código 1 si encuentra algún problema.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Archivos activos de la app (los AgroTrace_*.html son documentación renderizada)
APP_FILES = [
    "index.html",
    "agrotrace_prototipo_v3.html",
    "portal_rt.html",
]

# Funciones globales del navegador, SDKs de CDN y palabras clave de JS
# que pueden abrir un handler inline (onclick="if(...)...")
KNOWN_GLOBALS = {
    "alert", "confirm", "prompt", "supabase",
    "if", "for", "while", "switch", "return",
}

errors = []


def err(f, msg):
    errors.append(f"{f}: {msg}")


def check_file(name):
    path = ROOT / name
    if not path.exists():
        err(name, "el archivo no existe")
        return
    src = path.read_text(encoding="utf-8")

    # 1. JS: cada bloque <script> debe parsear (node --check)
    scripts = re.findall(r"<script>(.*?)</script>", src, re.S)
    if not scripts:
        err(name, "no tiene ningún bloque <script> inline")
    for i, code in enumerate(scripts, 1):
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as tmp:
            tmp.write(code)
            tmp_path = tmp.name
        r = subprocess.run(["node", "--check", tmp_path],
                           capture_output=True, text=True)
        if r.returncode != 0:
            detail = next((l for l in r.stderr.splitlines() if "Error" in l),
                          "error de sintaxis")
            err(name, f"bloque <script> #{i} no parsea: {detail.strip()}")

    # 2. CSS: llaves balanceadas en cada bloque <style>
    for i, css in enumerate(re.findall(r"<style>(.*?)</style>", src, re.S), 1):
        if css.count("{") != css.count("}"):
            err(name, f"bloque <style> #{i} con llaves desbalanceadas "
                      f"({{={css.count('{')} }}={css.count('}')})")

    # 3. IDs duplicados (rompen getElementById silenciosamente).
    # Solo en el HTML estático: los ids dentro de templates JS pueden
    # repetirse legítimamente si nunca coexisten en el DOM.
    static_html = re.sub(r"<script>.*?</script>", "", src, flags=re.S)
    ids = re.findall(r'\bid="([\w-]+)"', static_html)
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        err(name, f'id duplicado: "{dup}" ({ids.count(dup)} veces)')

    # 4. Handlers inline que llaman a funciones no definidas en el archivo
    defined = set(re.findall(r"function\s+(\w+)", src))
    defined |= set(re.findall(r"(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?(?:function|\()", src))
    called = set(re.findall(r'\bon\w+="\s*(\w+)\s*\(', src))
    called |= set(re.findall(r"\bon\w+='\s*(\w+)\s*\(", src))
    for fn in sorted(called - defined - KNOWN_GLOBALS):
        err(name, f"handler llama a función inexistente: {fn}()")

    # 5. Básicos de estructura
    if '<meta name="viewport"' not in src:
        err(name, "falta la meta viewport (rompe la versión móvil)")
    if src.count("<body") != src.count("</body>"):
        err(name, "tag <body> sin cerrar")

    # 6. Navegación interna: cada sv('x') debe tener su <div id="view-x">,
    # y cada showView('x') su <div id="x"> (un botón que navega a una
    # vista inexistente no da error de sintaxis pero rompe la app)
    for v in sorted(set(re.findall(r"\bsv\('([\w-]+)'\)", src))):
        if f'id="view-{v}"' not in src:
            err(name, f"sv('{v}') navega a una vista inexistente (falta id=\"view-{v}\")")
    for v in sorted(set(re.findall(r"\bshowView\('([\w-]+)'", src))):
        if f'id="{v}"' not in src:
            err(name, f"showView('{v}') navega a una vista inexistente (falta id=\"{v}\")")


def check_supabase_tables():
    """Cada sb.from('tabla') del código debe existir en supabase_schema.sql.

    Un typo en un nombre de tabla parsea perfecto y explota recién en
    producción; este cruce lo atrapa en el CI.
    """
    schema_path = ROOT / "supabase_schema.sql"
    if not schema_path.exists():
        err("supabase_schema.sql", "el archivo no existe")
        return
    schema = schema_path.read_text(encoding="utf-8")
    tables = set(re.findall(
        r"CREATE TABLE (?:IF NOT EXISTS )?(?:public\.)?([a-z_]+)", schema, re.I))
    for name in APP_FILES:
        path = ROOT / name
        if not path.exists():
            continue
        src = path.read_text(encoding="utf-8")
        for t in sorted(set(re.findall(r"\.from\('([a-z_]+)'\)", src))):
            if t not in tables:
                err(name, f"usa la tabla '{t}' que no existe en supabase_schema.sql")


def main():
    for f in APP_FILES:
        check_file(f)
    check_supabase_tables()
    if errors:
        print(f"✗ Sanity check falló ({len(errors)} problema/s):\n")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print(f"✓ Sanity check OK — {len(APP_FILES)} archivos verificados")


if __name__ == "__main__":
    main()
