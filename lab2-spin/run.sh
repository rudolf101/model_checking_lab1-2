#!/usr/bin/env bash
# Лаба 2: прогон всех свойств в SPIN. Каждое свойство собирается отдельно
# (spin -D<ИМЯ>), логи -> logs/<ИМЯ>.log, трассы -> logs/<ИМЯ>.trail.txt
set -u
cd "$(dirname "$0")"
SPIN="${SPIN:-spin}"
CC="${CC:-gcc}"
command -v "$SPIN" >/dev/null || { echo "spin не найден: задайте SPIN=/путь/к/spin"; exit 1; }
mkdir -p logs build
"$SPIN" -V | tee logs/version.txt

# имя:флаги pan (-a поиск циклов допуска, -f слабая справедливость)
PROPS="SAFETY: P1:-a P2:-a P3:-a P4:-a V1:-a V2:-a V3:-a L1:-a,-f"

for item in $PROPS; do
  name="${item%%:*}"; flags="${item#*:}"; flags="${flags//,/ }"
  d="build/$name"; rm -rf "$d"; mkdir -p "$d"; cp turnstile.pml "$d/"
  (
    cd "$d"
    if [ "$name" = SAFETY ]; then
      # без LTL: поиск тупиков (invalid end states) и нарушений assert
      "$SPIN" -a turnstile.pml >/dev/null && "$CC" -O2 -DSAFETY -DNOREDUCE -o pan pan.c
    else
      "$SPIN" -D"$name" -a turnstile.pml >/dev/null && "$CC" -O2 -DNOREDUCE -DNFAIR=3 -o pan pan.c
    fi
    start=$(date +%s.%N)
    ./pan -m200000 $flags > run.log 2>&1
    echo "elapsed: $(awk "BEGIN{print $(date +%s.%N) - $start}") s" >> run.log
    if [ -f turnstile.pml.trail ]; then
      if [ "$name" = SAFETY ]; then
        "$SPIN" -t -p -g -l turnstile.pml > trail.txt 2>&1
      else
        "$SPIN" -D"$name" -t -p -g -l turnstile.pml > trail.txt 2>&1
      fi
    fi
  )
  cp "$d/run.log" "logs/$name.log"
  [ -f "$d/trail.txt" ] && cp "$d/trail.txt" "logs/$name.trail.txt"
  errs=$(grep -Eo "errors: [0-9]+" "logs/$name.log" | head -1)
  states=$(grep -E "states, stored" "logs/$name.log" | head -1 | awk '{print $1}')
  printf "%-7s %-12s states=%-8s %s\n" "$name" "$errs" "$states" "$flags"
done | tee logs/summary.txt
