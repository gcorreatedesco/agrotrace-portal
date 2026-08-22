# Guía: Merge seguro entre branches dev y main

## Contexto

AgroTrace tiene dos entornos separados:

| Branch | Supabase | Uso |
|--------|----------|-----|
| `main` | PROD (`jqkyifuyaxxwugrnjfnq`) | Usuarios reales |
| `dev`  | DEV  (`aitodoqcsawntgznwtvj`) | Pruebas y desarrollo |

Las credenciales de conexión a Supabase (URL + clave anon) están hardcodeadas en 4 archivos HTML:

- `index.html`
- `agrotrace_prototipo_v3.html`
- `portal_rt.html`
- `portal_superadmin.html`

**El problema:** si se hace un `git merge` directo entre branches, git mezcla el contenido de los archivos y las credenciales del entorno equivocado pisan las correctas. Por ejemplo, mergear `dev` en `main` sin cuidado dejaría la URL de DEV en producción — los usuarios reales se conectarían a la base de datos de pruebas.

---

## Solución: script `ci/merge.py`

El script fue creado para resolver este problema de forma automática. Lo que hace internamente:

1. Cambia al branch destino
2. **Guarda las credenciales del destino** leyendo los archivos desde git (sin tocar el disco)
3. Ejecuta `git merge --no-commit --no-ff` desde el branch origen
4. **Restaura las credenciales guardadas**, pisando cualquier URL incorrecta que haya traído el merge
5. Commitea y pushea

De esta forma el merge siempre termina con las credenciales correctas para el entorno destino, sin intervención manual.

---

## Por qué se agregó el check en el CI (`sanity_check.py`)

El CI (GitHub Actions) corre `ci/sanity_check.py` en cada push. Se le agregó la función `check_supabase_credentials()` como segunda línea de defensa:

- En un push a `main`: verifica que todos los HTML tengan la URL de PROD. Si encuentra la URL de DEV → falla y manda email de alerta.
- En un push a `dev`: verifica que todos los HTML tengan la URL de DEV. Si encuentra la URL de PROD → falla y manda email de alerta.

Esto atrapa el caso en que alguien haga un merge manual sin usar el script.

---

## Cómo ejecutar un merge correctamente

### Deploy: pasar cambios de dev a producción (`dev → main`)

```bash
python ci/merge.py main
```

El script:
- Cambia a `main`
- Mergea `dev` en `main`
- Restaura credenciales de PROD en los 4 HTML
- Commitea con mensaje `deploy: merge dev -> main [credenciales MAIN restauradas]`
- Pushea a `origin/main`

### Sync: traer cambios de main a dev (`main → dev`)

Útil cuando se hacen cambios directamente en `main` (ej: actualización del README) que deben reflejarse en `dev`.

```bash
python ci/merge.py dev
```

El script:
- Cambia a `dev`
- Mergea `main` en `dev`
- Restaura credenciales de DEV en los 4 HTML
- Commitea con mensaje `sync: merge main -> dev [credenciales DEV restauradas]`
- Pushea a `origin/dev`

---

## Qué hacer si hay conflictos

El script distingue dos tipos de conflicto:

**Conflictos en archivos de credenciales** (los 4 HTML): los resuelve automáticamente restaurando las credenciales del branch destino.

**Conflictos en archivos de código** (cualquier otro archivo): el script aborta el merge y muestra cuáles archivos tienen conflictos. En ese caso hay que resolverlos manualmente:

```bash
# 1. Resolver los conflictos en el editor (buscar marcadores <<<<<<< / ======= / >>>>>>>)
# 2. Marcar como resueltos
git add <archivo-con-conflicto>
# 3. Completar el merge
git commit
# 4. Corregir credenciales manualmente (find & replace en VS Code)
#    PROD URL: jqkyifuyaxxwugrnjfnq.supabase.co
#    DEV  URL: aitodoqcsawntgznwtvj.supabase.co
git add index.html agrotrace_prototipo_v3.html portal_rt.html portal_superadmin.html
git commit --amend --no-edit
git push origin <branch>
```

---

## Regla general

> **Nunca usar `git merge` directo entre `dev` y `main`. Siempre usar `python ci/merge.py`.**

El CI actúa como red de seguridad: si por error se hace un push con credenciales incorrectas, GitHub Actions lo detecta y manda un email de alerta.

---

## Solución definitiva (futuro)

Al migrar a React + Vite, las credenciales se moverán a un archivo `.env` que no entra en git (`.gitignore`). Cada entorno tendrá su propio `.env` local y el problema desaparece por completo — los merges nunca tocarán credenciales.
