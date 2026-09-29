#!/usr/bin/env bash
#
# Deja tu instancia lista para la parte 2, desde cero.
#
#   bash setup/bootstrap.sh
#
# Una instancia recien creada no trae nada: ni Python, ni Node, ni Ollama. Este
# script instala las cinco capas y COMPRUEBA cada una antes de seguir:
#
#   1. paquetes del sistema   python3, venv, git, curl, lsof
#   2. entorno virtual        .venv/ dentro del proyecto
#   3. dependencias Python    Flask, CORS, requests
#   4. Node y el frontend     Node 24 (LTS) via nvm, y npm ci
#   5. Ollama y el modelo     el servidor y ~1 GB de pesos
#
# Se puede correr las veces que haga falta: comprueba antes de instalar, y lo
# que ya este no se vuelve a bajar.

set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELO="${OLLAMA_MODEL:-qwen2.5:1.5b}"
VENV="$AQUI/.venv"

VERDE="\033[32m"; ROJO="\033[31m"; AMARILLO="\033[33m"; RESET="\033[0m"
paso()  { echo; echo "==> $1"; }
ok()    { echo -e "    ${VERDE}OK${RESET}  $1"; }
aviso() { echo -e "    ${AMARILLO}!${RESET}   $1"; }
morir() { echo -e "    ${ROJO}FALLA${RESET} $1" >&2; exit 1; }

# Esto es para la instancia (Ubuntu). En una Mac o en Git Bash fallaria en la
# primera linea --apt-get no existe, sudo pide contraseña-- con un mensaje que
# no explica nada. Mejor decirlo antes de tocar nada.
if [[ "$(uname -s)" != "Linux" ]]; then
  cat <<'FIN' >&2
Este script es para tu INSTANCIA (Ubuntu), no para tu computadora.

Por ahora tu maquina edita y hace git; la instancia ejecuta.

  En tu computadora:  git add -A && git commit -m "..." && git push
  En la instancia:    git pull && ./run restart

Al final del modulo vas a tener que hacer correr esto en tu propia maquina.
Ese es un EJERCICIO, y a proposito no hay un script que lo haga por ti: para
entonces vas a saber que necesita el producto y podras averiguar como
instalarlo en tu sistema.

Si estas en la instancia y ves esto, algo raro pasa: deberia decir Linux.
FIN
  exit 1
fi


# ---------------------------------------------------------------------------
paso "0 · Espacio en disco"
# ---------------------------------------------------------------------------
#
# Ollama pesa ~1.5 GB y el modelo otro 1 GB. El disco por defecto de una
# instancia nueva son 8 GB, y se llena. Mejor decirlo ahora que a mitad de la
# descarga, cuando el error habla de "no space left on device" y ya perdiste
# diez minutos.
# Si por lo que sea no se puede medir, se sigue: un chequeo que reviente el
# bootstrap seria peor que no tenerlo.
LIBRE_GB="$(df -BG --output=avail "$AQUI" 2>/dev/null | tail -1 | tr -dc '0-9' || true)"
if [[ -z "$LIBRE_GB" ]]; then
  aviso "no pude medir el disco; sigo de todas formas"
elif (( LIBRE_GB < 5 )); then
  morir "quedan ${LIBRE_GB} GB libres y hacen falta al menos 5.
        Ollama pesa ~1.5 GB y el modelo otro 1 GB.
        Amplia el volumen desde la consola de AWS
        (EC2 > Volumes > Modify volume) y vuelve a correr esto."
else
  ok "${LIBRE_GB} GB libres"
fi


# ---------------------------------------------------------------------------
paso "1 · Paquetes del sistema"
# ---------------------------------------------------------------------------
#
# python3-venv va aparte de python3 en Ubuntu, y sin el 'python3 -m venv' falla
# con un mensaje que sugiere instalarlo... usando el propio venv que no existe.
#
# python3-pip NO esta en la lista, y es deliberado: arrastra gcc, g++,
# build-essential y unos noventa paquetes mas que aqui no se usan. El entorno
# virtual trae su propio pip (via ensurepip, que viene con python3-venv), asi
# que el pip del sistema sobra. Si por lo que sea faltara, el paso 2 lo detecta
# y lo instala entonces.
sudo apt-get update -qq
sudo apt-get install -y -qq \
  git python3 python3-venv curl ca-certificates lsof

