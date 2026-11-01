#!/bin/bash
# minibench - mini benchmark VPS: steal time, CPU single/multi, consistenza, disco.
# ATTENZIONE: nato su un server preciso (VPS) - DA AGGIUSTARE PER IL WEB, vedi README.md
# Non modifica il sistema. Durata ~37 s.
# Storico: ogni lancio aggiunge una riga a minibench.csv ACCANTO ALLO SCRIPT
# (stessa cartella del .sh).
# Uso:  minibench.sh                    tutte le vCPU, storico accanto allo script
#       minibench.sh -c 4               solo le prime 4 vCPU (affinity con taskset)
#       minibench.sh -c 0,2,4,6         vCPU scelte a mano (qui: 1 per core, niente SMT)
#       minibench.sh [-c ...] file.csv  storico in un altro file
#   lscpu -e mostra quali vCPU stanno sullo stesso core (stesso valore CORE).
#
# ---------------------------------------------------------------------------
# AFFINITY SPIEGATA SEMPLICE (-c)
# ---------------------------------------------------------------------------
# Cos'e': dire al sistema "questo programma puo' girare SOLO su queste vCPU".
#   Senza -c il test usa tutte le vCPU. Con -c lo chiudi in un recinto.
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
# - Disco: ora calcolato da byte/secondi di dd (preciso), non piu' arrotondato.
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
#   disco W 0.83-1.0 GB/s, R 3.4-5.3 GB/s, 4k 0.9-1.4 GB/s, durata ~37 s.
# ---------------------------------------------------------------------------
export LC_ALL=C
# --- affinity: -c N (prime N vCPU) o -c lista (es. 0,2,4,6 / 0-3). Rilancia lo script sotto taskset.
SCELTA=""
while getopts "c:" o; do case $o in c) SCELTA=$OPTARG;; *) echo "uso: $0 [-c N|lista] [file.csv]"; exit 2;; esac; done
shift $((OPTIND-1))
if [ -n "$SCELTA" ] && [ -z "${MINIBENCH_AFFINITY:-}" ]; then
  TOT=$(grep -c ^processor /proc/cpuinfo)
  if [[ "$SCELTA" =~ ^[0-9]+$ ]]; then
    (( SCELTA >= 1 && SCELTA <= TOT )) || { echo "-c $SCELTA: vCPU disponibili 1-$TOT"; exit 2; }
    LISTA="0-$((SCELTA-1))"
  else LISTA=$SCELTA; fi
  MINIBENCH_AFFINITY="$LISTA" exec taskset -c "$LISTA" "$0" "$@" || { echo "taskset -c $LISTA fallito"; exit 2; }
