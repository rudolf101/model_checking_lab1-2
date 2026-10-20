#!/usr/bin/env bash
# Лаба 1: прогон всех спецификаций в nuXmv. Лог -> logs/nuxmv.log
set -u
cd "$(dirname "$0")"
mkdir -p logs
NUXMV="${NUXMV:-nuXmv}"
command -v "$NUXMV" >/dev/null || { echo "nuXmv не найден: задайте NUXMV=/путь/к/nuXmv"; exit 1; }
{
  echo "### $(date -Is)"
  start=$(date +%s.%N)
  "$NUXMV" -source cmds.txt 2>&1
  echo "### elapsed: $(awk "BEGIN{print $(date +%s.%N) - $start}") s"
} | tee logs/nuxmv.log
echo
echo "== Итог =="
grep -E "^-- specification" logs/nuxmv.log | sed -E 's/^-- specification (.*) is (true|false)$/\2  \1/' | cut -c1-150
