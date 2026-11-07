#!/usr/bin/env bash
set -euo pipefail

# Impostazioni e messaggi
SQLITE=(sqlite3 -init /dev/null -batch -bail)
NON_SQLITE='auto_increment|engine[[:space:]]*=|create[[:space:]]+(database|schema|sequence|extension|type)'
NON_SQLITE+='|^[[:space:]]*use[[:space:]]|lock[[:space:]]+tables|foreign_key_checks|nextval[[:space:]]*\('
NON_SQLITE+='|owner[[:space:]]+to|search_path|::[a-z]|^copy[[:space:]]'

uso() {
    cat >&2 <<'FINE'
Uso: ./carica.sh [--forza] <database> <esercizi-svolti>
  <database>         file SQLite, oppure script SQL che crea e riempie le tabelle
  <esercizi-svolti>  file unico con testi e soluzioni, oppure cartella con es1.sql, es2.sql, ...
  --forza            sostituisce gli esercizi già caricati, cancellando anche le tue risposte
FINE
    exit 2
}

errore() {
    echo "$1" >&2
    exit 1
}

# Analisi file SQL
senza_commenti() {
    sed -zE 's#/\*([^*]|\*+[^*/])*\*+/##g; s/--[^\n]*//g' "$1"
}

inizia_con_sql() {
    senza_commenti "$1" | tr -s '[:space:]' ' ' |
        grep -iE '^ ?(select|with|insert|replace|update|delete|create|drop|alter|values|begin|pragma)\b' > /dev/null
}

# Controllo argomenti
forza=0
if [ "${1:-}" = --forza ]; then
    forza=1
    shift
fi
[ $# = 2 ] || uso
[ -f "$1" ] || errore "Database non trovato: $1"
[ -e "$2" ] || errore "Esercizi svolti non trovati: $2"
if [ -f "$2" ] && [ "$(head -c 4 "$2")" = "%PDF" ]; then
    echo "carica.sh non legge i PDF. Converti il file in testo e carica il .txt:" >&2
    errore "    pdftotext -layout \"$2\" esercizi.txt"
fi
database=$(realpath "$1")
svolti=$(realpath "$2")
cd "$(dirname "$0")"

# Controllo cartella
if [ "$forza" = 0 ] && [ -e dati/base.db ]; then
    echo "Questa cartella ha già degli esercizi caricati. Per un nuovo esame usa una copia" >&2
    echo "pulita della cartella, oppure rilancia con --forza (cancella anche le tue risposte)." >&2
    exit 1
fi

# Cartella temporanea
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp"/{dati,esercizi,soluzioni,testi,varianti}

# Lettura database
if [ "$(head -c 15 "$database")" = "SQLite format 3" ]; then
    cp "$database" "$tmp/dati/base.db"
    chmod u+w "$tmp/dati/base.db"
elif ! "${SQLITE[@]}" "$tmp/dati/base.db" < "$database"; then
    if riga=$(grep -inE -m1 "$NON_SQLITE" "$database"); then
        echo "Riga ${riga%%:*}: lo script sembra scritto per MySQL o PostgreSQL, serve SQLite (leggi README.md)." >&2
    fi
    errore "Errore nello script del database: $database"
fi
tabelle=$("${SQLITE[@]}" -list -noheader "$tmp/dati/base.db" "
    SELECT group_concat(name, ', ') FROM sqlite_master
    WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
[ -n "$tabelle" ] || errore "Il database non contiene tabelle: $database"

# Controllo dati
vuote=""
piene=0
while IFS= read -r nome; do
    if [ "$("${SQLITE[@]}" -list -noheader "$tmp/dati/base.db" "SELECT count(*) FROM \"$nome\"")" = 0 ]; then
        vuote+=" $nome"
    else
        piene=$((piene + 1))
    fi
done < <("${SQLITE[@]}" -list -noheader "$tmp/dati/base.db" "
    SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
if [ "$piene" = 0 ]; then
    echo "Il database non contiene dati: tutte le tabelle sono vuote." >&2
    errore "Ogni query darebbe zero righe e anche una risposta sbagliata risulterebbe OK."
fi
[ -z "$vuote" ] || echo "Attenzione: tabelle senza righe:$vuote"

# Lettura esercizi svolti
if [ -d "$svolti" ]; then
    scartati=""
    for file in "$svolti"/*.sql; do
        [ -f "$file" ] || continue
        nome=$(basename "$file" .sql)
        if [[ ! $nome =~ ^es[0-9]+[a-z]?(_.*)?$ ]]; then
            scartati+=" $nome.sql"
            continue
        fi
        cp "$file" "$tmp/soluzioni/"
        [[ $nome =~ ^es[0-9]+[a-z]?$ ]] || continue
        sed -n '/^[[:space:]]*\(--.*\)\?$/!q; s/^[[:space:]]*-- \?//p' "$file" > "$tmp/testi/$nome.txt"
    done
    [ -z "$scartati" ] || echo "Attenzione: file ignorati, il nome deve essere esN.sql o esN_nome.sql:$scartati"
else
    awk -v dir="$tmp" '
        function posizione(e,   lettera) {
            lettera = e
            sub(/^[0-9]+/, "", lettera)
            return e * 100 + (lettera == "" ? 0 : index("abcdefghijklmnopqrstuvwxyz", lettera))
        }

        { sub(/\r$/, "") }

        sezione == "" && corrente != "" && tolower($0) ~ /soluzion/ && NF <= 3 {
            sezione = "soluzioni"
            corrente = ""
            ultima = 0
            next
        }

        {
            riga = tolower($0)
            if (match(riga, /^[[:space:]]*(esercizio|es\.?)[[:space:]]*[0-9]+[a-z]?[.:]?([[:space:]]|$)/) ||
                match(riga, /^[[:space:]]*[0-9]+[a-z]?\.([[:space:]]|$)/) ||
                match(riga, /^[[:space:]]*[0-9]+[a-z]?[[:space:]]*$/)) {
                lunghezza = RLENGTH
                etichetta = substr(riga, 1, lunghezza)
                sub(/^[[:space:]]*(esercizio|es\.?)?[[:space:]]*/, "", etichetta)
                sub(/[.:[:space:]]*$/, "", etichetta)

                valida = posizione(etichetta) > ultima
                if (riga ~ /^[[:space:]]*[0-9]+[[:space:]]*$/) {
                    valida = valida && etichetta + 0 == int(ultima / 100) + 1
                    if (sezione == "soluzioni") valida = valida && (etichetta in testi)
                }
                if (valida) {
                    corrente = etichetta
                    ultima = posizione(etichetta)
                    if (sezione == "") testi[etichetta] = 1
                    $0 = substr($0, lunghezza + 1)
                    if ($0 ~ /^[[:space:]]*$/) next
                }
            }
        }

        corrente != "" {
            if (sezione == "soluzioni") print > (dir "/soluzioni/es" corrente ".sql")
            else print > (dir "/testi/es" corrente ".txt")
        }
    ' "$svolti"
