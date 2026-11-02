#!/bin/bash
# minibench - mini benchmark VPS: steal time, CPU single/multi, consistenza, disco.
# ATTENZIONE: nato su un server preciso (una VPS) - DA AGGIUSTARE PER IL WEB, vedi README.md
#
# ############################################################################
# ##  ATTENZIONE - FRENO ACCESO DI DEFAULT                                  ##
# ##  Senza -r il test NON riparte prima di 10 MINUTI dall'ultimo: ristampa ##
# ##  l'ultimo risultato. Test nuovo subito:  minibench.sh -r 0             ##
# ##  Spegnerlo per sempre: riga "FRENO=" piu' sotto (cerca FRENO=),        ##
# ##  metti 0 al posto di 9. Oppure una volta:  MINIBENCH_FRENO=0           ##
# ##  Per chi lo da a terzi: blocco "FRENO SPENTO DEL TUTTO" (cerca SPENTO) ##
# ##  (10 minuti nominali, cronometro a 9: chi rilancia poco prima, va)     ##
# ############################################################################
#
# CONFIGURAZIONE (lo script e' pensato per girare anche fuori da questa macchina):
#   i default sono prudenti, adatti a un server condiviso: freno fra due test acceso,
#   disco spento. Ogni protezione pero' si puo' allentare o spegnere, cosi' chi lo usa
#   in un altro contesto (tanti campioni di fila, una macchina tutta sua) non si trova
#   bloccato da limiti che li' non servono. Tutto si regola senza toccare la logica:
#     - sorgente  = default per tutti i lanci su quella macchina
#     - ambiente  = per un servizio o un agente (variabili MINIBENCH_...)
#     - switch    = per un lancio solo
#
#   cosa                    sorgente (default per tutti)          ambiente               switch
#   freno fra due test      riga FRENO= (9 = 10 min nominali)     MINIBENCH_FRENO=MIN    -r MIN
#   freno spento del tutto  blocco "FRENO SPENTO DEL TUTTO"       -                      -
#   storico: soglia taglio  riga CSV_KB= (1024 KB)                MINIBENCH_CSV_KB=KB    -
#   storico: righe tenute   riga TIENI= (1000)                    MINIBENCH_TIENI=N      -A (archivia)
#   durata/precisione       riga X=1                              -                      -x N
#   disco (consuma)         spento di default                     -                      -D / -d DIR
#   copie dello storico     -                                     -                      -o FILE (ripetibile)
#   non scrivere storico    -                                     -                      -n
#   vCPU usate              -                                     -                      -c N / -c LISTA
#   (MINIBENCH_CONFERMA e MINIBENCH_AFFINITY sono interni: li usa lo script quando si rilancia da solo.)
#
# Non modifica il sistema. Durata ~23 s, ~26 s con il disco (-D) (misurati su 8 vCPU con SMT). -x N moltiplica tutto.
#
# SCHEMA 2 (dal 2026-11-01 ~08:45): default VELOCE, la precisione si sceglie con -x.
#   Unita' base (-x 1): steal 5 s, CPU 1 core 3 s, istruzioni 1 s l'una, multi-core 3 s,
#   solo core 3 s, 3 giri CPU, disco (solo -D/-d) 1 passata + 1 s di 4k random.
#   Multi-core a 3 s e non 1 (revisione 08:50): con -multi 8 -seconds 1 l'avvio degli 8
#   processi pesa quanto la misura -> 12,4 -> 9,6 GB/s fra due test uguali = falso allarme.
#   Allarmi su CPU e indice solo con almeno 3 test di riferimento (lo steal sempre).
#   CONFERMA DEGLI ALLARMI: se lanci SENZA -x e scatta un allarme, NON viene mandato.
#   Il test non scrive nello storico e si rilancia da solo con -x 3 (~1 min), confrontato
#   con lo stesso storico: se l'allarme si ripete -> "ALLARME CONFERMATO", altrimenti
#   "non confermato: era rumore" e si salva il test lungo (colonna conferma=1).
#   Con -x messo a mano niente conferma: la precisione l'hai gia' scelta tu.
#   CPU 1 core a 3 s (quarta revisione): la scala = CN / (C1 x N) dividerebbe una misura
#   da 3 s per una da 1 s, riportando nel denominatore il rumore tolto dal numeratore.
#   SCHEMA 3 = schema 2 con multi-core a 3 s (la riga di schema 2 non si confronta).
#   -x 3 ~ vecchio default (60 s), -x 10 = alta precisione (~3 min).
#   Non tutto a 1 giro: steal su 2 s e' casuale (il provider ruba a raffiche), 1 solo
#   giro non mostra la consistenza, e misure troppo corte fanno scattare allarmi a vuoto.
#   Lo schema e' nel CSV (colonna schema): si confrontano solo test dello stesso schema.
#   Disco fuori dal default per NON consumarlo: ogni test disco scrive 512 MB (x N con -x).
#   Gli agenti AI usano il default e scelgono loro -x quando serve.
# Storico: ogni lancio aggiunge una riga a minibench.csv ACCANTO ALLO SCRIPT
# (stessa cartella del .sh).
# Uso:  minibench.sh [opzioni] [file.csv]      (minibench.sh -h = aiuto)
#   -c N|lista  affinity: solo le prime N vCPU, o lista (0,2,4,6 / 4-7)
#   -x N        test lungo: tempi, giri e passate disco moltiplicati per N
#   -D          fa ANCHE il test disco, nella cartella dello script (di default NON si fa)
#   -d DIR      fa ANCHE il test disco, nella cartella DIR.
#               Se e' tmpfs (RAM) lo segnala: misureresti la RAM, non il disco
#   -t          solo riassunto breve per Telegram/WhatsApp (5-8 righe)
#   -n          non scrive nello storico (prova al volo)
#   -o FILE     scrive la riga ANCHE in FILE (si ripete: -o a.csv -o b.csv). Il test gira una
#               volta sola; il confronto con la media usa sempre lo storico principale.
#               FILE nuovo -> creato con l'intestazione. Se FILE e' lo storico stesso
#               (o un link a lui) viene saltato, cosi' la riga non si scrive due volte.
#   -r MIN      FRENO (di default ACCESO, 10 min nominali = 9 di cronometro): se nello storico c'e' gia' un test
#               confrontabile (stesso -x, stessa affinity, disco se chiesto) piu' giovane di
#               MIN minuti, NON rifa' il test: stampa quello. -r 0 = test sempre.
#               Serve sui server condivisi: se 12 agenti lo lanciano insieme, il primo fa il
#               test (gli altri aspettano il lucchetto) e gli altri 11 leggono il risultato.
#               Valore di default cambiabile con MINIBENCH_FRENO=MIN.
#               ATTENZIONE: chi fa tanti campioni di fila (ciclo) senza -r 0 ottiene
#               lo stesso risultato ristampato, non campioni nuovi. Se lo dai a terzi,
#               attiva il blocco "FRENO SPENTO DEL TUTTO" nel codice (cerca SPENTO).
#   -A          archivia: sposta le righe vecchie dello storico in minibench-archivio-DATA.csv.gz
#               (accanto allo storico) e tiene le ultime 1000. Non fa il test. Non cancella niente.
#               Quando lo storico supera 1 MB (~2500 test) ogni test lo PROPONE, non lo fa da solo.
#   -h          aiuto
# Esempi: minibench.sh -c 4   |   minibench.sh -D   |   minibench.sh -x 23   |   minibench.sh -t -n
#          minibench.sh -o /percorso/copia1.csv -o /percorso/copia2.csv
# Due test insieme si falsano: un blocco (flock) fa aspettare il secondo.
#   lscpu -e mostra quali vCPU stanno sullo stesso core (stesso valore CORE).
#
# ---------------------------------------------------------------------------
# AFFINITY SPIEGATA SEMPLICE (-c)
# ---------------------------------------------------------------------------
# Cos'e': dire al sistema "questo programma puo' girare SOLO su queste vCPU".
#   Senza -c il test usa tutte le vCPU. Con -c lo chiudi in un recinto.
#
# DEFAULT (senza -c): prova su TUTTE le vCPU che trova (qui 8):
#   1. CPU 1 core ......... 1 processo
#   2. CPU tutti i core ... 1 processo per vCPU (8)
#   3. CPU solo core ...... 1 processo per core (4), solo se c'e' SMT
#   "Tutte" e' meno di 8 se: lo lanci gia' sotto taskset (nproc vede solo le
#   vCPU permesse, riga "test su:") oppure dentro un container/servizio con
#   limite CPU (es. cpus: "2"): lancia 8 processi ma ne rendono 2, lo scrive
#   in "limite cgroup" e calcola la scala sulle CPU concesse.
#
# Perche' serve:
#   1. Vedere come cresce la potenza: prova -c 1, -c 2, -c 4, -c 8.
#      Se raddoppiando le vCPU la "CPU tutti i core" non raddoppia,
#      le vCPU in piu' valgono meno di quanto sembra.
#   2. Scoprire l'SMT (hyperthreading): 2 vCPU sullo stesso core si dividono
#      lo stesso core fisico, quindi rendono meno di 2 core veri.
#        -c 0,1        2 vCPU sullo STESSO core (secondo la VM)
#        -c 0,2        2 vCPU su core DIVERSI
#      Se 0,2 va molto piu' forte di 0,1: l'SMT e' vero.
#      Se vanno uguali: la topologia mostrata dalla VM e' finta (la decide
#      l'hypervisor), sotto le vCPU stanno dove vuole il provider.
#   3. Simulare una macchina piu' piccola: -c 2 = "come andrebbe con 2 vCPU".
#   4. Trovare una vCPU lenta: -c 0, poi -c 3, poi -c 7 ... (1 core per volta).
#
# Esempi:
#   minibench.sh -c 1          solo la vCPU 0
#   minibench.sh -c 4          vCPU 0,1,2,3 (le prime 4)
#   minibench.sh -c 0,2,4,6    4 vCPU, una per core
#   minibench.sh -c 4-7        vCPU dalla 4 alla 7
#
# Da sapere:
#   - Lo storico confronta solo test con la STESSA affinity: -c 4 non viene
#     mischiato con i test su tutte le vCPU.
#   - Numero semplice (-c 4) = le prime N vCPU. Per sceglierle usa la lista.
#   - Prova trovata il 2026-11-01 su questo server: -c 0-3 (2 core "SMT") =
#     3.97 GB/s, -c 0,2,4,6 (4 core diversi) = 3.29 GB/s. Cioe' la topologia
#     dichiarata dalla VM NON corrisponde all'hardware vero (1 test, da ripetere).
# Date SOLO in UTC (dal kernel, niente salti per ora legale). offset_ita = +1 inverno, +2 estate.
#
# ---------------------------------------------------------------------------
# UNITA' (tutte uguali, niente piu' kB/MB/GB misti)
# ---------------------------------------------------------------------------
#   velocita' CPU e disco ...... GB/s   (1 GB = 1.000.000.000 byte, 2 decimali; piu' alto = meglio)
#   giri CPU, durata ........... s      (piu' basso = meglio)
#   steal ...................... %      (piu' basso = meglio)
#
# ---------------------------------------------------------------------------
# INDICE (il dato comune a tutti: % rispetto alla MEDIA DEGLI ULTIMI 5 TEST)
# ---------------------------------------------------------------------------
# Riferimento = media degli ultimi 5 test dello storico (meno se ce ne sono meno):
# un test singolo balla anche del 30 %, la media di 5 e' stabile.
# Ogni valore viene trasformato in "% della media", girato in modo che
# SOPRA 100 = MEGLIO e SOTTO 100 = PEGGIO:
#   piu' alto = meglio (GB/s) ....... ora / media x 100
#   piu' basso = meglio (giri) ...... media / ora x 100
#   steal ........................... CPU disponibile (100 - steal), ora / media x 100
# Esempio: CPU 1.00 -> 0.95 GB/s = 95 %  (5 % sotto).  giro 1.5 -> 1.2 s = 125 %.
# INDICE = media di questi valori. 100 = nella media dei 5 test precedenti.
#   >= 105  MIGLIORATO     95-105  COSTANTE (rumore)     <= 95  PEGGIORATO
# La durata del test non entra nella media (e' quasi tutta l'attesa fissa di 20 s).
#
# ALLARME (in fondo all'output, in MAIUSCOLO): scatta se anche UNA di queste e' vera
#   - steal sotto carico >= 5 %  oppure  steal a riposo >= 1 %
#   - CPU 1 core o CPU tutti i core <= 80 % della media (20 % piu' lenta)
#   - indice medio <= 85 %
# Soglie modificabili in testa al blocco python (SOGLIA_*).
#
# ---------------------------------------------------------------------------
# COS'E' LO STEAL TIME (la cosa piu' importante di questo test)
# ---------------------------------------------------------------------------
# Questo server e' una VPS: una macchina virtuale (KVM) su un server fisico
# del provider, che lo divide tra tanti clienti. Le vCPU della VM sono "prestate"
# dalle CPU fisiche di quell'host.
#
# Steal time = percentuale di tempo in cui la nostra VM voleva usare la CPU
# ma l'hypervisor l'ha data a un'altra VM. E' tempo "rubato" (steal).
# Lo misura il kernel (colonna "st" in top/vmstat, ottavo valore in /proc/stat).
#
# Come leggerlo:
#   steal < 1 %    OK         host tranquillo, le vCPU sono "nostre"
#   steal 1-5 %    ATTENZIONE host condiviso sotto carico, rallentamenti a tratti
#   steal > 5 %    MALE       VPS su host stracarico, da segnalare al provider
# Misurato due volte: a riposo (20 s) e mentre stressa tutte le vCPU (5 s).
# Il valore sotto carico e' quello che dice di piu'.
#
# ---------------------------------------------------------------------------
# CONSIDERAZIONI PER CHI LEGGE I RISULTATI
# ---------------------------------------------------------------------------
# - Un test solo non dice niente: conta l'andamento nello storico (colonna indice).
# - Test di notte sono ottimisti. L'overselling si vede nelle ore di punta
#   (circa 10-13 e 18-22): servono test anche in quelle fasce.
# - CPU tutti i core in calo con CPU 1 core normale e steal 0: possibile host
#   carico che abbassa la frequenza. Se si ripete nello storico, e' un segnale.
# - Prima di dare la colpa all'host guardare "Processi pesanti": altri lavori
#   sulla macchina (trascrizioni, LLM locali, agenti, build) falsano la misura multi-core.
# - Disco: scrittura/lettura da byte/secondi di dd. 4k RANDOM (dal 2026-11-01 08:30):
#   letture da 4 KB in punti casuali su tutto il file da 512 MB, O_DIRECT, una alla
#   volta (queue depth 1) per 3 s: IOPS = latenza del disco. Prima c'era un dd 4k
#   quasi sequenziale (sbagliato): quei valori stanno in disco_4k_GBs e non si confrontano.
# - CPU VECCHIE E NUOVE, INTEL E AMD: prova "base" con OPENSSL_ia32cap=0:0 (nessuna
#   estensione, stesso codice ovunque: confrontabile fra macchine), poi SHA (SHA-NI),
#   AES (AES-NI/VAES) e vettoriale (SSE/AVX2/AVX-512) con quello che la CPU ha.
#   Stampa il livello x86-64 (v1..v4), le estensioni presenti e quelle che mancano.
#   Su CPU senza un'estensione la prova gira lo stesso (in software): niente errori.
# - Versioni di openssl e python nel CSV: un aggiornamento cambia le misure CPU,
#   quindi si confrontano solo test con le stesse versioni.
# - Se una misura CPU/steal fallisce (valore vuoto) il test si ferma e NON scrive nello storico.
#   Il DISCO invece, se fallisce (filesystem senza O_DIRECT: tmpfs, ZFS, NFS, overlayfs),
#   esce n/d e il test va avanti: CPU e steal non si buttano (terza revisione, 1/11).
# - Steal calcolato sulle sole vCPU del test (righe cpuN di /proc/stat): con -c conta
#   solo quelle scelte. In container o con limite cgroup resta quello di tutta la VM (nota).
# - Non misura RAM (overcommit) ne' rete (banda condivisa).
# - OROLOGIO (aggiunto 2026-11-01, utile per incrociare lo storico con un controllo
#   periodico degli orologi): colonne clocksource (kvm-clock/tsc), ntp_sync
#   (yes/no) e drift_raw_mono_s = quanto CLOCK_MONOTONIC_RAW si e' scostato da
#   CLOCK_MONOTONIC durante il test (NTP che corregge la frequenza). Non entrano
#   nell'indice. La durata ora e' misurata con MONOTONIC: una correzione NTP
#   durante il test non la falsa piu' (prima usava date = REALTIME).
# - CPU: lo script NON presume niente. Legge la CPU reale (lscpu): modello, vCPU,
#   core x thread (SMT), limite cgroup/container, e fa il test multi-core con
#   TUTTE le vCPU che trova (nproc) e, se c'e' SMT, anche con i soli core.
#   scala_pct = CPU tutti / (CPU 1 core x vCPU) x 100: quanta potenza reale danno
#   le vCPU rispetto a N core pieni (con SMT 2 thread/core e' normale ~55-65 %).
#   Il confronto con la media usa solo test fatti con la STESSA CPU e lo stesso
#   numero di vCPU e lo stesso limite cgroup (se cambia la VPS, o lo lanci
#   dentro un container limitato, lo storico non viene mischiato).
#   Con limite cgroup la scala e' calcolata sulle CPU concesse, non sulle vCPU.
# - Riferimento 2026-11-01 notte (server di origine: 8 vCPU = 4 core x 2 thread, EPYC Milan):
#   steal 0/0 %, CPU 1 core ~1.06 GB/s, 8 core 5.5-7.0 GB/s, giri 1.4-1.6 s,
#   disco (ext4, /): W ~0.55 GB/s, R ~0.55 GB/s. (I valori vecchi 1.0/4.5 GB/s erano /tmp = RAM.)
# ---------------------------------------------------------------------------
export LC_ALL=C
# --- affinity: -c N (prime N vCPU) o -c lista (es. 0,2,4,6 / 0-3). Rilancia lo script sotto taskset.
aiuto(){ sed -n '/^# Uso:/,/^# Due test/p' "$0" | sed 's/^# \{0,1\}//'; }
ORIG=("$@")
SCELTA=""; X=1; DISKDIR=""; TG=0; NOLOG=0
DISCO=0; XSET=0; ARCHIVIA=0; OUT=()
# >>> FRENO: 9 = minuti minimi fra due test (sotto, si ristampa l'ultimo). 0 = SPENTO per sempre. <<<
# >>> Nominale 10 minuti, cronometro a 9: chi rilancia a 9 minuti e mezzo trova il test nuovo. <<<
FRENO=${MINIBENCH_FRENO:-9}       # per una volta sola: -r 0, oppure MINIBENCH_FRENO=0 minibench.sh
CSV_KB=${MINIBENCH_CSV_KB:-1024}    # oltre questa dimensione lo storico propone il taglio
TIENI=${MINIBENCH_TIENI:-1000}      # righe che -A lascia nello storico
CONFERMA=${MINIBENCH_CONFERMA:-0}   # 1 = questo e' il test lungo di conferma di un possibile allarme
while getopts "c:x:d:o:r:DtnAh" o; do case $o in
  o) OUT+=("$OPTARG");; r) FRENO=$OPTARG;; c) SCELTA=$OPTARG;; x) X=$OPTARG; XSET=1;; d) DISKDIR=$OPTARG; DISCO=1;; D) DISCO=1;; t) TG=1;; n) NOLOG=1;; A) ARCHIVIA=1;;
  h) aiuto; exit 0;; *) aiuto; exit 2;; esac; done