command -v python3 >/dev/null || morir "python3 no quedo instalado"
ok "python $(python3 --version 2>&1 | cut -d' ' -f2)"


# ---------------------------------------------------------------------------
paso "2 · Entorno virtual"
# ---------------------------------------------------------------------------
#
# Ubuntu 24.04 protege el Python del sistema (PEP 668): un 'pip install' fuera
# de un entorno virtual se niega con "externally-managed-environment". No es un
# estorbo, es correcto: las dependencias de tu proyecto no deben mezclarse con
# las del sistema operativo.
#
# Por eso TODO lo que instalamos va dentro de .venv/, y por eso ./run llama a
# .venv/bin/python directamente en vez de pedirte que actives nada.
if [[ -x "$VENV/bin/python" ]]; then
  ok "ya existia en .venv/"
else
  python3 -m venv "$VENV" || morir "no se pudo crear el entorno.
        ¿Quedo instalado python3-venv?  sudo apt-get install -y python3-venv"
  ok "creado en .venv/"
fi

# Red de seguridad: si el entorno quedo sin pip --no deberia, ensurepip viene
# con python3-venv-- se instala el del sistema y se rehace.
if [[ ! -x "$VENV/bin/pip" ]]; then
  aviso "el entorno quedo sin pip; instalando python3-pip y rehaciendolo"
  sudo apt-get install -y -qq python3-pip
  rm -rf "$VENV"
  python3 -m venv "$VENV" || morir "no se pudo crear el entorno ni con python3-pip"
fi

"$VENV/bin/python" -m pip install -q --upgrade pip
ok "pip $("$VENV/bin/pip" --version | cut -d' ' -f2)"


# ---------------------------------------------------------------------------
paso "3 · Dependencias del backend"
# ---------------------------------------------------------------------------
"$VENV/bin/pip" install -q -r "$AQUI/backend/requirements.txt"

# Comprobar que se pueden importar, no solo que pip dijo que si.
"$VENV/bin/python" - <<'PY' || morir "las dependencias no se pueden importar"
import flask, flask_cors, requests
print(f"    OK  Flask {flask.__version__} · requests {requests.__version__}")
PY


# ---------------------------------------------------------------------------
paso "4 · Node para el frontend"
# ---------------------------------------------------------------------------
#
# QUE VERSION, Y POR QUE ESA.
#
# Node publica una version nueva cada seis meses. Las pares se vuelven LTS
# --soporte largo-- y las impares mueren en medio año. En cualquier momento
# hay cuatro vivas:
#
#   v26   la mas nueva. Sera LTS en octubre de 2026; hoy todavia no lo es
#   v24   LTS ACTIVA. Es la que se instala aqui
#   v22   en mantenimiento: solo parches de seguridad
#   v20   fin de vida
#
# Se instala la 24 y no la 26 a proposito. "La mas nueva" suena a mejor y en
# herramientas de build suele significar "la que todavia no tiene arreglado lo
# que te va a pasar". La LTS activa lleva meses recibiendo correcciones y es
# contra la que prueban Vite, TypeScript y todo lo demas.
#
# Y se instala con nvm, no con apt: el Node de los repositorios de Ubuntu suele
# ir una o dos versiones por detras, y ademas nvm no necesita sudo. Queda todo
# bajo ~/.nvm, que es tuyo.
NODE_MAYOR=24
NVM_VER="v0.40.8"
export NVM_DIR="$HOME/.nvm"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VER/install.sh" | bash >/dev/null 2>&1 \
    || morir "no se pudo instalar nvm. ¿Hay red?  curl -I https://raw.githubusercontent.com"
fi
# nvm es una funcion de shell, no un programa: hay que cargarla en esta sesion.
# Por eso 'command -v nvm' no encontraria nada aunque este instalado.
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"

if nvm ls "$NODE_MAYOR" >/dev/null 2>&1; then
  ok "Node $NODE_MAYOR ya estaba"
else
  nvm install "$NODE_MAYOR" >/dev/null 2>&1 || morir "no se pudo instalar Node $NODE_MAYOR"
  ok "Node $NODE_MAYOR instalado"
