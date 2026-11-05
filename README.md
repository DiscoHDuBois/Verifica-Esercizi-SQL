# Verifica esercizi SQL

Carichi un database e gli esercizi svolti, scrivi le tue query e `./verifica.sh <numero>`
le confronta con le soluzioni. Serve solo `sqlite3`.

## Avvio rapido

Per esercitarsi, fare una copia della cartella per ogni esame, così questa resta pulita:

    cp -r ~/Documenti/verifica-sql ~/Documenti/mio-esame
    cd ~/Documenti/mio-esame
    ./carica.sh percorso/database.db percorso/esercizi-svolti

Scrivi la risposta in `esercizi/es1.sql` (il testo dell'esercizio deve essere nel file)

    ./verifica.sh 1       # un esercizio
    ./verifica.sh 1 4     # alcuni esercizi
    ./verifica.sh         # tutti

Per provare le query a mano:

    sqlite3 -init init.sql esercizi.db

Dentro sqlite3 puoi eseguire il tuo file con `.read esercizi/es1.sql`, o scrivere le query
al prompt con il `;` finale. Comandi utili: `.tables`, `.schema Ordini`, `.quit`.

## Condizioni perché funzioni

Una prova si può verificare solo se ha tutto questo:

1. **Un database con dati.** Serve un file SQLite, o uno script SQL compatibile con SQLite: uno
   script scritto per MySQL o PostgreSQL può dare errore e va adattato. Se tutte le tabelle sono
   vuote `carica.sh` si ferma, perché ogni query darebbe zero righe e anche una risposta
   sbagliata risulterebbe OK. Molte prove riportano solo lo schema: i dati vanno aggiunti a mano.
2. **Le soluzioni.** La risposta attesa si ottiene eseguendo la soluzione: senza soluzioni non
   c'è niente da confrontare. Devono essere query che girano su SQLite.
3. **Gli esercizi in formato testo.** `carica.sh` non legge i PDF. Un PDF con il testo
   selezionabile si converte così, poi si carica il file `.txt`:

       pdftotext -layout prova.pdf prova.txt

   Un PDF scansionato non contiene testo: gli esercizi vanno trascritti a mano.
4. **Esercizi ed etichette riconoscibili.** Le forme accettate sono descritte in
   [Cosa puoi caricare](#cosa-puoi-caricare). Se un file ne usa altre, vanno corrette a mano.
5. **Esercizi di SQL.** Si controllano solo query SQL, non domande di algebra relazionale,
   progettazione o teoria. `carica.sh` non sa riconoscerle: una prova di questo tipo può
   caricarsi lo stesso, e le sue risposte vengono segnalate come soluzioni che danno errore. In
   un file convertito da un PDF la parte prima del primo esercizio viene ignorata.

`carica.sh` si ferma con un messaggio, lasciando la cartella com'è, se il database è vuoto o dà
errore, se non trova nessuna soluzione o se riceve un PDF.

In questi casi invece carica lo stesso, ma la verifica è meno affidabile e conviene sistemare:

| Avviso | Cosa fare |
| --- | --- |
| `soluzioni/esN.sql dà errore` | Correggere il file, o toglierlo se non è una query: finché dà errore l'esercizio non è verificabile |
| `soluzioni/esN.sql non restituisce righe` | Aggiungere dati o una variante: una risposta sbagliata senza righe risulterebbe OK |
| `tabelle senza righe` | Aggiungere dati: le query su quelle tabelle danno risultati vuoti |
| `l'esercizio N non ha una soluzione` | Scrivere `soluzioni/esN.sql`, altrimenti l'esercizio non è verificabile |

## Cosa puoi caricare

    ./carica.sh <database> <esercizi-svolti>

**Il database** può essere:

- un file SQLite, per esempio `prova.db`
- uno script SQL che crea e riempie le tabelle, per esempio `biblioteca-script-sql.sql`

Se schema e dati sono in due file, uniscili prima: `cat schema.sql dati.sql > database.sql`.

**Gli esercizi svolti** possono essere:

- un file unico con i testi e poi le soluzioni:

      Si consideri una base di dati con schema...   <- ignorato

      1.
      Trovare i prodotti di prezzo minore di 100.

      2.
      Trovare i clienti senza ordini.

      Possibili soluzioni

      1.
      SELECT codice FROM Prodotti WHERE prezzo < 100;

      2.
      SELECT ...

  Ogni esercizio inizia con un'etichetta a inizio riga, in una di queste forme:

  - numero con il punto: `1.`, `12.`, `1a.`
  - `Es.` o `Esercizio` con il numero: `Es. 1`, `Esercizio 2:`, `Es. 3a`
  - numero da solo sulla riga, con o senza lettera: `1a`, `3b`, `4`

  Nelle prime due forme il testo può stare anche sulla stessa riga dell'etichetta. Le etichette
  devono essere in ordine crescente. Un numero senza lettera da solo sulla riga vale solo se è il
  successivo (dopo `3b` vale `4`, non `7`): così un numero di pagina non diventa un esercizio.
  Una riga breve con la parola "soluzioni" (o "soluzione") separa i testi dalle soluzioni.

  Gli esercizi con la lettera mantengono l'etichetta: `esercizi/es1a.sql`, `./verifica.sh 1a`.

- una cartella con un file per esercizio: `es1.sql`, `es2.sql`, `es3a.sql`, ... I commenti `--` all'inizio
  di ogni file diventano il testo dell'esercizio. Eventuali soluzioni alternative
  (`es4_altra.sql`) vengono caricate anche loro.

`carica.sh` crea i file in `esercizi/` e `soluzioni/`, prepara `esercizi.db` e prova ogni
soluzione sul database: se una dà errore lo segnala, così puoi correggerla.

In una cartella già usata `carica.sh` si ferma. Con `./carica.sh --forza ...` sostituisce
tutto: cancella esercizi, soluzioni, varianti e **anche le tue risposte**.

## Gli esiti

| Esito | Significato |
| --- | --- |
| `es3: OK` | Il risultato coincide. Sotto viene mostrata la tua risposta, per ogni insieme di dati |
| `es3: OK (coincide con ...)` | Come sopra, ma con una soluzione alternativa |
| `es3: DIVERSO` | Il risultato non coincide. Vengono mostrate la tua risposta e quella attesa |
| `es3: ERRORE` | La query non gira. Viene mostrato il messaggio di sqlite3 |
| `es3: da fare` | Il file è vuoto o contiene solo commenti |
| `es3: manca la soluzione` | Non c'è `soluzioni/es3.sql`, quindi non c'è niente da confrontare |

`verifica.sh` esce con 0 se non ci sono risposte sbagliate, con 1 altrimenti.

## Cosa viene confrontato

La query e la soluzione girano su database temporanei, uno nuovo ogni volta: `esercizi.db`
non cambia e un `CREATE VIEW` si può rilanciare quante volte vuoi. Le chiavi esterne sono attive.

- **Colonne**: contano il numero e l'ordine, non i nomi o gli alias.
- **Ordine delle righe**: conta solo se l'ultima istruzione della soluzione ha `ORDER BY`.
- **Decimali**: arrotondati a 2 cifre, e `10.0` vale come `10`.
- **NULL**: è diverso da `0` e dalla stringa vuota.
- **Modifiche**: se la soluzione non stampa niente ma cambia il database (`UPDATE`, `DELETE`,
  `CREATE TABLE`, `CREATE VIEW`...), si confronta lo stato finale di tabelle e viste. In questo
  caso la risposta mostrata è l'elenco delle righe tolte (`-`) e aggiunte (`+`).

## Cosa modificare quando cambiano gli esercizi

### Numero di esercizi

Di solito non serve toccare niente: `verifica.sh` conta gli esercizi dai file in `soluzioni/` ed
`esercizi/`, quindi il numero si aggiorna da solo a ogni caricamento.

Ma per fissarlo a mano, modifica questa riga in cima a `verifica.sh` (riga 6):

    NUM_ESERCIZI=

Per esempio `NUM_ESERCIZI=8` controlla gli esercizi da 1 a 8 e rifiuta gli altri. Un numero
fisso non si aggiorna: se carichi più esercizi va cambiato a mano, oppure lasciato vuoto per
tornare al conteggio automatico. Con esercizi come `1a` va lasciato vuoto, perché conta solo
numeri interi.

### Aggiungere un esercizio a mano

Per aggiungere per esempio l'esercizio 6, senza ricaricare gli altri:

1. Scrivere la soluzione in `soluzioni/es6.sql`.
2. Creare `esercizi/es6.sql` con il testo in commenti `--`.
3. Lanciare `./verifica.sh 6`.

Se si è fissato `NUM_ESERCIZI`, aumentarlo a 6.

### Accettare più di una soluzione

Aggiungi un file `soluzioni/esN_nome.sql`, per esempio `soluzioni/es4_con_clienti_senza_ordini.sql`.
La risposta è giusta se coincide con almeno una soluzione. Serve quando il testo si può leggere
in due modi, o quando la soluzione del docente non corrisponde al testo: si può anche correggere
direttamente `soluzioni/esN.sql`.

### Provare altri dati

Ogni file `varianti/nome.sql` è una variante: viene applicato sopra i dati base e ogni esercizio
deve risultare giusto anche lì. Il file contiene istruzioni come:

    INSERT INTO RigheOrdine VALUES (3,2,15,800);

Serve a scoprire le query che funzionano solo per caso, per esempio un `LIMIT 1` che perde i
pareggi. Non servono altre modifiche, le varianti vengono trovate da sole.

### Altre impostazioni

| Cosa | Dove |
| --- | --- |
| Cifre decimali nel confronto | `normalizza()` in `verifica.sh`: cambia i due `%.2f` |
| Aspetto delle tabelle in sqlite3 | `init.sql` |

## Ripristinare i dati

    ./reset.sh          # dati base
    ./reset.sh nome     # dati base più varianti/nome.sql

Serve dopo aver modificato `esercizi.db`, o per provare a mano una variante. Chiudi prima sqlite3
e riaprilo dopo.

## Limiti

- **OK vuol dire stessi risultati su questi dati, non query corretta.** Se per esempio `ORDER BY
  Nome` dà lo stesso ordine di `ORDER BY Codice`, la risposta sbagliata passa. Una variante
  scelta bene riduce il rischio.
- **Il confronto riguarda tutto quello che il file stampa.** Una `SELECT` di prova rimasta nel
  file dà DIVERSO: lascia solo la risposta.
- **Le viste richieste dal testo non vengono controllate se la soluzione stampa anche delle
  righe.** Conta solo il risultato finale, perché la vista potrebbe essere solo un passaggio
  intermedio.
- **Con `ORDER BY` e valori pari merito** due risposte giuste possono avere le righe in ordine
  diverso. L'esito è DIVERSO con la nota "righe giuste, ordine diverso dalla soluzione": in quel
  caso giudica tu.

## Attenzione con sqlite3

- Le stringhe vanno tra apici singoli: `'abc'`. Le virgolette doppie danno errore.
- Una vista resta in `esercizi.db`: per rileggere a mano un file che fa `CREATE VIEW`, aggiungi
  prima `DROP VIEW IF EXISTS V;` oppure lancia `./reset.sh`.
- Le chiavi esterne sono attive solo se apri il database con `-init init.sql`.
- `> ALL (...)` e `> ANY (...)` non esistono in SQLite: usa `MAX`, `MIN` o `NOT EXISTS`.
- La divisione tra interi tronca: `7/2` vale 3. Per avere i decimali scrivi `7*1.0/2`.

## File

| File | Contenuto |
| --- | --- |
| `carica.sh` | Carica database ed esercizi svolti |
| `verifica.sh` | Confronta le tue risposte con le soluzioni |
| `reset.sh` | Ricrea `esercizi.db` |
| `init.sql` | Impostazioni di sqlite3 (tabelle leggibili, chiavi esterne) |

Create da `carica.sh`:

| File | Contenuto |
| --- | --- |
| `esercizi/` | Le tue risposte, una per esercizio |
| `soluzioni/` | Le soluzioni usate da `verifica.sh` |
| `varianti/` | Altri dati su cui provare le query, all'inizio vuota |
| `dati/base.db` | Copia del database caricato, da non modificare |
| `esercizi.db` | Il database su cui lavorare, ricreabile con `reset.sh` |