shift $((OPTIND-1))
for f in "${OUT[@]}"; do d=$(dirname "$f"); [ -d "$d" ] && [ -w "$d" -o -w "$f" ] || { echo "-o $f: la cartella $d non esiste o non e' scrivibile"; exit 2; }; done
[[ "$FRENO" =~ ^[0-9]+$ ]] || { echo "-r $FRENO: servono i minuti (0 = freno spento)"; exit 2; }
# ############################################################################
# ##  FRENO SPENTO DEL TUTTO (blocco INATTIVO: per attivarlo togli il "#"   ##
# ##  dalle 2 righe sotto). Ogni lancio fa sempre il test vero, come -r 0,  ##
# ##  e -r / MINIBENCH_FRENO vengono ignorati. Utile se lo script va a      ##
# ##  terzi che fanno tanti campioni di fila e il freno li confonderebbe.   ##
# ############################################################################
# FRENO=0
# echo "(freno spento nel codice: ogni lancio fa il test)" >&2
[[ "$X" =~ ^[0-9]+$ ]] && (( X >= 1 && X <= 1000 )) || { echo "-x $X: serve un numero da 1 a 1000"; exit 2; }
if [ -n "$SCELTA" ] && [ -z "${MINIBENCH_AFFINITY:-}" ]; then
  TOT=$(grep -c ^processor /proc/cpuinfo)
  if [[ "$SCELTA" =~ ^[0-9]+$ ]]; then
    (( SCELTA >= 1 && SCELTA <= TOT )) || { echo "-c $SCELTA: vCPU disponibili 1-$TOT"; exit 2; }
    LISTA="0-$((SCELTA-1))"
  else LISTA=$SCELTA; fi
  command -v taskset >/dev/null || { echo "-c: manca taskset (pacchetto util-linux)"; exit 2; }
  # ogni vCPU della lista deve esistere (taskset da solo accetta 0-20 su 8 vCPU e tace)
  python3 -I -c 'import sys
