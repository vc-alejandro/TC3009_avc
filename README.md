# TC3009 · Parte 2

Segunda mitad de la concentración. La parte 1 llevó un modelo entrenado por ti hasta un
producto usable. Esta parte va de lo que pasa después: modelos que no entrenaste, que corren
en tu propia máquina, y que responden con texto en vez de números.

---

## Cómo se trabaja aquí

**No hay fork.** Bajas este contenido una vez, creas **tu** repositorio, y a partir de ahí es
tuyo. La instancia clona el tuyo, no el mío.

```
   Repo del curso            Tu repositorio             Tu instancia
   ──────────────            ──────────────             ────────────
   lo bajas una vez  ──▶  escribes en VS Code  ──push──▶  lo clonas
   (guías y esqueleto)         y haces push              y lo pruebas
```

Todo eso está en **[docs/00-setup.md](docs/00-setup.md)** — quince minutos, una sola vez.

---

## Lo que hay ahora

| | |
|---|---|
| **[docs/guia.md](docs/guia.md)** | La práctica: un producto con un modelo de lenguaje propio |
| `backend/` | Flask. Tres `COMPLETA` que llenas tú |
| `frontend/` | React + TypeScript con Vite. Dos `COMPLETA` más |
| `setup/bootstrap.sh` | Deja la instancia lista: Python, Node, Ollama y el modelo |
| `run` | `start` · `stop` · `status` · `logs` · `salud` · `modelo` |

**El modelo por defecto es `qwen2.5:1.5b`**, y se cambia en una línea de `backend/app.py`:

```python
MODELO = os.environ.get("OLLAMA_MODEL", "qwen2.5:1.5b")
```

Bájalo primero (`ollama pull <modelo>`) y reinicia. Para probar uno sin tocar código:
`OLLAMA_MODEL=llama3.2:3b ./run restart`. La guía explica cuáles caben en una t2.large.

```
   Fase 1   un backend en Flask que habla con Ollama          ~60 min
   Fase 2a  un frontend en React que habla con el backend     ~45 min
   Fase 2b  la respuesta aparece escribiéndose, no de golpe   ~30 min
```

---

## Arranque rápido

**En tu computadora**, una vez leído [docs/00-setup.md](docs/00-setup.md):

```bash
git add -A && git commit -m "..." && git push
```

**En la instancia:**

```bash
git pull && ./run restart && ./run salud
```

---

## Los puertos

```
   :8080    el backend        abierto en tu security group desde la parte 1
   :3000    el chat (fase 2)  abierto también
   :11434   Ollama            NO se abre, y es una decisión
```

Si el 11434 estuviera abierto, cualquiera podría preguntarle al modelo saltándose tu API — sin
tu validación, sin tu tope de tokens, sin tu registro. **Tu backend es la única puerta.**

Es la misma razón por la que, el día que uses una API de pago, la clave vive en el servidor y
no en el navegador.

---

## Dos reglas

**`git push` al terminar de trabajar.** Tu instancia es desechable; tu repositorio no.

**Detén la instancia al terminar, nunca la termines.** El laboratorio la reinicia sola con una
IP nueva — por eso nada en el código apunta a una dirección fija.