fi
nvm alias default "$NODE_MAYOR" >/dev/null 2>&1
nvm use default >/dev/null 2>&1

command -v node >/dev/null || morir "node no quedo disponible"
ok "node $(node --version) · npm $(npm --version)"

# Una terminal NUEVA no carga nvm sola a menos que este en el perfil. El
# instalador lo añade a ~/.bashrc, pero si el alumno usa otra shell o el
# archivo no existia, mejor comprobarlo que descubrirlo cuando 'npm' no exista.
if ! grep -q "NVM_DIR" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'FIN'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
FIN
  aviso "añadi nvm a ~/.bashrc; en terminales nuevas ya estara"
fi

# Las dependencias del frontend. 'npm ci' y no 'npm install' porque instala
# EXACTAMENTE las versiones del package-lock.json: las mismas que probe yo y
# las mismas en las treinta instancias del grupo. 'install' puede subir una
# version menor por su cuenta, y entonces un fallo le pasa a una persona y a
# nadie mas -- que es la clase de fallo peor.
if [[ -f "$AQUI/frontend/package.json" ]]; then
  if [[ -d "$AQUI/frontend/node_modules" ]]; then
    ok "las dependencias del frontend ya estaban"
  else
    echo "    instalando las dependencias del frontend"
    ( cd "$AQUI/frontend" && npm ci --silent ) \
      || morir "npm ci fallo en frontend/. Mira el error de arriba."
    ok "frontend listo"
  fi
else
  aviso "todavia no hay frontend/ (llega en la fase 2)"
fi


# ---------------------------------------------------------------------------
paso "5 · Ollama"
# ---------------------------------------------------------------------------
if command -v ollama >/dev/null 2>&1; then
  ok "ya estaba instalado"
else
  curl -fsSL https://ollama.com/install.sh | sh
  command -v ollama >/dev/null || morir "la instalacion de Ollama no dejo el comando"
  ok "instalado"
fi

# El instalador deja un servicio de systemd. Si no arranco solo, lo levantamos.
if curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
  ok "el servidor responde en el 11434"
else
  sudo systemctl enable --now ollama 2>/dev/null || (nohup ollama serve >/dev/null 2>&1 &)
  for _ in $(seq 1 12); do
    sleep 2
    curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1 && break
  done
  curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1 \
    || morir "Ollama no respondio. Prueba a mano:  ollama serve"
  ok "servidor arrancado"
fi


# ---------------------------------------------------------------------------
paso "6 · El modelo"
# ---------------------------------------------------------------------------
if curl -s --max-time 5 http://localhost:11434/api/tags | grep -q "\"$MODELO\""; then
  ok "$MODELO ya estaba descargado"
else
  echo "    bajando $MODELO (~1 GB, tarda unos minutos)"
  ollama pull "$MODELO" || morir "no se pudo descargar $MODELO"
  ok "descargado"
fi


# ---------------------------------------------------------------------------
paso "Comprobacion final"
# ---------------------------------------------------------------------------
fallos=0
[[ -x "$VENV/bin/python" ]] && ok "entorno virtual" || { aviso "falta .venv"; fallos=1; }
"$VENV/bin/python" -c "import flask, requests" 2>/dev/null \
  && ok "dependencias" || { aviso "faltan dependencias"; fallos=1; }
command -v node >/dev/null 2>&1 \
  && ok "node $(node --version)" || { aviso "falta Node"; fallos=1; }
if [[ -f "$AQUI/frontend/package.json" ]]; then
  [[ -d "$AQUI/frontend/node_modules" ]] \
    && ok "dependencias del frontend" || { aviso "falta npm ci en frontend/"; fallos=1; }
fi
curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1 \
  && ok "Ollama responde" || { aviso "Ollama no responde"; fallos=1; }
curl -s --max-time 5 http://localhost:11434/api/tags | grep -q "\"$MODELO\"" \
  && ok "$MODELO disponible" || { aviso "falta el modelo"; fallos=1; }

echo
if (( fallos )); then
  echo -e "${ROJO}Algo quedo a medias.${RESET} Vuelve a correr este script."
  exit 1
fi
echo -e "${VERDE}Instancia lista.${RESET} Ahora:"
echo
echo "    ./run start"
echo "    ./run salud"
