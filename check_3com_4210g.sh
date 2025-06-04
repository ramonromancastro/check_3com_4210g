#!/bin/bash

# check_3com_4210g.sh monitoriza switches 3Com 4210G vía Web.
# Copyright (C) 2025  Ramón Román Castro <ramonromancastro@gmail.com>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

#
# Valores por defecto
#

VERSION=0.2
TEMP_WARN=50
TEMP_CRIT=60
LANG=0
TYPE_FILTER=

#
# Funciones
#

print_help() {
  echo "Uso: $0 -H <host> -u <usuario> -p <contraseña> [-w <temp_warn>] [-c <temp_crit>] [-t tipo] [-l <lang>]"
  echo ""
  echo "Opciones:"
  echo "  -H  IP o hostname del switch (requerido)"
  echo "  -u  Usuario de acceso web (requerido)"
  echo "  -p  Contraseña (requerido)"
  echo "  -w  Umbral WARNING temperatura (°C, default: 50)"
  echo "  -c  Umbral CRITICAL temperatura (°C, default: 60)"
  echo "  -t  Tipo de entidad a monitorear: PSU, FAN o TEMP (requerido)"
  echo "  -l  Idioma (default: 0)"
  echo "  -h  Mostrar ayuda"
  exit 3
}

cleanup() {
  if [[ -n "$LOGIN_UID" ]]; then
    curl -s -b "$COOKIE_JAR" "http://$IP_ADDRESS/wcn/logout?uid=$LOGIN_UID" > /dev/null
  fi
  [ -f "$COOKIE_JAR" ] && rm -f "$COOKIE_JAR"
}
trap cleanup EXIT

#
# Lectura de parámetros
#

while getopts ":H:u:p:w:c:t:l:h" opt; do
  case $opt in
    H) IP_ADDRESS="$OPTARG" ;;
    u) USER="$OPTARG" ;;
    p) PASS="$OPTARG" ;;
    w) TEMP_WARN="$OPTARG" ;;
    c) TEMP_CRIT="$OPTARG" ;;
    t) TYPE_FILTER=$(echo "$OPTARG" | tr '[:lower:]' '[:upper:]') ;;
    l) LANG="$OPTARG" ;;
    h) print_help ;;
    *) print_help ;;
  esac
done

[[ -z "$IP_ADDRESS" || -z "$USER" || -z "$PASS" || -z "$TYPE_FILTER" ]] && print_help

COOKIE_JAR=$(mktemp)

#
# Realizar el login y capturar el UID de sesión
#

LOGIN_RESPONSE=$(curl -s -c "$COOKIE_JAR" -X POST "http://$IP_ADDRESS/Web" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "user_name=$USER" \
  --data-urlencode "password=$PASS" \
  --data-urlencode "lang=$LANG")

LOGIN_UID=$(echo "$LOGIN_RESPONSE" | grep -oP '<input[^>]+id=uid[^>]+value="\K[^"]+')
if [ -z "$LOGIN_UID" ]; then
  echo "UNKNOWN - Login fallido o UID no encontrado"
  exit 3
fi

#
# Obtener entidades filtradas por tipo
#

ENTITY_URL="http://$IP_ADDRESS/wcn/panel3/entity.x?uid=$LOGIN_UID&pos=287&cheid=2"
ENTITY_RESPONSE=$(curl -s -b "$COOKIE_JAR" "$ENTITY_URL")

case $TYPE_FILTER in
  PSU) REGEX='class="6"' ;;
  FAN) REGEX='class="7"' ;;
  TEMP) REGEX='class="3"' ;;
  *) echo "UNKNOWN - Tipo inválido: $TYPE_FILTER"; exit 3 ;;
esac

ID_LIST=$(echo "$ENTITY_RESPONSE" | grep -E "$REGEX" | grep -oP 'id="\K[0-9]+')
[ -z "$ID_LIST" ] && { echo "UNKNOWN - No se encontraron entidades $TYPE_FILTER"; exit 3; }

#
# Obtener datos
#

DATA_URL="http://$IP_ADDRESS/wcn/panel3/data.x?uid=$LOGIN_UID&pos=287&cheid=2"
DATA_RESPONSE=$(curl -s -b "$COOKIE_JAR" "$DATA_URL")

STATUS=0
OUTPUT=""
PERF_DATA=""

for ID in $ID_LIST; do
  LINE=$(echo "$DATA_RESPONSE" | grep -oP "<entext id=\"$ID\"[^>]+")
  [ -z "$LINE" ] && continue

  TEMP=$(echo "$LINE" | grep -oP 'temp="\K[0-9]+')
  ERROR=$(echo "$LINE" | grep -oP 'error="\K[0-9]+')
  LABEL=$(echo "$ENTITY_RESPONSE" | grep "id=\"$ID\"" | grep -oP 'descr="\K[^"]+')

  if [[ "$TYPE_FILTER" == "TEMP" ]]; then
    # Solo evaluar temperatura
    if [ "$TEMP" -ge "$TEMP_CRIT" ]; then
      OUTPUT+="CRITICAL - $LABEL temp $TEMP°C >= $TEMP_CRIT | "
      STATUS=2
    elif [ "$TEMP" -ge "$TEMP_WARN" ]; then
      OUTPUT+="WARNING - $LABEL temp $TEMP°C >= $TEMP_WARN | "
      [ "$STATUS" -lt 2 ] && STATUS=1
    else
      OUTPUT+="OK - $LABEL temp $TEMP°C | "
    fi
    PERF_DATA+="${LABEL// /_}=${TEMP}C;$TEMP_WARN;$TEMP_CRIT;0;100 "
  else
    # Evaluar estado (error)
    if [ "$ERROR" -ne 2 ]; then
      OUTPUT+="CRITICAL - $LABEL tiene error $ERROR | "
      STATUS=2
    else
      OUTPUT+="OK - $LABEL estado OK | "
    fi
  fi
done

# 4. Salida
echo "${OUTPUT::-3} | $PERF_DATA"
exit $STATUS
