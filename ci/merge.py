#!/usr/bin/env python3
"""
Merge seguro entre branches con corrección automática de credenciales Supabase.

El script guarda las credenciales del branch DESTINO antes del merge y las
restaura después, evitando que un merge accidental pise el entorno equivocado.

Uso:
  python ci/merge.py main   # deploy:  dev -> main  (credenciales de PROD)
  python ci/merge.py dev    # sync:    main -> dev  (credenciales de DEV)
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CRED_FILES = [
    'index.html',
    'agrotrace_prototipo_v3.html',
    'portal_rt.html',
    'portal_superadmin.html',
]

# Detecta URLs de Supabase y claves anon (formato JWT o nuevo sb_publishable_*)
URL_RE = re.compile(r'https://\w+\.supabase\.co')
KEY_RE = re.compile(r'(?:eyJ[A-Za-z0-9._\-]+|sb_publishable_[A-Za-z0-9._\-]+)')


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', cwd=ROOT)


def die(msg):
    print(f'\nERROR: {msg}')
    sys.exit(1)


def current_branch():
    return run(['git', 'rev-parse', '--abbrev-ref', 'HEAD']).stdout.strip()


def save_creds(branch):
    """Lee las credenciales de cada archivo en el branch dado (sin tocar el disco)."""
    creds = {}
    for name in CRED_FILES:
        r = run(['git', 'show', f'{branch}:{name}'])
        if r.returncode != 0:
            continue
        content = r.stdout
        urls = URL_RE.findall(content)
        keys = KEY_RE.findall(content)
        creds[name] = {
            'url': urls[0] if urls else None,
            'key': keys[0] if keys else None,
        }
    return creds


def apply_creds(creds):
    """Reemplaza todas las URLs y claves Supabase en los archivos locales."""
    for name, vals in creds.items():
        path = ROOT / name
        if not path.exists():
            continue
        content = path.read_text(encoding='utf-8')
        if vals['url']:
            content = URL_RE.sub(vals['url'], content)
        if vals['key']:
            content = KEY_RE.sub(vals['key'], content)
        path.write_text(content, encoding='utf-8')
        print(f'  {name} -> {vals["url"]}')


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ('main', 'dev'):
        print('Uso:')
        print('  python ci/merge.py main   # deploy dev -> main (PROD)')
        print('  python ci/merge.py dev    # sync  main -> dev  (DEV)')
        sys.exit(1)

    target = sys.argv[1]
    source = 'dev' if target == 'main' else 'main'
    label  = 'deploy' if target == 'main' else 'sync'
    origin = current_branch()

    # Cambiar al branch destino si hace falta
    if origin != target:
        r = run(['git', 'checkout', target])
        if r.returncode != 0:
            die(f'No se pudo cambiar a \'{target}\':\n{r.stderr}')
        print(f"Cambiado a branch '{target}'")

    # Verificar que no hay cambios sin commitear
    if run(['git', 'status', '--porcelain']).stdout.strip():
        die(f"Hay cambios sin commitear en '{target}'. Hacé commit o stash primero.")

    # Guardar credenciales del branch DESTINO antes del merge
    print(f"\nGuardando credenciales de '{target}'...")
    creds = save_creds(target)
    for name, vals in creds.items():
        if vals['url']:
            print(f'  {name}: {vals["url"]}')

    # Merge sin commit automático
    print(f"\nMergeando '{source}' -> '{target}'...")
    r = run(['git', 'merge', source, '--no-commit', '--no-ff'])

    if 'Already up to date' in r.stdout:
        print('Ya está al día, nada que mergear.')
        sys.exit(0)

    # Detectar conflictos por git status (UU = ambos modificaron, AA/DD = otros)
    status = run(['git', 'status', '--porcelain']).stdout
    conflicts = [
        line[3:].strip()
        for line in status.splitlines()
        if line[:2] in ('UU', 'AA', 'DD', 'AU', 'UA')
    ]
    non_cred = [f for f in conflicts if f not in CRED_FILES]

    if non_cred:
        run(['git', 'merge', '--abort'])
        die('Conflictos en archivos de código — resolvé manualmente:\n  ' +
            '\n  '.join(non_cred))

    if r.returncode != 0 and not conflicts:
        run(['git', 'merge', '--abort'])
        die(f'Merge falló por razón desconocida:\n{r.stdout}\n{r.stderr}')

    # Restaurar credenciales correctas (resuelve también conflictos en cred files)
    print(f"\nRestaurando credenciales de '{target}'...")
    apply_creds(creds)

    # Stagear archivos de credenciales
    run(['git', 'add'] + CRED_FILES)

    # Commit
    msg = f'{label}: merge {source} -> {target} [credenciales {target.upper()} restauradas]'
    r = run(['git', 'commit', '-m', msg])
    if r.returncode != 0:
        print('Sin cambios para commitear.')
        sys.exit(0)
    print(f'\nCommit: {r.stdout.strip()}')

    # Push
    print(f"\nPusheando '{target}'...")
    r = run(['git', 'push', 'origin', target])
    if r.returncode != 0:
        die(f'Push falló:\n{r.stderr}')

    print(f'\nOK: {source} -> {target} completado correctamente')

    # Volver al branch original
    if origin != target:
        run(['git', 'checkout', origin])
        print(f"Vuelto a branch '{origin}'")


if __name__ == '__main__':
    main()
