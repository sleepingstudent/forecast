#!/usr/bin/env bash
##############################################################################
# traffic_run_mz.sh — генерация Packet-in через mz, каждый пакет с новым MAC
##############################################################################
set -euo pipefail

# --- параметры запуска ------------------------------------------------------
DURATION="${1:-3h}"          # пример: 90m, 2h30m, 1d и т.п.
IFACE="${2:-}"               # если не указан — autodetect

# autodetect интерфейса, если не передан
if [[ -z "$IFACE" ]]; then
  IFACE="$(ip -o link show | awk -F': ' '!/ lo/{print $2; exit}')"
fi

ip link show "$IFACE" >/dev/null 2>&1 \
  || { echo "[traffic_run] интерфейс $IFACE не найден"; exit 1; }
command -v mz >/dev/null 2>&1 \
  || { echo "[traffic_run] утилита mz не установлена"; exit 1; }

# перевести DURATION в секунды
TIMEOUT=$(python3 - <<'EOF' "$DURATION"
import sys, re
arg = sys.argv[1].strip().lower()
m = re.fullmatch(r'(\d+)([smhd]?)', arg)
num, unit = int(m[1]), m[2] or 's'
mult = dict(s=1, m=60, h=3600, d=86400)[unit]
print(num*mult)
EOF
)

echo "[traffic_run] генерируем $DURATION = ${TIMEOUT}s на интерфейсе $IFACE"

# лог в ~/runos_traffic_logs/YYYYMMDD-HHMMSS/controller_traffic.log
LOGDIR="$HOME/runos_traffic_logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"
exec > >(tee "$LOGDIR/controller_traffic.log") 2>&1

# запускает переданную команду до исчерпания TIMEOUT
run_until_deadline() {
  local deadline=$((SECONDS + TIMEOUT))
  while (( SECONDS < deadline )); do
    "$@"
  done
}

##############################################################################
# 1) Фоновый ровный поток — 5 пакетов/с (каждый с новым MAC)
##############################################################################
( run_until_deadline bash -c '
send_n_packets() {
  local n=$1
  for ((i=0; i<n; i++)); do
    mz '"$IFACE"' -a rand -b rand -c 1 -p 64 >/dev/null 2>&1
  done
}
while true; do
  send_n_packets 5
  sleep 1
done
' ) &

##############################################################################
# 2) Усиленные всплески — каждые 2–5 секунд, 30–50 пакетов
##############################################################################
( run_until_deadline bash -c '
send_n_packets() {
  local n=$1
  for ((i=0; i<n; i++)); do
    mz '"$IFACE"' -a rand -b rand -c 1 -p 64 >/dev/null 2>&1
  done
}
while true; do
  N=$(shuf -i30-50 -n1)
  send_n_packets "$N"
  sleep $(shuf -i4-7 -n1)
done
' ) &

##############################################################################
# 3) Синусоидальный тренд — период ~90 сек (1.5 мин)
##############################################################################
( run_until_deadline bash -c '
send_n_packets() {
  local n=$1
  for ((i=0; i<n; i++)); do
    mz '"$IFACE"' -a rand -b rand -c 1 -p 64 >/dev/null 2>&1
  done
}
for ((s=0;;s++)); do
  AMP=$(python3 -c "import math,sys; t=int(sys.argv[1]); print(int(4*(1+1.5*math.sin(2*math.pi*t/90))))" "$s")
  send_n_packets "$AMP"
  sleep 1
done
' ) &

##############################################################################
# 4) Плавающий аварийный пик — каждые 1–3 мин, сам пик ~30 с
##############################################################################
( run_until_deadline bash -c '
send_n_packets() {
  local n=$1
  for ((i=0; i<n; i++)); do
    mz '"$IFACE"' -a rand -b rand -c 1 -p 64 >/dev/null 2>&1
  done
}
while true; do
  for N in 15 30 60 120 150 120 60 30 15; do
    send_n_packets "$N"
    sleep 1
  done
  wait_sec=$((60 + RANDOM % 121))
  echo "[traffic_run] следующий аварийный пик через $wait_sec с"
  sleep "$wait_sec"
done
' ) &

wait
echo "[traffic_run]  генерация завершена"