s,tot=sys.argv[1],int(sys.argv[2]); v=set()
for p in s.split(","):
    a,_,b=p.partition("-"); v.update(range(int(a),int(b or a)+1))
sys.exit(0 if v and max(v)<tot else 1)' "$LISTA" "$TOT" 2>/dev/null \
    && taskset -c "$LISTA" true 2>/dev/null \
    || { echo "-c $LISTA: lista vCPU non valida (vCPU disponibili 0-$((TOT-1)))"; exit 2; }
  MINIBENCH_AFFINITY="$LISTA" exec taskset -c "$LISTA" "$0" "${ORIG[@]}"
fi
# --- -t: tutto l'output dettagliato va via, alla fine si stampa solo il riassunto
SINTESI=""
if (( TG )); then exec 3>&1 1>/dev/null; SINTESI=$(mktemp /tmp/minibench-sintesi.XXXXXX); fi
orologi(){ python3 -I -c 'import time;m=time.clock_gettime(time.CLOCK_MONOTONIC);r=time.clock_gettime(time.CLOCK_MONOTONIC_RAW);print(f"{m:.6f} {r-m:.6f}")'; }
read -r MONO0 RAWD0 < <(orologi)   # inizio: MONOTONIC e (RAW - MONOTONIC)
N=$(nproc); DIR=$(dirname "$(readlink -f "$0")"); LOG="${1:-${DIR%/}/minibench.csv}"
# --- blocco: un test alla volta (due insieme si falsano a vicenda).
# Lucchetto accanto allo storico (non in /tmp, dove chiunque potrebbe crearlo o tenerlo).
# Se la cartella dello storico non e' scrivibile (agenti non root): lucchetto personale.
LOCKDIR=$(dirname "$LOG"); [ -w "$LOCKDIR" ] || LOCKDIR=${XDG_RUNTIME_DIR:-$HOME}
exec 9>"$LOCKDIR/.minibench.lock"
if ! flock -n 9; then echo "Un altro minibench sta girando: aspetto che finisca..." >&2; flock 9; fi
# --- -A: archivia le righe vecchie dello storico e basta (niente test)
if (( ARCHIVIA )); then
  [ -s "$LOG" ] || { echo "storico $LOG vuoto o inesistente: niente da archiviare"; exit 0; }
  python3 -I - "$LOG" "$TIENI" <<'ARCH'
