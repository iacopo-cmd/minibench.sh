# minibench

Mini benchmark per VPS Linux in circa 37 secondi. Misura se il provider ti sta togliendo CPU (steal time), quanto vanno CPU e disco, e confronta ogni test con la media dei 5 test precedenti.

> ⚠️ **DA AGGIUSTARE PER IL WEB**
> Lo script è nato e tarato su **un server preciso**: VPS con 8 vCPU EPYC e Debian 13.
> Funziona, ma prima di usarlo altrove va sistemato. Vedi la sezione [Da aggiustare per il web](#da-aggiustare-per-il-web).

---

## File nel repo

| File | Cosa è |
|---|---|
| `minibench.sh` | lo script |
| `README.md` | questa descrizione |
| `SINTESI.txt` | riassunto breve da mandare su WhatsApp o Telegram |
| `LICENSE` | licenza MIT |
| `.gitignore` | esclude lo storico locale `minibench.csv` |
| `storico-esempio.csv` | storico vero del server di origine (1 novembre 2026, 28 test), come esempio di formato e di valori |

---

## Uso

```bash
bash minibench.sh                  # tutte le vCPU, storico in minibench.csv accanto allo script
bash minibench.sh -c 4             # solo le prime 4 vCPU (affinity)
bash minibench.sh -c 0,2,4,6       # vCPU scelte a mano
bash minibench.sh /percorso/altro.csv
```

- Non modifica il sistema. Scrive un file temporaneo di 512 MB in `/tmp` e poi lo cancella.
- Ogni lancio aggiunge una riga allo storico CSV.
- Requisiti: `bash`, `python3`, `openssl`, `dd`, `awk`, `ps`, `lscpu`, `taskset`, `timedatectl` (systemd).

---

## CPU reale: niente valori scritti fissi

Lo script non presume niente: legge dal sistema cosa c'è davvero e lo scrive.

```
== CPU REALE (letta dal sistema, niente valori fissi)
modello:      AMD EPYC-Milan Processor
sistema:      1 socket x 4 core x 2 thread = 4 core, 8 vCPU  (SMT/hyperthreading: 2 vCPU = 1 core)
test su:      8 vCPU [0,1,2,3,4,5,6,7] = 4 core reali
limite cgroup: nessuno
istruzioni:   aes avx2 sha_ni   hypervisor: kvm
```

- **vCPU**: il test multi-core usa tutte le vCPU che trova (`nproc`), non un numero scritto nello script.
- **Core e thread**: se c'è SMT (hyperthreading), fa anche un test con i soli core, per vedere quanto rendono i thread in più.
- **Limite cgroup**: se lo lanci dentro un container o un servizio limitato (Docker `cpus`, systemd `CPUQuota`), se ne accorge. Lo scrive e calcola la scala sulle CPU concesse davvero.
- **Scala** = CPU tutti / (CPU 1 core × CPU) × 100. Al 100 % ogni vCPU vale un core pieno; con SMT è normale stare tra il 55 e il 70 %.
- **Confronto onesto**: la media usa solo test con stessa CPU, stesse vCPU, stessa affinity e stesso limite. Se cambi VPS lo storico vecchio non si mischia.

---

## Affinity spiegata semplice (`-c`)

**Cos'è.** Dici al sistema: "questo programma può girare **solo** su queste vCPU". Senza `-c` il test usa tutte le vCPU; con `-c` lo chiudi in un recinto.

**Perché serve:**

1. **Vedere come cresce la potenza.** Prova `-c 1`, `-c 2`, `-c 4`, `-c 8`. Se raddoppiando le vCPU la "CPU tutti i core" non raddoppia, le vCPU in più valgono meno di quanto sembra.
2. **Scoprire l'SMT (hyperthreading).** Due vCPU sullo stesso core si dividono lo stesso core fisico, quindi rendono meno di due core veri.
   - `-c 0,1`: 2 vCPU sullo **stesso** core (secondo la VM)
   - `-c 0,2`: 2 vCPU su core **diversi**
   - se `0,2` va molto più forte di `0,1`, l'SMT è vero;
   - se vanno uguali, la topologia mostrata dalla VM è finta: la decide l'hypervisor, e sotto le vCPU stanno dove vuole il provider.
3. **Simulare una macchina più piccola.** `-c 2` vuol dire "come andrebbe con 2 vCPU".
4. **Trovare una vCPU lenta.** Prova una vCPU alla volta: `-c 0`, poi la lista `-c 3`, poi `-c 7`…

**Esempi:**

| Comando | Su quali vCPU gira |
|---|---|
| `minibench.sh -c 1` | solo la vCPU 0 |
| `minibench.sh -c 4` | le prime 4: 0, 1, 2, 3 |
| `minibench.sh -c 0,2,4,6` | 4 vCPU, una per core |
| `minibench.sh -c 4-7` | dalla 4 alla 7 |

**Da sapere:**

- Un numero semplice (`-c 4`) vuol dire le **prime** N vCPU. Per sceglierle una per una si usa la lista.
- `lscpu -e` mostra quali vCPU stanno sullo stesso core: hanno lo stesso valore nella colonna `CORE`.
- Lo storico confronta solo test con la **stessa** affinity: un test con `-c 4` non viene mischiato con quelli su tutte le vCPU.

**Cosa abbiamo trovato sul server di origine** (1 novembre 2026, un test solo, da ripetere):

| Affinity | Secondo la VM | CPU tutti |
|---|---|---|
| `-c 0-3` | 2 core × 2 thread (SMT) | 3,97 GB/s |
| `-c 0,2,4,6` | 4 core diversi | 3,29 GB/s |

Le vCPU che per la VM sono "SMT" sono andate **più forte** dei core "diversi": la topologia dichiarata dalla VM non corrisponde all'hardware vero.

---

## Cosa misura

| Sezione | Cosa | Unità | Meglio se |
|---|---|---|---|
| Steal a riposo | CPU rubata dall'hypervisor in 20 s di quiete | % | basso |
| CPU 1 core | `openssl speed sha256`, 3 s | GB/s | alto |
| CPU tutti i core | `openssl speed -multi N sha256`, 5 s | GB/s | alto |
| Steal sotto carico | steal mentre tutti i core lavorano | % | basso |
| Consistenza CPU | 5 giri uguali in Python: il più veloce e il più lento | s | basso |
| Disco scrittura / lettura | `dd` 512 MB, diretto senza cache | GB/s | alto |
| Disco 4k | `dd` a blocchi da 4 KB | GB/s | alto |
| Orologio | clocksource, NTP, drift RAW−MONOTONIC | — | drift ≈ 0 |

---

## Steal time (la cosa più importante)

Una VPS è una macchina virtuale su un server fisico condiviso con altri clienti. Lo **steal** è la percentuale di tempo in cui la VM voleva usare la CPU ma l'hypervisor l'ha data a un altro cliente. Lo misura il kernel: colonna `st` di `top`/`vmstat`, ottavo valore di `/proc/stat`.

| Steal | Verdetto | Significato |
|---|---|---|
| < 1 % | OK | host tranquillo, le vCPU sono "tue" |
| 1–5 % | ATTENZIONE | host condiviso sotto carico, rallentamenti a tratti |
| > 5 % | MALE | host stracarico (overselling), da segnalare al provider |

Il valore **sotto carico** è quello che conta di più.

---

## Indice: un dato comune a tutti

Ogni valore viene trasformato in **% della media degli ultimi 5 test**, girato in modo che **sopra 100 = meglio** e **sotto 100 = peggio**:

- più alto è meglio (GB/s): `ora / media × 100`
- più basso è meglio (secondi): `media / ora × 100`
- steal: CPU disponibile `(100 − steal)`, poi `ora / media × 100`

**INDICE MEDIO** = media dei 9 valori.

| Indice | Esito |
|---|---|
| ≥ 105 % | MIGLIORATO |
| 95–105 % | COSTANTE (rumore di misura) |
| ≤ 95 % | PEGGIORATO |

Il confronto si fa con la media di 5 test e non con il test precedente, perché un test singolo può ballare anche del 30 %. La durata del test non entra nella media: è quasi tutta un'attesa fissa.

---

## Allarme

In fondo all'output compare un blocco in **MAIUSCOLO** se anche una sola di queste condizioni è vera:

- steal sotto carico ≥ 5 %
- steal a riposo ≥ 1 %
- CPU 1 core o CPU tutti i core ≤ 80 % della media
- indice medio ≤ 85 %

```
!!! ALLARME: CI STANNO A INCULA' LA CPU !!!
!!! - CPU TUTTI I CORE AL 70 % DELLA MEDIA (4.00 GB/s INVECE DI 5.72)
!!! - STEAL SOTTO CARICO 6.20 % (SOGLIA 5 %)
```

Le soglie si cambiano nelle variabili `SOGLIA_*` all'inizio del blocco Python.

---

## Orologio: perché MONOTONIC

- **REALTIME** (`date`) è l'ora del giorno. NTP la può spostare avanti o indietro in qualsiasi momento, quindi una durata calcolata con `date` può venire sbagliata.
- **MONOTONIC** è un contatore che parte all'avvio e va **solo avanti**, senza salti. NTP può solo accelerarlo o rallentarlo di pochissimo (ppm). È quello giusto per misurare le durate.
- **MONOTONIC_RAW** è come MONOTONIC ma senza nessuna correzione NTP: il quarzo o l'hypervisor nudo. `RAW − MONOTONIC` misura quanto NTP sta correggendo.

Durata del test e giri CPU sono misurati con MONOTONIC. Data e ora nel CSV sono in UTC dal kernel.
**drift < 0,001 s = orologio stabile, misure attendibili.**

Serve anche a incrociare lo storico del minibench con un controllo periodico degli orologi.

---

## Storico CSV

Colonne nell'ordine: data e ora UTC, verdetto, indice, poi le velocità in GB/s, i secondi, gli steal e infine il contesto.

```
giorno_utc, ora_utc, offset_ita, verdetto, indice_pct,
cpu1_GBs, cpu_tutti_GBs, disco_scrittura_GBs, disco_lettura_GBs, disco_4k_GBs,
giro_min_s, giro_max_s,
steal_riposo_pct, steal_carico_pct,
durata_s, clocksource, ntp_sync, drift_raw_mono_s, load1, vcpu,
cpu_core_GBs, scala_pct, cpu_modello, core, thread_per_core, limite_cgroup,
vcpu_sistema, core_sistema, affinity
```

- `vcpu` e `core`: quelli **usati dal test** (dipendono da `-c`).
- `vcpu_sistema` e `core_sistema`: quelli della macchina.
- `affinity`: l'elenco esatto delle vCPU usate.

---

## Come leggere i risultati

- Un test solo non dice niente: conta l'andamento nello storico.
- I test di notte sono ottimisti, perché gli altri clienti dormono. L'overselling si vede nelle ore di punta: fare test anche tra le 10 e le 13 e tra le 18 e le 22.
- CPU tutti i core in calo, con CPU 1 core normale e steal a 0: forse l'host è carico e abbassa la frequenza. Lo steal in quel caso non lo vede.
- Prima di dare la colpa all'host, guardare la sezione "Processi pesanti": lavori tuoi sul server falsano la misura multi-core.
- Non misura RAM (overcommit) né rete (banda condivisa).

Valori di riferimento del server di origine, 1 novembre 2026 di notte, 8 vCPU EPYC Milan:
steal 0/0 % · CPU 1 core ~1,06 GB/s · 8 core 5,5–7,0 GB/s · giri 1,4–1,6 s · disco W 0,83–1,0 / R 3,4–5,3 / 4k 0,9–1,4 GB/s · durata ~37 s.

---

## Da aggiustare per il web

Lo script è nato per uso interno. Prima di proporlo come strumento generico vanno sistemati questi punti:

- [ ] **Riferimenti personali nei commenti:** da rendere generici.
- [x] **CPU e vCPU lette dal sistema** (`lscpu`, `nproc`, affinity, limite cgroup), non più scritte fisse nello script.
- [ ] **Valori di riferimento** del server di origine nei commenti: vanno spostati in un file a parte o ricavati dallo storico della macchina.
- [ ] **Fuso orario fisso** `Europe/Rome` nella colonna `offset_ita`: va reso configurabile o tolto, l'UTC basta.
- [ ] **Solo italiano:** testi e colonne. Valutare una versione in inglese o una variabile per la lingua.
- [ ] **Dipendenze non controllate:** se manca `openssl`, `python3` o `timedatectl` lo script dà valori vuoti invece di un errore chiaro. Serve un controllo iniziale.
- [ ] **Solo systemd:** `timedatectl` non c'è su Alpine, sui container e su altri sistemi. Serve un'alternativa (`chronyc`, `ntpq`, `adjtimex`).
- [ ] **Disco:** scrive 512 MB in `/tmp`, che a volte è tmpfs, cioè in RAM: in quel caso misura la RAM e non il disco. Il percorso del test va reso configurabile e va controllato lo spazio libero.
- [ ] **Due lanci insieme** si falsano a vicenda e mischiano lo storico. Serve un blocco con `flock`.
- [ ] **Storico accanto allo script:** se la cartella non è scrivibile, lo storico va perso. Serve un default in `~/.local/share` o un messaggio chiaro.
- [ ] **Cambio di formato del CSV:** se l'intestazione non corrisponde, la riga non viene scritta. Serve una migrazione automatica o un file nuovo.
- [ ] **ARM e macOS** non provati: `openssl speed` e `dd iflag=direct` cambiano.
- [x] **Licenza:** MIT (file `LICENSE`).

---

*Prima versione: 2026-11-01.*