fi
orologi(){ python3 -I -c 'import time;m=time.clock_gettime(time.CLOCK_MONOTONIC);r=time.clock_gettime(time.CLOCK_MONOTONIC_RAW);print(f"{m:.6f} {r-m:.6f}")'; }
read -r MONO0 RAWD0 < <(orologi)   # inizio: MONOTONIC e (RAW - MONOTONIC)
N=$(nproc); DIR=$(dirname "$(readlink -f "$0")"); LOG="${1:-${DIR%/}/minibench.csv}"
stat_cpu(){ read -r _ u n s i w q sq st _ < <(grep '^cpu ' /proc/stat); echo "$((u+n+s+i+w+q+sq+st)) $st"; }
pct(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f",(b>0?100*a/b:0)}'; }
dd_gbs(){ tail -1 | awk -F', ' '{split($1,b," "); split($3,s," "); printf "%.2f", b[1]/s[1]/1e9}'; }

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
FLAG=$(grep -m1 -o -w -E 'avx512f|avx2|sha_ni|aes' /proc/cpuinfo | sort -u | tr '\n' ' ')
echo "== CPU REALE (letta dal sistema, niente valori fissi)"
echo "modello:      $MODELLO"
echo "sistema:      $SOCK socket x $CPS core x $TPC thread = $CORE_SIS core, $VCPU_TOT vCPU$( [ "$TPC" -gt 1 ] && echo '  (SMT/hyperthreading: 2 vCPU = 1 core)')"
echo "test su:      $N vCPU [$AFF] = $CORE core reali$( [ -n "${MINIBENCH_AFFINITY:-}" ] && echo "  (affinity scelta: -c ${MINIBENCH_AFFINITY})")"
echo "limite cgroup: $LIMITE$( [ "$LIMITE" != nessuno ] && echo ' CPU (container o servizio limitato: il multi-core non puo superarlo)')"
echo "istruzioni:   ${FLAG:-nessuna rilevante}  hypervisor: $(systemd-detect-virt 2>/dev/null || echo n/d)"
echo "RAM:          $(free -h | awk '/Mem/{print $2}')"
LOAD=$(cut -d' ' -f1 /proc/loadavg); echo "load attuale: $(cut -d' ' -f1-3 /proc/loadavg)"

echo; echo "== STEAL a riposo (20 s)"
read -r t1 s1 < <(stat_cpu); sleep 20; read -r t2 s2 < <(stat_cpu)
ST0=$(pct $((s2-s1)) $((t2-t1))); echo "steal a riposo:       $ST0 %"

echo; echo "== CPU 1 core (openssl sha256, 3 s)"
C1=$(openssl speed -seconds 3 -bytes 16384 sha256 2>/dev/null | awk '/^sha256/{v=$NF; sub(/k$/,"",v); printf "%.2f", v/1e6}')
echo "CPU 1 core:           $C1 GB/s"

echo; echo "== CPU tutti i core ($N processi, 5 s) + steal sotto carico"
read -r t1 s1 < <(stat_cpu)
CN=$(openssl speed -seconds 5 -bytes 16384 -multi $N sha256 2>/dev/null | awk '/^sha256/{v=$NF; sub(/k$/,"",v); printf "%.2f", v/1e6}')
read -r t2 s2 < <(stat_cpu)
ST1=$(pct $((s2-s1)) $((t2-t1)))
echo "CPU tutti i core:     $CN GB/s  ($N vCPU)"; echo "steal sotto carico:   $ST1 %"
CC=""
if [ "$TPC" -gt 1 ] && [ "$CORE" -lt "$N" ]; then
  echo; echo "== CPU solo core reali ($CORE processi, 5 s): quanto rende l'SMT"
  CC=$(openssl speed -seconds 5 -bytes 16384 -multi $CORE sha256 2>/dev/null | awk '/^sha256/{v=$NF; sub(/k$/,"",v); printf "%.2f", v/1e6}')
  echo "CPU $CORE core:            $CC GB/s   -> con SMT ($N vCPU): $CN GB/s  ($(awk -v a="$CC" -v b="$CN" 'BEGIN{printf "%+.0f",(a>0?(b/a-1)*100:0)}') %)"
fi
# CPU concesse davvero: le vCPU, o meno se c'e' un limite cgroup
NEFF=$(awk -v n="$N" -v l="$LIMITE" 'BEGIN{if(l!="nessuno" && l+0<n) printf "%.2f",l; else print n}')
SCALA=$(awk -v c1="$C1" -v cn="$CN" -v n="$NEFF" 'BEGIN{printf "%.1f",(c1>0?cn/(c1*n)*100:0)}')
echo "scala:                $SCALA %  (CPU tutti / (CPU 1 core x $NEFF CPU concesse): 100 % = ogni CPU vale un core pieno)"
[ "$LIMITE" != nessuno ] && echo "  NOTA: limite cgroup $LIMITE CPU: il multi-core misura il LIMITE, non la macchina"

echo; echo "== CONSISTENZA CPU (5 giri uguali, 1 core)"
GIRI=""; for k in 1 2 3 4 5; do g=$(/usr/bin/env python3 -I -c "
import time;t=time.perf_counter();x=0
for i in range(6_000_000): x+=i*i
print(f'{time.perf_counter()-t:.3f}')"); echo "giro $k: $g s"; GIRI="$GIRI $g"; done
GMIN=$(echo $GIRI | tr ' ' '\n' | sort -n | head -1); GMAX=$(echo $GIRI | tr ' ' '\n' | sort -n | tail -1)

echo; echo "== DISCO (512 MB, diretto, senza cache)"
F=$(mktemp /tmp/minibench.XXXXXX)
DW=$(dd if=/dev/zero of=$F bs=1M count=512 oflag=direct conv=fsync 2>&1 | dd_gbs); echo "scrittura:            $DW GB/s"
DR=$(dd if=$F of=/dev/null bs=1M iflag=direct 2>&1 | dd_gbs);                     echo "lettura:              $DR GB/s"
D4=$(dd if=$F of=/dev/null bs=4k count=20000 iflag=direct skip=$((RANDOM%1000)) 2>&1 | dd_gbs); echo "lettura 4k:           $D4 GB/s"
rm -f $F

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

V=$(awk -v a="$ST0" -v b="$ST1" 'BEGIN{m=(a>b?a:b); if(m<1) print "OK"; else if(m<5) print "ATTENZIONE"; else print "MALE"}')
echo; echo "== VERDETTO STEAL"
case $V in OK) echo "OK: host non sovraccarico (steal < 1%)";; ATTENZIONE) echo "ATTENZIONE: host condiviso sotto carico (steal 1-5%)";; *) echo "MALE: VPS su host stracarico (steal > 5%)";; esac