import sys, csv, gzip, os, time
log, tieni = sys.argv[1], int(sys.argv[2])
with open(log, newline="") as fh:
    r = csv.reader(fh); hdr = next(r); righe = list(r)
if len(righe) <= tieni:
    print(f"storico: {len(righe)} test, non oltre {tieni}: niente da archiviare"); sys.exit(0)
vecchie, nuove = righe[:-tieni], righe[-tieni:]
arch = os.path.join(os.path.dirname(os.path.abspath(log)), f"minibench-archivio-{time.strftime('%Y%m%d-%H%M%S')}.csv.gz")
with gzip.open(arch, "wt", newline="") as g:
    w = csv.writer(g); w.writerow(hdr); w.writerows(vecchie)
tmp = log + ".nuovo"
with open(tmp, "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(hdr); w.writerows(nuove)
os.replace(tmp, log)
print(f"archiviati {len(vecchie)} test vecchi in {arch}")
print(f"storico {log}: restano gli ultimi {len(nuove)} test ({os.path.getsize(log)//1024} KB)")
ARCH
  exit $?
fi
# --- FRENO: c'e' gia' un test recente e confrontabile? allora niente test, si mostra quello.
# Dentro il lucchetto: chi aspettava un altro test trova il suo risultato appena fatto.
# Non vale per il test di conferma di un allarme (MINIBENCH_CONFERMA=1).
if (( FRENO > 0 )) && [ "$CONFERMA" != 1 ] && [ -s "$LOG" ]; then
  AFF_ORA=$(taskset -pc $$ 2>/dev/null | sed 's/.*: //')
  if python3 -I - "$LOG" "$FRENO" "$X" "$DISCO" "$AFF_ORA" > "${SINTESI:-/dev/stdout}" <<'FRENO'
import sys, csv, datetime as dt
log, freno, x, disco, aff = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4] == "1", sys.argv[5]
def norm(a):                                   # "0-3" e "0,1,2,3" sono la stessa affinity
    v = set()
    for p in a.replace('"', "").split(","):
        p = p.strip()
        if not p: continue
        a1, _, b1 = p.partition("-"); v.update(range(int(a1), int(b1 or a1) + 1))
    return v
try:
    righe = list(csv.DictReader(open(log, newline="")))
except Exception:
    sys.exit(1)
ora = dt.datetime.now(dt.timezone.utc)
for r in reversed(righe):
    try:
        quando = dt.datetime.fromisoformat(f"{r['giorno_utc']}T{r['ora_utc']}+00:00")
    except Exception:
        continue
    eta = (ora - quando).total_seconds() / 60
    if eta > freno: break                      # le righe prima sono ancora piu' vecchie
    if r.get("x", "1") != x: continue
    if disco and not r.get("disco_scrittura_GBs"): continue
    try:
        if aff and norm(r.get("affinity", "")) != norm(aff): continue
    except ValueError:
        continue
    loc = quando.astimezone(dt.timezone(dt.timedelta(hours=int(r.get("offset_ita") or 1))))
    print(f"🛑 FRENO: test gia' fatto {eta:.0f} min fa (limite {freno} min), non lo rifaccio.")
    print(f"📊 minibench {loc:%d/%m %H:%M} (ora italiana): {r['verdetto']}, indice {r.get('indice_pct') or 'n/d'} %")
    print(f"CPU 1 core {r['cpu1_GBs']} GB/s · tutti {r['cpu_tutti_GBs']} GB/s · steal {r['steal_riposo_pct']}/{r['steal_carico_pct']} %")
    if r.get("disco_scrittura_GBs"):
        print(f"disco scrittura {r['disco_scrittura_GBs']} GB/s · lettura {r['disco_lettura_GBs']} GB/s")
    print("(test nuovo comunque: aggiungi -r 0)")
    sys.exit(0)
sys.exit(1)
FRENO
  then
    [ -n "$SINTESI" ] && { exec 1>&3; cat "$SINTESI"; rm -f "$SINTESI"; }
    exit 0
  fi
fi
DISKFS=""; DW=""; DR=""; D4=""
if (( DISCO )); then
  DISKDIR=${DISKDIR:-$DIR}
  [ -d "$DISKDIR" ] && [ -w "$DISKDIR" ] || { echo "disco: $DISKDIR inesistente o non scrivibile" >&2; exit 2; }
  DISKFS=$(findmnt -n -o FSTYPE --target "$DISKDIR" 2>/dev/null || stat -f -c %T "$DISKDIR" 2>/dev/null || echo n/d)
  LIBERO_MB=$(df -Pm "$DISKDIR" | awk 'NR==2{print $4}')
  (( LIBERO_MB > 700 )) || { echo "disco: in $DISKDIR servono 700 MB liberi, ce ne sono $LIBERO_MB" >&2; exit 2; }
else DISKDIR=""; fi
# steal sommato SOLO sulle vCPU del test (righe cpuN di /proc/stat): con -c 4 conta lo steal di quelle 4,
# non di tutta la macchina. Senza -c le vCPU sono tutte e il risultato e' lo stesso della riga "cpu".
stat_cpu(){ awk -v a=",$AFF," '$1 ~ /^cpu[0-9]+$/ && index(a, "," substr($1,4) ",") {
  for (i=2; i<=9; i++) tot += $i; st += $9 } END { print tot+0, st+0 }' /proc/stat; }
pct(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f",(b>0?100*a/b:0)}'; }
dd_gbs(){ awk -F', ' '/copied/{split($1,b," "); split($3,s," "); if (s[1] > 0) printf "%.2f", b[1]/s[1]/1e9}'; }  # niente output se dd fallisce
# 4k RANDOM vero: letture da 4 KB in posizioni casuali su TUTTO il file, O_DIRECT (niente cache),
# una alla volta (queue depth 1 = misura la latenza del disco). Stampa le IOPS.
rand4k(){ python3 -I - "$1" "$2" <<'R4K'
import os, sys, mmap, random, time
try:
    fd = os.open(sys.argv[1], os.O_RDONLY | os.O_DIRECT)   # tmpfs, ZFS, NFS, overlayfs: puo' non esserci
except Exception:
    sys.exit(0)                                             # niente output = n/d, il test va avanti
blocchi = os.fstat(fd).st_size // 4096
if blocchi == 0: sys.exit(0)              # file vuoto (scrittura fallita): n/d
buf = mmap.mmap(-1, 4096)                 # buffer allineato, richiesto da O_DIRECT
n = 0; t0 = time.monotonic(); fine = t0 + float(sys.argv[2])
while True:
    try: os.preadv(fd, [buf], random.randrange(blocchi) * 4096)
    except Exception: sys.exit(0)
    n += 1
    if time.monotonic() >= fine: break      # ogni lettura: sui dischi lenti (~100 IOPS) non sfora
print(f"{n / (time.monotonic() - t0):.0f}")
R4K
}

lsc(){ LC_ALL=C lscpu 2>/dev/null | awk -F: -v k="$1" '$1==k{sub(/^[ \t]+/,"",$2); print $2; exit}'; }
MODELLO=$(lsc "Model name"); [ -n "$MODELLO" ] || MODELLO=$(awk -F: '/model name/{sub(/^ /,"",$2);print $2;exit}' /proc/cpuinfo)
VCPU_TOT=$(lsc "CPU(s)"); TPC=$(lsc "Thread(s) per core"); CPS=$(lsc "Core(s) per socket"); SOCK=$(lsc "Socket(s)")
TPC=${TPC:-1}; CPS=${CPS:-$N}; SOCK=${SOCK:-1}; CORE_SIS=$((CPS * SOCK))
# vCPU su cui gira il test (affinity) e quanti core reali diversi coprono
AFF=$(python3 -I -c 'import os;s=sorted(os.sched_getaffinity(0));print(",".join(map(str,s)))')
CORE=$(LC_ALL=C lscpu -p=CPU,CORE,SOCKET 2>/dev/null | grep -v '^#' | awk -F, -v a="$AFF" 'BEGIN{n=split(a,x,",");for(i=1;i<=n;i++)ok[x[i]]=1} ($1 in ok){c[$3","$2]=1} END{k=0;for(i in c)k++;print k}')
[ "${CORE:-0}" -gt 0 ] || CORE=$N
# limite CPU del cgroup (docker/systemd CPUQuota): cpu.max = "quota periodo" o "max periodo"
LIMITE="nessuno"; cg=$(awk -F: '$1=="0"{print $3}' /proc/self/cgroup 2>/dev/null)
while [ -n "$cg" ]; do
  if [ -r "/sys/fs/cgroup$cg/cpu.max" ]; then read -r q per < "/sys/fs/cgroup$cg/cpu.max"
    [ "$q" != "max" ] && { LIMITE=$(awk -v q="$q" -v p="$per" 'BEGIN{printf "%.2f", q/p}'); break; }; fi
  [ "$cg" = "/" ] && break; cg=$(dirname "$cg")
done
# Estensioni CPU: stessi nomi su Intel e AMD. Livello x86-64: v1 (vecchie) ... v4 (AVX-512)
CPUFLAGS=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2) "
ha(){ for f in "$@"; do [[ "$CPUFLAGS" == *" $f "* ]] || return 1; done; }
LIVELLO="n/d"
if [ "$(uname -m)" = x86_64 ]; then LIVELLO="v1"
  ha cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3 && LIVELLO="v2"
  [ "$LIVELLO" = v2 ] && ha avx avx2 bmi1 bmi2 f16c fma abm movbe xsave && LIVELLO="v3"
  [ "$LIVELLO" = v3 ] && ha avx512f avx512bw avx512cd avx512dq avx512vl && LIVELLO="v4"
