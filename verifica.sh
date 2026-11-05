#!/usr/bin/env bash
# Confronta le tue query con le soluzioni, sui dati base e sulle varianti.
# Uso: ./verifica.sh        tutti gli esercizi
#      ./verifica.sh 3      solo l'esercizio 3
#      ./verifica.sh 1 4    gli esercizi 1 e 4
# Lavora su database temporanei: esercizi.db non viene toccato.
set -uo pipefail
cd "$(dirname "$0")"

# Quanti esercizi controllare. Se è vuoto li ricava dai file in soluzioni/ ed esercizi/.
# Per fissarli a mano scrivi il numero, per esempio NUM_ESERCIZI=8.
NUM_ESERCIZI=

SQLITE=(sqlite3 -init /dev/null -batch -bail -cmd 'PRAGMA foreign_keys=ON')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

elenco_esercizi() {
    if [ -n "$NUM_ESERCIZI" ]; then
        seq 1 "$NUM_ESERCIZI"
    else
        ls soluzioni esercizi 2>/dev/null | sed -nE 's/^es([0-9]+[a-z]?)(_.*)?\.sql$/\1/p' | sort -Vu
    fi
}

elenco_dataset() {  # "base" e il nome di ogni variante
    local file
    echo base
    for file in varianti/*.sql; do
        [ -f "$file" ] && basename "$file" .sql
    done
}

crea_db() {  # $1 = dataset; stampa il percorso di un database nuovo
    local db
    db=$(mktemp -p "$tmp" XXXXXX.db)
    cp dati/base.db "$db"
    if [ "$1" != base ] && ! "${SQLITE[@]}" "$db" < "varianti/$1.sql"; then
        echo "Errore in varianti/$1.sql" >&2
        return 1
    fi
    echo "$db"
}

senza_commenti() {  # $1 = file sql
    sed -zE 's#/\*([^*]|\*+[^*/])*\*+/##g; s/--[^\n]*//g' "$1"
}

ha_order_by() {  # $1 = file sql; vero se l'ultima istruzione ha ORDER BY
    senza_commenti "$1" | awk 'BEGIN { RS = ";" } NF { ultima = $0 } END { print ultima }' |
        tr '\n' ' ' | grep -qiE 'order[[:space:]]+by'
}

normalizza() {  # arrotonda i decimali a 2 cifre: 10.0 diventa 10, 3.14159 diventa 3.14
    awk -F'|' -v OFS='|' -v CONVFMT='%.2f' '{
        for (i = 1; i <= NF; i++)
            if ($i ~ /^-?[0-9]+\.[0-9]+$/) $i = sprintf("%.2f", $i) + 0
        print
    }'
}

stato() {  # $1 = database; stampa tabelle e viste in una forma confrontabile
    local nome
    {
        "${SQLITE[@]}" -list -noheader "$1" "
            SELECT lower(m.name), group_concat(lower(p.name))
            FROM sqlite_master m JOIN pragma_table_info(m.name) p
            WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
            GROUP BY m.name"
        "${SQLITE[@]}" -list -noheader "$1" "
            SELECT name FROM sqlite_master
            WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'" |
        while IFS= read -r nome; do
            "${SQLITE[@]}" -list -noheader -nullvalue NULL "$1" "SELECT * FROM \"$nome\"" 2>/dev/null |
                normalizza | awk -v t="$nome" '{ print tolower(t) ": " $0 }'
        done
    } | LC_ALL=C sort
}

esegui() {  # $1 = file sql, $2 = database, $3 = dove scrivere le righe; ritorna 1 se dà errore
    "${SQLITE[@]}" -list -noheader -nullvalue NULL "$2" < "$1" 2>&1 | normalizza > "$3"
    return "${PIPESTATUS[0]}"
}

stesse_righe() {  # confronta le righe di $tmp/mio e $tmp/ref senza badare all'ordine
    cmp -s <(LC_ALL=C sort "$tmp/mio") <(LC_ALL=C sort "$tmp/ref")
}

confronta() {  # $1 = tua query, $2 = soluzione, $3 = dataset
    # Ritorna 0 se coincidono, 1 se no, 2 se la query dà errore, 3 se la soluzione dà errore.
    local db_mio db_ref
    db_mio=$(crea_db "$3")
    db_ref=$(crea_db "$3")
    esegui "$1" "$db_mio" "$tmp/mio" || return 2
    esegui "$2" "$db_ref" "$tmp/ref" || return 3

    # La soluzione non stampa niente ma cambia il database: conta lo stato finale.
    if [ ! -s "$tmp/ref" ]; then
        stato "$(crea_db "$3")" > "$tmp/stato_iniziale"
        stato "$db_ref" > "$tmp/stato_ref"
        if ! cmp -s "$tmp/stato_iniziale" "$tmp/stato_ref"; then
            stato "$db_mio" > "$tmp/stato_mio"
            cmp -s "$tmp/stato_mio" "$tmp/stato_ref" || return 1
            return 0
        fi
    fi

    if ha_order_by "$2"; then
        cmp -s "$tmp/mio" "$tmp/ref" || return 1
    else
        stesse_righe || return 1
    fi
}