# --- confronto con la media degli ultimi 5 test (indice %) e scrittura storico ---
python3 -I - "$LOG" "$(date -u +%F)" "$(date -u +%T)" "$(TZ=Europe/Rome date +%:::z | sed 's/^\([+-]\)0/\1/')" \
  "$V" "$C1" "$CN" "$GMIN" "$GMAX" "$DW" "$DR" "$D4" "$ST0" "$ST1" "$DUR" "$CLKSRC" "$NTP" "$DRIFT" "$LOAD" "$N" \
  "$CC" "$SCALA" "$MODELLO" "$CORE" "$TPC" "$LIMITE" "$VCPU_TOT" "$CORE_SIS" "$AFF" <<'PY'
import sys, os, csv
log = sys.argv[1]
COLS = ["giorno_utc","ora_utc","offset_ita","verdetto","indice_pct",
        "cpu1_GBs","cpu_tutti_GBs","disco_scrittura_GBs","disco_lettura_GBs","disco_4k_GBs",
        "giro_min_s","giro_max_s",
        "steal_riposo_pct","steal_carico_pct","durata_s","clocksource","ntp_sync","drift_raw_mono_s","load1","vcpu",
        "cpu_core_GBs","scala_pct","cpu_modello","core","thread_per_core","limite_cgroup",
        "vcpu_sistema","core_sistema","affinity"]
# ordine degli argomenti passati da bash
ARG = ["giorno_utc","ora_utc","offset_ita","verdetto","cpu1_GBs","cpu_tutti_GBs","giro_min_s","giro_max_s",
       "disco_scrittura_GBs","disco_lettura_GBs","disco_4k_GBs","steal_riposo_pct","steal_carico_pct","durata_s",
       "clocksource","ntp_sync","drift_raw_mono_s","load1","vcpu",
       "cpu_core_GBs","scala_pct","cpu_modello","core","thread_per_core","limite_cgroup",
       "vcpu_sistema","core_sistema","affinity"]