fi
FLAG=""; MANCA=""
for f in sse4_2 aes sha_ni avx avx2 avx512f vaes vpclmulqdq avx512_vnni avx_vnni gfni amx_tile; do
  if ha "$f"; then FLAG="$FLAG $f"; else MANCA="$MANCA $f"; fi; done
FLAG=${FLAG# }; MANCA=${MANCA# }
VETT="SSE"; ha avx && VETT="AVX"; ha avx2 && VETT="AVX2"; ha avx512f && VETT="AVX-512"
echo "== CPU REALE (letta dal sistema, niente valori fissi)"
echo "modello:      $MODELLO"
echo "sistema:      $SOCK socket x $CPS core x $TPC thread = $CORE_SIS core, $VCPU_TOT vCPU$( [ "$TPC" -gt 1 ] && echo '  (SMT/hyperthreading: 2 vCPU = 1 core)')"
echo "test su:      $N vCPU [$AFF] = $CORE core reali$( [ -n "${MINIBENCH_AFFINITY:-}" ] && echo "  (affinity scelta: -c ${MINIBENCH_AFFINITY})")"
echo "limite cgroup: $LIMITE$( [ "$LIMITE" != nessuno ] && echo ' CPU (container o servizio limitato: il multi-core non puo superarlo)')"
echo "livello:      x86-64-$LIVELLO  (v1 = CPU vecchie, v2 ~2009, v3 = AVX2 ~2015, v4 = AVX-512)"
echo "istruzioni:   ${FLAG:-nessuna}   hypervisor: $(systemd-detect-virt 2>/dev/null || echo n/d)"
echo "mancano:      ${MANCA:-nessuna}"
echo "RAM:          $(free -h | awk '/Mem/{print $2}')"
CONT=$(systemd-detect-virt --container 2>/dev/null || true); CONT=${CONT:-none}
OSSL=$(openssl version 2>/dev/null | awk '{print $2}'); PYV=$(python3 -I -c 'import platform;print(platform.python_version())')
echo "strumenti:    openssl ${OSSL:-?}  python ${PYV:-?}  (se cambiano, lo storico riparte: vedi confronto)"
if [ "$CONT" != none ] || [ "$LIMITE" != nessuno ]; then
  echo "  NOTA STEAL: $( [ "$CONT" != none ] && echo "dentro un container ($CONT)" || echo "con limite cgroup") lo steal letto da /proc/stat"
  echo "  e' quello di TUTTA la VM, non della tua quota: non attribuirlo al tuo processo."
fi
LOAD=$(cut -d' ' -f1 /proc/loadavg); echo "load attuale: $(cut -d' ' -f1-3 /proc/loadavg)"

(( X > 1 )) && { echo; echo "== TEST LUNGO x$X: tempi, giri e passate disco moltiplicati per $X (~$((20 * X)) s)"; }
echo; echo "== STEAL a riposo ($((5 * X)) s, sulle $N vCPU del test)"
read -r t1 s1 < <(stat_cpu); sleep $((5 * X)); read -r t2 s2 < <(stat_cpu)
ST0=$(pct $((s2-s1)) $((t2-t1))); echo "steal a riposo:       $ST0 %"

echo; echo "== CPU 1 core (openssl sha256, $((3 * X)) s)"
C1=$(openssl speed -seconds $((3 * X)) -bytes 16384 sha256 2>/dev/null | awk '/^sha256/{v=$NF; sub(/k$/,"",v); printf "%.2f", v/1e6}')
echo "CPU 1 core:           $C1 GB/s"

# Stesse prove su 1 core, per CPU vecchie e nuove, Intel e AMD:
#  base  = sha256 con OPENSSL_ia32cap=0:0 -> OpenSSL NON usa nessuna estensione: stesso codice su
#          ogni CPU x86. E' l'unico numero confrontabile fra macchine diverse.
#  SHA   = sha256 nativo (SHA-NI se c'e')  = "CPU 1 core" sopra
#  AES   = aes-128-gcm nativo (AES-NI, VAES+VPCLMULQDQ sulle ultime)
#  vett  = chacha20-poly1305 nativo (SSE / AVX2 / AVX-512: la piu' larga disponibile)
ossl(){ awk 'NF{l=$0} END{n=split(l,a," "); v=a[n]; sub(/k$/,"",v); printf "%.2f", v/1e6}'; }
echo; echo "== ISTRUZIONI CPU (1 core, $((1 * X)) s ciascuna)"
CB=$(OPENSSL_ia32cap=0:0 openssl speed -seconds $((1 * X)) -bytes 16384 sha256 2>/dev/null | ossl)
CA=$(openssl speed -seconds $((1 * X)) -bytes 16384 -evp aes-128-gcm 2>/dev/null | ossl)
CV=$(openssl speed -seconds $((1 * X)) -bytes 16384 -evp chacha20-poly1305 2>/dev/null | ossl)
per(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", (b>0 ? a/b : 0)}'; }
echo "base (nessuna estensione): $CB GB/s   <- confrontabile fra CPU diverse"
echo "SHA  ($(ha sha_ni && echo SHA-NI || echo 'software, niente SHA-NI')):  $C1 GB/s   x$(per "$C1" "$CB") rispetto alla base"
echo "AES  ($(ha vaes vpclmulqdq && echo 'AES-NI + VAES' || { ha aes && echo AES-NI || echo 'software, niente AES-NI'; })):  $CA GB/s"
echo "vett ($VETT):  $CV GB/s"

echo; echo "== CPU tutti i core ($N processi, $((3 * X)) s) + steal sotto carico"
read -r t1 s1 < <(stat_cpu)
CN=$(openssl speed -seconds $((3 * X)) -bytes 16384 -multi $N sha256 2>/dev/null | awk '/^sha256/{v=$NF; sub(/k$/,"",v); printf "%.2f", v/1e6}')
read -r t2 s2 < <(stat_cpu)
ST1=$(pct $((s2-s1)) $((t2-t1)))
echo "CPU tutti i core:     $CN GB/s  ($N vCPU)"; echo "steal sotto carico:   $ST1 %"
CC=""
if [ "$TPC" -gt 1 ] && [ "$CORE" -lt "$N" ]; then
  echo; echo "== CPU solo core reali ($CORE processi, $((3 * X)) s): quanto rende l'SMT"
  CC=$(openssl speed -seconds $((3 * X)) -bytes 16384 -multi $CORE sha256 2>/dev/null | awk '/^sha256/{v=$NF; sub(/k$/,"",v); printf "%.2f", v/1e6}')
  echo "CPU $CORE core:            $CC GB/s   -> con SMT ($N vCPU): $CN GB/s  ($(awk -v a="$CC" -v b="$CN" 'BEGIN{printf "%+.0f",(a>0?(b/a-1)*100:0)}') %)"
fi
# CPU concesse davvero: le vCPU, o meno se c'e' un limite cgroup
NEFF=$(awk -v n="$N" -v l="$LIMITE" 'BEGIN{if(l!="nessuno" && l+0<n) printf "%.2f",l; else print n}')
SCALA=$(awk -v c1="$C1" -v cn="$CN" -v n="$NEFF" 'BEGIN{printf "%.1f",(c1>0?cn/(c1*n)*100:0)}')
echo "scala:                $SCALA %  (CPU tutti / (CPU 1 core x $NEFF CPU concesse): 100 % = ogni CPU vale un core pieno)"
[ "$LIMITE" != nessuno ] && echo "  NOTA: limite cgroup $LIMITE CPU: il multi-core misura il LIMITE, non la macchina"

echo; echo "== CONSISTENZA CPU ($((3 * X)) giri uguali, 1 core)"
GIRI=""; for k in $(seq 1 $((3 * X))); do g=$(/usr/bin/env python3 -I -c "
import time;t=time.perf_counter();x=0
for i in range(6_000_000): x+=i*i
print(f'{time.perf_counter()-t:.3f}')"); echo "giro $k: $g s"; GIRI="$GIRI $g"; done
GMIN=$(echo $GIRI | tr ' ' '\n' | sort -n | head -1); GMAX=$(echo $GIRI | tr ' ' '\n' | sort -n | tail -1)

if (( DISCO )); then
  echo; echo "== DISCO (512 MB, diretto, senza cache) in $DISKDIR [$DISKFS]$( (( X > 1 )) && echo ", $X passate, mediana")"
  [ "$DISKFS" = tmpfs ] && echo "  ATTENZIONE: $DISKDIR e' tmpfs = RAM. Questo NON e' il disco: usa -d su una cartella del disco."
  mediana(){ tr ' ' '\n' | grep . | sort -n | awk '{v[NR]=$1} END{if(NR==0) exit; if(NR%2) print v[(NR+1)/2]; else printf "%.2f\n",(v[NR/2]+v[NR/2+1])/2}'; }
  F=$(mktemp "$DISKDIR/.minibench-disco.XXXXXX"); trap 'rm -f "$F"' EXIT
  LW=""; LR=""; L4=""
  for k in $(seq 1 $X); do
    LW="$LW $(dd if=/dev/zero of="$F" bs=1M count=512 oflag=direct conv=fsync 2>&1 | dd_gbs)"
    LR="$LR $(dd if="$F" of=/dev/null bs=1M iflag=direct 2>&1 | dd_gbs)"
    L4="$L4 $(rand4k "$F" 1)"
  done
  DW=$(echo $LW | mediana); DR=$(echo $LR | mediana); D4=$(echo $L4 | mediana)
  echo "scrittura:            ${DW:-n/d} GB/s"; echo "lettura:              ${DR:-n/d} GB/s"
  if [ -n "$D4" ]; then
    echo "4k random:            $D4 IOPS  (= $(awk -v i="$D4" 'BEGIN{printf "%.1f", i*4096/1e6}') MB/s; letture da 4 KB in punti casuali, una alla volta)"
  else echo "4k random:            n/d"; fi
  [ -n "$DW" ] && [ -n "$DR" ] && [ -n "$D4" ] || echo "  NOTA DISCO: una o piu' misure n/d: probabilmente $DISKFS non supporta O_DIRECT. CPU e steal valgono lo stesso."
  rm -f "$F"
else
  echo; echo "== DISCO: saltato (di default non si fa; -D = nella cartella dello script, -d DIR = altrove)"
fi

echo; echo "== Processi pesanti in questo momento"; ps -eo pcpu,rss,comm --sort=-pcpu | head -6
read -r MONO1 RAWD1 < <(orologi)   # fine
DUR=$(awk -v a="$MONO0" -v b="$MONO1" 'BEGIN{printf "%.1f",b-a}')
CLKSRC=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null || echo n/d)
NTP=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo n/d)
DRIFT=$(awk -v a="$RAWD0" -v b="$RAWD1" 'BEGIN{printf "%.6f",b-a}')
echo; echo "== OROLOGIO (come sono misurati i tempi)"
echo "clocksource: $CLKSRC   NTP sincronizzato: $NTP   drift RAW-MONOTONIC nel test: $DRIFT s"
echo "  Tempi misurati con orologi MONOTONIC, non con l'ora di sistema:"
echo "  - REALTIME (date) = ora del giorno: NTP la puo' spostare avanti/indietro"
echo "    in qualsiasi momento -> una durata calcolata con date puo' venire falsa."
echo "  - MONOTONIC = contatore che parte dall'avvio e va SOLO avanti, mai salti:"
echo "    NTP puo' solo rallentarlo/accelerarlo di poco (ppm). Giusto per le durate."
echo "  - MONOTONIC_RAW = come MONOTONIC ma senza nessuna correzione NTP: e' il"
echo "    quarzo/hypervisor nudo. RAW - MONOTONIC = quanto NTP sta correggendo."
echo "  Durata test e giri CPU: MONOTONIC (perf_counter). Data/ora nel CSV: UTC dal kernel."
echo "  drift quasi 0 (< 0.001 s) = orologio stabile, misure attendibili."

# --- misure valide? Se uno strumento fallisce, niente righe sporche nello storico
# il disco NON e' in elenco: se manca resta n/d e il test va avanti (CPU e steal non si buttano)
MISURE="C1 CN CB CA CV GMIN GMAX ST0 ST1 DUR"
for v in $MISURE; do
  [[ "${!v}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ERRORE: misura $v non valida ('${!v}'): test interrotto, storico NON scritto" >&2; exit 3; }
done
V=$(awk -v a="$ST0" -v b="$ST1" 'BEGIN{m=(a>b?a:b); if(m<1) print "OK"; else if(m<5) print "ATTENZIONE"; else print "MALE"}')
echo; echo "== VERDETTO STEAL"
case $V in OK) echo "OK: host non sovraccarico (steal < 1%)";; ATTENZIONE) echo "ATTENZIONE: host condiviso sotto carico (steal 1-5%)";; *) echo "MALE: VPS su host stracarico (steal > 5%)";; esac