risposta() {  # $1 = file sql, $2 = dataset; mostra quello che produce il file
    local db out
    db=$(crea_db "$2")
    out=$("${SQLITE[@]}" -box -header -nullvalue NULL "$db" < "$1" 2>&1)
    if [ -z "$out" ]; then  # nessuna riga stampata: mostra cosa è cambiato nel database
        stato "$(crea_db "$2")" > "$tmp/prima"
        stato "$db" > "$tmp/dopo"
        out=$(diff "$tmp/prima" "$tmp/dopo" | sed -n 's/^< /- /p; s/^> /+ /p')
    fi
    echo "${out:-(nessuna riga)}" | sed 's/^/    /'
}

verifica() {  # $1 = numero esercizio; ritorna 0 se ok
    local n=$1 mio="esercizi/es$1.sql" ref d esito=0 passati riferimenti=()
    local piu_vicina="" dati_diversi="" massimo=-1

    for ref in "soluzioni/es$n.sql" "soluzioni/es$n"_*.sql; do
        [ -f "$ref" ] && riferimenti+=("$ref")
    done
    if [ ${#riferimenti[@]} = 0 ]; then
        echo "es$n: manca la soluzione (soluzioni/es$n.sql)"
        return 1
    fi
    if [ ! -f "$mio" ] || [ -z "$(senza_commenti "$mio" | tr -d '[:space:];')" ]; then
        echo "es$n: da fare"
        return 0
    fi

    for ref in "${riferimenti[@]}"; do
        passati=0
        for d in "${DATASET[@]}"; do
            confronta "$mio" "$ref" "$d"
            esito=$?
            [ "$esito" = 0 ] || break
            passati=$((passati + 1))
        done
        case $esito in
            0)
                if [ "$ref" = "${riferimenti[0]}" ]; then
                    echo "es$n: OK"
                else
                    echo "es$n: OK (coincide con $ref)"
                fi
                for d in "${DATASET[@]}"; do
                    echo "  La tua risposta (dati: $d):"
                    risposta "$mio" "$d"
                done
                return 0
                ;;
            1)
                if [ "$passati" -gt "$massimo" ]; then
                    massimo=$passati
                    piu_vicina=$ref
                    dati_diversi=$d
                fi
                ;;
            2)
                echo "es$n: ERRORE (dati: $d)"
                sed 's/^/    /' "$tmp/mio"
                return 1
                ;;
            3)
                echo "es$n: ERRORE nella soluzione $ref (dati: $d)"
                sed 's/^/    /' "$tmp/ref"
                return 1
                ;;
        esac
    done

    # Nessuna soluzione coincide: mostra la differenza da quella che regge su più dataset.
    ref=$piu_vicina
    d=$dati_diversi
    confronta "$mio" "$ref" "$d"
    echo "es$n: DIVERSO (dati: $d)"
    if [ -s "$tmp/ref" ] && stesse_righe; then
        echo "  righe giuste, ordine diverso dalla soluzione"
    fi
    echo "  La tua risposta:"
    risposta "$mio" "$d"
    echo "  Risposta attesa ($ref):"
    risposta "$ref" "$d"
    return 1
}

mapfile -t ESERCIZI < <(elenco_esercizi)
mapfile -t DATASET < <(elenco_dataset)

if [ ! -f dati/base.db ] || [ ${#ESERCIZI[@]} = 0 ]; then
    echo "Nessun esercizio caricato: usa prima ./carica.sh (vedi README.md)" >&2
    exit 2
fi
for n in "$@"; do
    if ! printf '%s\n' "${ESERCIZI[@]}" | grep -qxF -- "$n"; then
        echo "Uso: ./verifica.sh [numero...]    Esercizi disponibili: ${ESERCIZI[*]}" >&2
        exit 2
    fi
done
for d in "${DATASET[@]}"; do
    crea_db "$d" > /dev/null || exit 2
done

[ $# -gt 0 ] || set -- "${ESERCIZI[@]}"
esito=0
for n in "$@"; do
    [ "$n" = "$1" ] || echo
    verifica "$n" || esito=1
done
exit $esito