cur = dict(zip(ARG, sys.argv[2:]))
# raggruppate per unita': prima GB/s, poi secondi, poi %
# gruppo, metrica, colonna, modo: 'alto' = piu' alto meglio, 'basso' = piu' basso meglio, 'steal'
METRICHE = [("GB/s  (piu alto = meglio)","CPU 1 core","cpu1_GBs","alto"), (None,"CPU tutti i core","cpu_tutti_GBs","alto"),
            (None,"disco scrittura","disco_scrittura_GBs","alto"), (None,"disco lettura","disco_lettura_GBs","alto"),
            (None,"disco 4k","disco_4k_GBs","alto"),
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
allarmi = []
righe = []
if os.path.exists(log) and os.path.getsize(log) > 0:
    with open(log, newline="") as fh: righe = list(csv.DictReader(fh))
# solo test fatti con la stessa CPU e lo stesso numero di vCPU (righe vecchie senza modello: conta solo vcpu)
stessa = [r for r in righe if r.get("vcpu") == cur["vcpu"] and r.get("cpu_modello", "") in ("", cur["cpu_modello"])
          and r.get("limite_cgroup", "nessuno") in ("", cur["limite_cgroup"])
          and r.get("affinity", "") in ("", cur["affinity"])]
if len(stessa) < len(righe):
    print(f"\nNOTA: {len(righe)-len(stessa)} test dello storico fatti con CPU, vCPU, affinity o limite diversi: esclusi dal confronto")
rif = stessa[-N_RIF:]
def media(col):
    v = [x for x in (f(r.get(col)) for r in rif) if x is not None]
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
        if gruppo: print(f"  -- {gruppo}")
        a, b = prev.get(col), f(cur[col]); i = indice(a, b, modo)
        if i is None: print(f"  {nome:22s}{'n/d':>12s}"); continue
        vals.append(i); u = UNITA[modo]
        if col in ("cpu1_GBs", "cpu_tutti_GBs") and i <= SOGLIA_CPU:
            allarmi.append(f"{nome.upper()} AL {i:.0f} % DELLA MEDIA ({b:.2f} GB/s INVECE DI {a:.2f})")
        print(f"  {nome:22s}{a:>7.2f} {u:<4s}  {b:>7.2f} {u:<4s}  {i:>7.1f} %  {esito(i)}")
    a, b = prev.get("durata_s"), f(cur["durata_s"])
    if a and b: print(f"  -- non in media\n  {'durata test':22s}{a:>7.1f} {'s':<4s}  {b:>7.1f} {'s':<4s}")
    if vals:
        m = sum(vals) / len(vals); cur["indice_pct"] = f"{m:.1f}"
        d = m - 100
        verso = "SOPRA" if d > 0 else "SOTTO" if d < 0 else "PARI A"
        print(f"\n  INDICE MEDIO: {m:.1f} %  ->  {abs(d):.1f} % {verso} la media degli ultimi {len(rif)} test  ({esito(m)}, {len(vals)} valori)")
        if m <= SOGLIA_INDICE: allarmi.append(f"INDICE MEDIO AL {m:.1f} % ({abs(d):.1f} % SOTTO LA MEDIA)")
    else: cur["indice_pct"] = ""

st0, st1 = f(cur["steal_riposo_pct"]), f(cur["steal_carico_pct"])
if st1 is not None and st1 >= SOGLIA_STEAL_CARICO: allarmi.append(f"STEAL SOTTO CARICO {st1:.2f} % (SOGLIA {SOGLIA_STEAL_CARICO:.0f} %)")
if st0 is not None and st0 >= SOGLIA_STEAL_RIPOSO: allarmi.append(f"STEAL A RIPOSO {st0:.2f} % (SOGLIA {SOGLIA_STEAL_RIPOSO:.0f} %)")
if allarmi:
    print("\n" + "!" * 70)
    print("!!! ALLARME: CI STANNO A INCULA' LA CPU !!!")
    for a in allarmi: print("!!! - " + a)
    print("!!! Prima guardare 'Processi pesanti' (altri lavori sulla macchina).")
    print("!!! Se non e' roba nostra: ripetere il test; se si ripete, segnalare al provider.")
    print("!" * 70)

nuovo = not righe
if righe and list(righe[0].keys()) != COLS:
    print(f"ATTENZIONE: intestazione di {log} diversa dal formato attuale, riga non aggiunta"); sys.exit(0)
with open(log, "a", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=COLS)
    if nuovo: w.writeheader()
    w.writerow(cur)
print(f"storico: riga aggiunta a {log} ({len(righe)+1} test)")
PY
exit 0