fi

# Elenco esercizi
numeri=$(ls "$tmp/soluzioni" "$tmp/testi" | sed -nE 's/^es([0-9]+[a-z]?)(_.*)?\.(sql|txt)$/\1/p' | sort -Vu)
if [ -z "$(ls "$tmp/soluzioni")" ]; then
    echo "Nessuna soluzione trovata in: $svolti" >&2
    errore "Controlla il README.md, sezione \"Condizioni perché funzioni\"."
fi

# Creazione file esercizi
for n in $numeri; do
    {
        echo "-- Esercizio $n"
        if [ -f "$tmp/testi/es$n.txt" ]; then
            sed '/^[[:space:]]*$/d' "$tmp/testi/es$n.txt" | fold -s -w 76 |
                sed -E 's/[[:space:]]+$//; s/^/-- /'
        fi
        echo
    } > "$tmp/esercizi/es$n.sql"

    if [ ! -f "$tmp/soluzioni/es$n.sql" ]; then
        echo "Attenzione: l'esercizio $n non ha una soluzione (soluzioni/es$n.sql)"
    fi
done

# Prova soluzioni
"${SQLITE[@]}" "$tmp/dati/base.db" .dump > "$tmp/iniziale.dump"
for file in "$tmp"/soluzioni/es*.sql; do
    cp "$tmp/dati/base.db" "$tmp/prova.db"
    if ! stampato=$("${SQLITE[@]}" "$tmp/prova.db" < "$file" 2>"$tmp/errore"); then
        if inizia_con_sql "$file"; then
            echo "Attenzione: soluzioni/$(basename "$file") dà errore e va corretta:"
        else
            echo "Attenzione: soluzioni/$(basename "$file") non inizia con un'istruzione SQL (algebra o teoria?): va corretta o tolta:"
        fi
        sed 's/^/    /' "$tmp/errore"
    elif [ -z "$stampato" ] && "${SQLITE[@]}" "$tmp/prova.db" .dump | cmp -s - "$tmp/iniziale.dump"; then
        echo "Attenzione: soluzioni/$(basename "$file") non restituisce righe su questi dati:"
        echo "    anche una risposta sbagliata senza righe risulterebbe OK."
    fi
done

# Installazione cartella
rm -rf dati esercizi soluzioni varianti esercizi.db
mv "$tmp"/{dati,esercizi,soluzioni,varianti} .
./reset.sh > /dev/null

# Recap
echo "Tabelle: $tabelle"
echo "Esercizi caricati:" $numeri
echo "Scrivi le risposte in esercizi/es<numero>.sql, poi lancia ./verifica.sh <numero>"