# --- confronto con la media degli ultimi 5 test (indice %) e scrittura storico ---
MB_OUT=$(printf '%s\n' "${OUT[@]}") MB_XSET=$XSET MB_CSV_KB=$CSV_KB MB_TIENI=$TIENI python3 -I - "$LOG" "$(date -u +%F)" "$(date -u +%T)" "$(TZ=Europe/Rome date +%:::z | sed 's/^\([+-]\)0/\1/')" \
  "$V" "$C1" "$CN" "$GMIN" "$GMAX" "$DW" "$DR" "$D4" "$ST0" "$ST1" "$DUR" "$CLKSRC" "$NTP" "$DRIFT" "$LOAD" "$N" \
  "$CC" "$SCALA" "$MODELLO" "$CORE" "$TPC" "$LIMITE" "$VCPU_TOT" "$CORE_SIS" "$AFF" "$X" "$DISKFS" "$DISKDIR" \
  "$OSSL" "$PYV" "$CONT" "$CB" "$CA" "$CV" "$LIVELLO" "$FLAG" 3 "$CONFERMA" "$NOLOG" "$SINTESI" <<'PY'
import sys, os, csv
log = sys.argv[1]
COLS = ["giorno_utc","ora_utc","offset_ita","verdetto","indice_pct",
        "cpu1_GBs","cpu_tutti_GBs","disco_scrittura_GBs","disco_lettura_GBs","disco_4k_GBs",
        "giro_min_s","giro_max_s",
        "steal_riposo_pct","steal_carico_pct","durata_s","clocksource","ntp_sync","drift_raw_mono_s","load1","vcpu",
        "cpu_core_GBs","scala_pct","cpu_modello","core","thread_per_core","limite_cgroup",
        "vcpu_sistema","core_sistema","affinity","x","disco_fs","disco_dir",
        "disco_4k_iops","openssl_ver","python_ver","container",
        "cpu1_base_GBs","aes_GBs","vett_GBs","x86_livello","cpu_flag","schema","conferma"]
