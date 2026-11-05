#!/usr/bin/env bash
# Ricrea esercizi.db dal database caricato.
# Uso: ./reset.sh          dati base
#      ./reset.sh nome     dati base più varianti/nome.sql
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f dati/base.db ]; then
    echo "Nessun database caricato: usa prima ./carica.sh (vedi README.md)" >&2
    exit 2
fi
if [ $# -gt 1 ] || { [ $# = 1 ] && [ ! -f "varianti/$1.sql" ]; }; then
    echo "Uso: ./reset.sh [variante]    Varianti disponibili:" $(ls varianti | sed 's/\.sql$//') >&2
    exit 2
fi

rm -f esercizi.db
cp dati/base.db esercizi.db
[ $# = 0 ] || sqlite3 -init /dev/null -batch -bail esercizi.db < "varianti/$1.sql"
echo "esercizi.db ricreato (${1:-base})"
