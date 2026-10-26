#!/bin/sh
# run.sh <dump dir> <variant...>: N=5 Gemma runs per question per variant into <dump dir>/runs/<variant>/<qid>.txt
set -e
DUMP=$1; shift
RIG=$(dirname "$0")/../.build/release/rig
for f in "$DUMP"/*_user.txt; do
  qid=$(basename "$f" _user.txt)
  [ -f "$DUMP/$qid.prompt" ] || "$RIG" templateuser "$f" > "$DUMP/$qid.prompt"
  for v in "$@"; do
    mkdir -p "$DUMP/runs/$v"
    out="$DUMP/runs/$v/$qid.txt"
    [ -s "$out" ] && continue
    "$RIG" gengrammar "$DUMP/$qid.prompt" "$DUMP/${qid}_$v.gbnf" 0.45 5 1000 > "$out.part" && mv "$out.part" "$out"
  done
done