# ordine degli argomenti passati da bash
ARG = ["giorno_utc","ora_utc","offset_ita","verdetto","cpu1_GBs","cpu_tutti_GBs","giro_min_s","giro_max_s",
       "disco_scrittura_GBs","disco_lettura_GBs","disco_4k_GBs","steal_riposo_pct","steal_carico_pct","durata_s",
       "clocksource","ntp_sync","drift_raw_mono_s","load1","vcpu",
       "cpu_core_GBs","scala_pct","cpu_modello","core","thread_per_core","limite_cgroup",
       "vcpu_sistema","core_sistema","affinity","x","disco_fs","disco_dir",
       "openssl_ver","python_ver","container",
       "cpu1_base_GBs","aes_GBs","vett_GBs","x86_livello","cpu_flag","schema","conferma"]
cur = dict(zip(ARG, sys.argv[2:2+len(ARG)]))
# disco_4k: ora e' 4k RANDOM in IOPS (colonna nuova); la vecchia disco_4k_GBs (sequenziale, sbagliata) resta vuota
cur["disco_4k_iops"] = cur.pop("disco_4k_GBs"); cur["disco_4k_GBs"] = ""
NOLOG = sys.argv[2+len(ARG)] == "1"; SINTESI = sys.argv[3+len(ARG)]
# raggruppate per unita': prima GB/s, poi secondi, poi %
# gruppo, metrica, colonna, modo: 'alto' = piu' alto meglio, 'basso' = piu' basso meglio, 'steal'
METRICHE = [("GB/s  (piu alto = meglio)","CPU 1 core","cpu1_GBs","alto"), (None,"CPU tutti i core","cpu_tutti_GBs","alto"),
            (None,"disco scrittura","disco_scrittura_GBs","alto"), (None,"disco lettura","disco_lettura_GBs","alto"),
            ("IOPS  (piu alto = meglio)","disco 4k random","disco_4k_iops","alto"),
            ("secondi  (piu basso = meglio)","giro CPU piu veloce","giro_min_s","basso"), (None,"giro CPU piu lento","giro_max_s","basso"),
            ("% steal  (piu basso = meglio)","steal a riposo","steal_riposo_pct","steal"), (None,"steal sotto carico","steal_carico_pct","steal")]
def f(x):
    try: return float(x)
    except Exception: return None
def indice(a, b, modo):
    if a is None or b is None: return None
    if modo == "steal": a, b = 100 - a, 100 - b
    if modo == "basso": a, b = b, a
    return None if a <= 0 else b / a * 100
def esito(i): return "MIGLIORATO" if i >= 105 else "PEGGIORATO" if i <= 95 else "COSTANTE"

N_RIF = 5   # quanti test precedenti fanno la media di riferimento
SOGLIA_STEAL_CARICO = 5.0   # %  steal sotto carico da allarme
SOGLIA_STEAL_RIPOSO = 1.0   # %  steal a riposo da allarme
SOGLIA_CPU = 80.0           # %  indice CPU (1 core o tutti) da allarme
SOGLIA_INDICE = 85.0        # %  indice medio da allarme
MIN_RIF_ALLARME = 3         # allarmi CPU/indice solo con almeno 3 test di riferimento (1 solo = rumore)
allarmi = []
brevi = []      # stessi allarmi, scritti corti per il telefono (-t)
righe = []
if os.path.exists(log) and os.path.getsize(log) > 0:
    with open(log, newline="") as fh: righe = list(csv.DictReader(fh))
# solo test fatti con la stessa CPU e lo stesso numero di vCPU (righe vecchie senza modello: conta solo vcpu)
stessa = [r for r in righe if r.get("vcpu") == cur["vcpu"] and r.get("cpu_modello", "") in ("", cur["cpu_modello"])
          and r.get("limite_cgroup", "nessuno") in ("", cur["limite_cgroup"])
          and r.get("affinity", "") in ("", cur["affinity"])
          and (r.get("x") or "1") == ("1" if cur["conferma"] == "1" else cur["x"])
          and r.get("conferma", "") != "1"
          and (r.get("schema") or "1") == cur["schema"]
          and r.get("openssl_ver", "") in ("", cur["openssl_ver"])
          and r.get("python_ver", "") in ("", cur["python_ver"])]
if len(stessa) < len(righe):
    print(f"\nNOTA: {len(righe)-len(stessa)} test dello storico non confrontabili (CPU, vCPU, affinity, limite, -x, schema o versioni openssl/python): esclusi")
rif = stessa[-N_RIF:]
# disco: solo test che l'hanno misurato, sullo stesso tipo di filesystem, col 4k random nuovo
rif_disco = [r for r in stessa if r.get("disco_4k_iops") and r.get("disco_fs") == cur["disco_fs"]][-N_RIF:]
def media(col):
    base = rif_disco if col.startswith("disco_") else rif
    v = [x for x in (f(r.get(col)) for r in base) if x is not None]
    return sum(v) / len(v) if v else None
prev = {c: media(c) for c in COLS[5:]} if rif else None
print(f"\n== CONFRONTO CON LA MEDIA DEGLI ULTIMI {N_RIF} TEST  (100 % = nella media, sopra = meglio, sotto = peggio)")
if not prev:
    print("primo test: niente da confrontare"); cur["indice_pct"] = ""
else:
    print(f"media di {len(rif)} test: dal {rif[0]['giorno_utc']} {rif[0]['ora_utc']} al {rif[-1]['giorno_utc']} {rif[-1]['ora_utc']} UTC")
    UNITA = {"alto": "GB/s", "basso": "s", "steal": "%"}
    print(f"  {'':22s}{'media':>12s}{'ora':>14s}{'indice':>12s}")
    vals = []
    for gruppo, nome, col, modo in METRICHE:
        if col.startswith("disco_") and not cur["disco_fs"]: continue   # disco non misurato (niente -D)
        if gruppo: print(f"  -- {gruppo}")
        a, b = prev.get(col), f(cur[col]); i = indice(a, b, modo)
        if i is None: print(f"  {nome:22s}{'n/d':>12s}"); continue
        vals.append(i); u = "IOPS" if col == "disco_4k_iops" else UNITA[modo]
        if col in ("cpu1_GBs", "cpu_tutti_GBs") and i <= SOGLIA_CPU and len(rif) >= MIN_RIF_ALLARME:
            allarmi.append(f"{nome.upper()} AL {i:.0f} % DELLA MEDIA ({b:.2f} GB/s INVECE DI {a:.2f})")
            brevi.append(f"{nome}: {i:.0f} % della media")
        dec = 0 if u == "IOPS" else 2
        print(f"  {nome:22s}{a:>7.{dec}f} {u:<4s}  {b:>7.{dec}f} {u:<4s}  {i:>7.1f} %  {esito(i)}")
    righe_istr = [("base (senza estensioni)","cpu1_base_GBs"),("AES","aes_GBs"),("vettoriale","vett_GBs")]
    if any(prev.get(c) for _, c in righe_istr): print("  -- istruzioni CPU, 1 core (GB/s, non in media)")
    for nome, col in righe_istr:
        a, b = prev.get(col), f(cur[col]); i = indice(a, b, "alto")
        if i is not None: print(f"  {nome:22s}{a:>7.2f} GB/s  {b:>7.2f} GB/s  {i:>7.1f} %  {esito(i)}")
    a, b = prev.get("durata_s"), f(cur["durata_s"])
    if a and b: print(f"  -- non in media\n  {'durata test':22s}{a:>7.1f} {'s':<4s}  {b:>7.1f} {'s':<4s}")
    if vals:
        m = sum(vals) / len(vals); cur["indice_pct"] = f"{m:.1f}"
        d = m - 100
        verso = "SOPRA" if d > 0 else "SOTTO" if d < 0 else "PARI A"
        print(f"\n  INDICE MEDIO: {m:.1f} %  ->  {abs(d):.1f} % {verso} la media degli ultimi {len(rif)} test  ({esito(m)}, {len(vals)} valori)")
        if len(rif) < MIN_RIF_ALLARME:
            print(f"  (allarmi CPU/indice spenti: solo {len(rif)} test di riferimento, ne servono {MIN_RIF_ALLARME})")
        elif m <= SOGLIA_INDICE:
            allarmi.append(f"INDICE MEDIO AL {m:.1f} % ({abs(d):.1f} % SOTTO LA MEDIA)"); brevi.append(f"indice: {m:.0f} %")
    else: cur["indice_pct"] = ""

st0, st1 = f(cur["steal_riposo_pct"]), f(cur["steal_carico_pct"])
if st1 is not None and st1 >= SOGLIA_STEAL_CARICO:
    allarmi.append(f"STEAL SOTTO CARICO {st1:.2f} % (SOGLIA {SOGLIA_STEAL_CARICO:.0f} %)"); brevi.append(f"steal sotto carico: {st1:.1f} %")
if st0 is not None and st0 >= SOGLIA_STEAL_RIPOSO:
    allarmi.append(f"STEAL A RIPOSO {st0:.2f} % (SOGLIA {SOGLIA_STEAL_RIPOSO:.0f} %)"); brevi.append(f"steal a riposo: {st0:.1f} %")
# storico troppo grande? si PROPONE il taglio (-A), non si fa da solo
proposta = ""
if os.path.exists(log):
    kb = os.path.getsize(log) // 1024
    if kb > int(os.environ.get("MB_CSV_KB", "1024")):
        proposta = f"storico {kb} KB ({len(righe)} test): proposta di archiviare le righe vecchie con -A"
DA_CONFERMARE = allarmi and cur["x"] == "1" and cur["conferma"] != "1" and os.environ.get("MB_XSET") == "0"
if DA_CONFERMARE:
    print("\n" + "?" * 70)
    print("??? POSSIBILE ALLARME (test veloce, puo' essere rumore):")
    for a in allarmi: print("??? - " + a)
    print("??? NON lo mando: ripeto il test piu' lungo (x3) per capire se e' vero.")
    print("?" * 70)
    sys.exit(10)                     # niente riassunto, niente storico: decide il test di conferma
if not allarmi and cur["conferma"] == "1":
    print("\n=== Allarme del test veloce NON confermato dal test lungo x3: era rumore. ===")
if allarmi:
    print("\n" + "!" * 70)
    print("!!! ALLARME" + (" CONFERMATO dal test lungo x3" if cur["conferma"] == "1" else "") + ": CI STANNO A INCULA' LA CPU !!!")
    for a in allarmi: print("!!! - " + a)
    print("!!! Prima guardare 'Processi pesanti' (altri lavori sulla macchina).")
    print("!!! Se non e' roba nostra: ripetere il test; se si ripete, segnalare al provider.")
    print("!" * 70)

# --- riassunto breve (-t) per Telegram/WhatsApp: un dato per riga, righe corte (telefono),
# niente simboli che Telegram interpreta (*, _, `), virgola decimale all'italiana.
if SINTESI:
    it = lambda v: (v or "n/d").replace(".", ",")
    g, o = cur["giorno_utc"].split("-"), cur["ora_utc"][:5]
    ind = cur.get("indice_pct") or ""
    icona = {"OK": "✅", "ATTENZIONE": "⚠️", "MALE": "🔴"}.get(cur["verdetto"], "")
    s = [f"📊 minibench {g[2]}/{g[1]} {o} UTC" + (f" (x{cur['x']})" if cur["x"] != "1" else ""),
         f"{icona} {cur['verdetto']}" + (f", indice {it(ind)} %" if ind else ", primo test"),
         "",
         f"Steal: {it(cur['steal_riposo_pct'])} % / {it(cur['steal_carico_pct'])} %",
         f"CPU 1 core: {it(cur['cpu1_GBs'])} GB/s",
         f"CPU {cur['vcpu']} vCPU: {it(cur['cpu_tutti_GBs'])} GB/s",
         f"Scala: {it(cur['scala_pct'])} %",
         f"Base: {it(cur['cpu1_base_GBs'])} GB/s ({cur['x86_livello']})",
         f"AES: {it(cur['aes_GBs'])} GB/s",
         f"Vett: {it(cur['vett_GBs'])} GB/s"]
    if cur["disco_fs"]:
        s += [f"Disco W: {it(cur['disco_scrittura_GBs'])} GB/s", f"Disco R: {it(cur['disco_lettura_GBs'])} GB/s",
              f"Disco 4k: {cur['disco_4k_iops'] or 'n/d'} IOPS"]
        if cur["disco_fs"] == "tmpfs": s.append("⚠️ disco in RAM (tmpfs)")
    else: s.append("Disco: non misurato")
    if cur["container"] != "none": s.append("⚠️ container: steal di tutta la VM")
    s.append("")
    if allarmi:
        s.append("🚨 ALLARME CONFERMATO (x3)" if cur["conferma"] == "1" else "🚨 ALLARME")
        s += ["• " + b for b in brevi]
    elif cur["conferma"] == "1":
        s.append("✅ allarme non confermato: era rumore")
    else:
        s.append("✅ nessun allarme")
    if proposta: s += ["", "📦 Storico grande: " + str(os.path.getsize(log)//1024) + " KB", "Proposta: archiviare con -A"]
    open(SINTESI, "w").write("\n".join(s) + "\n")

if NOLOG:
    print("storico: NON scritto (-n)")
    if proposta: print(f"\n📦 PROPOSTA: {proposta}.")
    sys.exit(0)
nuovo = not righe
if righe and list(righe[0].keys()) != COLS:
    print(f"ATTENZIONE: intestazione di {log} diversa dal formato attuale, riga non aggiunta"); sys.exit(0)
with open(log, "a", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=COLS)
    if nuovo: w.writeheader()
    w.writerow(cur)
print(f"storico: riga aggiunta a {log} ({len(righe)+1} test)")
# -o: stessa riga anche negli altri file (saltato se e' lo storico stesso o un link a lui)
fatti = {os.path.realpath(log)}
for extra in filter(None, os.environ.get("MB_OUT", "").split("\n")):
    vero = os.path.realpath(extra)
    if vero == os.path.realpath(log):
        print(f"   -o {extra}: e' lo storico (o un link a lui), saltato"); continue
    if vero in fatti:
        print(f"   -o {extra}: gia' scritto in questo test, saltato"); continue
    fatti.add(vero)
    try:
        hdr = None
        if os.path.exists(extra) and os.path.getsize(extra) > 0:
            with open(extra, newline="") as fh: hdr = next(csv.reader(fh), None)
        if hdr is not None and hdr != COLS:
            print(f"   -o {extra}: intestazione diversa dal formato attuale, riga NON aggiunta"); continue
        with open(extra, "a", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=COLS)
            if hdr is None: w.writeheader()
            w.writerow(cur)
        print(f"   -o {extra}: riga aggiunta")
    except OSError as e:
        print(f"   -o {extra}: NON scritto ({e.strerror})")
if proposta:
    print(f"\n📦 PROPOSTA: {proposta}.")
    print(f"   minibench.sh -A  sposta le righe vecchie in minibench-archivio-DATA.csv.gz e tiene le ultime {os.environ.get('MB_TIENI','1000')}.")
PY
RC=$?
if [ "$RC" = 10 ]; then
  # possibile allarme nel test veloce: rilancio tutto con -x 3, confrontato con lo stesso storico
  [ -n "$SINTESI" ] && { rm -f "$SINTESI"; exec 1>&3; }
  (( TG )) && echo "⏳ possibile allarme nel test veloce: verifico con un test lungo (x3, ~1 min)..."
  exec 9>&-                                   # rilascio il lucchetto: lo riprende il test di conferma
  MINIBENCH_CONFERMA=1 exec "$0" -x 3 "${ORIG[@]}"
fi
if [ -n "$SINTESI" ]; then cat "$SINTESI" >&3; rm -f "$SINTESI"; fi
exit 0
