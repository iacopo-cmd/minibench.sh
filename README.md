# minibench

Mini benchmark per VPS Linux in circa 23 secondi (26 con il disco, che di default non si fa). Misura se il provider ti sta togliendo CPU (steal time), quanto vanno CPU e disco, e confronta ogni test con la media dei 5 test precedenti.

> ⚠️ **DA AGGIUSTARE PER IL WEB**
> Lo script è nato e tarato su **un server preciso**: una VPS con 8 vCPU EPYC e Debian 13.
> Funziona, ma prima di usarlo altrove va sistemato. Vedi la sezione [Da aggiustare per il web](#da-aggiustare-per-il-web).

---


> ## ⚠️ FRENO ACCESO DI DEFAULT: senza `-r` il test NON riparte prima di 10 minuti
> Se l'ultimo test confrontabile ha meno di 10 minuti, lo script ristampa quello invece di rifare il test
> (utile su server condivisi: 12 lanci insieme = 1 test vero). Test subito: `minibench.sh -r 0`.
> Spegnerlo per sempre: in `minibench.sh` cerca la riga `FRENO=${MINIBENCH_FRENO:-9}` e metti `0` al posto di `9`
> (oppure per un lancio: `MINIBENCH_FRENO=0 minibench.sh`).
> 10 minuti nominali, cronometro a 9: chi rilancia poco prima dei 10 trova già il test nuovo.
>
> **Tanti campioni di fila?** Con il freno acceso un ciclo senza `-r 0` ristampa sempre lo stesso risultato:
> sembrano campioni nuovi ma non lo sono. Se usi lo script così (o lo passi ad altri), in `minibench.sh`
> c'è un blocco commentato `FRENO SPENTO DEL TUTTO` (cerca `SPENTO`): togli il `#` dalle 2 righe e il freno
> non c'è più, ogni lancio fa il test vero.

## File nel repo

| File | Cosa è |
|---|---|
| `minibench.sh` | lo script |
| `README.md` | questa descrizione |
| `SINTESI.txt` | riassunto breve da mandare su WhatsApp o Telegram |
| `LICENSE` | licenza MIT |
| `.gitignore` | esclude lo storico locale `minibench.csv` |
| `storico-esempio.csv` | storico vero del server di origine (1 novembre 2026: i primi col disco in RAM, poi disco vero; dalla riga con `disco_4k_iops` il 4k è random), come esempio di formato e di valori |

---

## Uso

```bash
bash minibench.sh                  # tutte le vCPU, storico in minibench.csv accanto allo script
bash minibench.sh -h               # aiuto
bash minibench.sh -c 4             # solo le prime 4 vCPU (affinity)
bash minibench.sh -x 3             # precisione come il vecchio default (~1 min)
bash minibench.sh -x 23            # alta precisione: tutto x23 (~8 minuti)
bash minibench.sh -t               # solo riassunto breve per Telegram/WhatsApp
bash minibench.sh -t -n            # riassunto, senza scrivere nello storico
bash minibench.sh -D                # anche il test disco, nella cartella dello script
bash minibench.sh -d /data         # anche il test disco, in /data
bash minibench.sh /percorso/altro.csv
```

| Switch | Cosa fa |
|---|---|
| `-c N` o `-c lista` | affinity: solo le prime N vCPU, o quelle elencate (`0,2,4,6`, `4-7`) |
| `-x N` | test lungo: secondi di misura, giri CPU e passate disco moltiplicati per N; sul disco si tiene la mediana delle passate |
| `-D` | fa **anche** il test disco, nella cartella dello script. **Di default il disco non si fa** |
| `-d DIR` | fa **anche** il test disco, nella cartella DIR |
| `-t` | stampa solo un riassunto di 5–8 righe, pronto da mandare in chat |
| `-n` | non scrive nello storico (prova al volo) |
| `-o FILE` | scrive la riga anche in FILE; si ripete (`-o a.csv -o b.csv`). Il test gira una volta, il confronto usa lo storico principale. Un link allo storico viene saltato |
| `-r MIN` | **freno**, acceso di default a 10 min (cronometro a 9): se c'è già un test confrontabile più giovane di MIN minuti non rifà il test e stampa quello. `-r 0` = test sempre. Per toglierlo del tutto: blocco `FRENO SPENTO DEL TUTTO` nel codice |
| `-A` | archivia: sposta le righe vecchie dello storico in `minibench-archivio-DATA.csv.gz`, accanto allo storico, e tiene le ultime 1.000. Non fa il test e non cancella niente |
| `-h` | aiuto |

Esempio di `-t` (fatto per il telefono: un dato per riga, righe corte, virgola decimale):

```
📊 minibench 01/11 08:21 UTC
✅ OK, indice 97,2 %

Steal: 0,00 % / 0,00 %
CPU 1 core: 1,07 GB/s
CPU 8 vCPU: 5,39 GB/s
Scala: 63,0 %
Base: 0,13 GB/s (v3)
AES: 1,77 GB/s
Vett: 1,39 GB/s
Disco: non misurato

✅ nessun allarme
```

- **Un test alla volta.** Due test insieme si falsano a vicenda: un blocco (`flock` su `.minibench.lock` accanto allo storico, non in `/tmp` dove chiunque potrebbe crearlo o tenerlo) fa aspettare il secondo finché il primo non ha finito.
- **Test lunghi a parte.** Lo storico confronta solo test con lo stesso `-x`: un test x23 non si mischia con quelli normali.
- Non modifica il sistema. Scrive un file temporaneo di 512 MB nella cartella del test disco e poi lo cancella.
- Ogni lancio aggiunge una riga allo storico CSV (tranne con `-n`).
- **Storico grande:** quando supera 1 MB (circa 2.500 test), ogni test **propone** di archiviare, anche nel riassunto `-t` (`📦 Storico grande … Proposta: archiviare con -A`), ma non lo fa da solo. Soglie cambiabili con `MINIBENCH_CSV_KB` e `MINIBENCH_TIENI`.

### Configurabilità: pensata per darlo a terzi

Lo script è stato previsto molto configurabile, perché si possa dare a terzi senza che diventi un problema o un disservizio (per esempio un freno che confonde chi fa tanti campioni, o un disco consumato da test lanciati di continuo). Si regola senza toccare la logica, su 3 livelli:

- **dal sorgente**: i default per tutti (righe commentate in testa a `minibench.sh`);
- **dall'ambiente**: per un servizio o un agente (`MINIBENCH_...`);
- **dagli switch**: per un lancio solo.

| Cosa | Sorgente (default per tutti) | Ambiente | Switch |
|---|---|---|---|
| freno fra due test | riga `FRENO=` (9 = 10 min nominali) | `MINIBENCH_FRENO=MIN` | `-r MIN` |
| freno spento del tutto | blocco `FRENO SPENTO DEL TUTTO` (togliere il `#`) | – | – |
| storico: soglia per proporre il taglio | riga `CSV_KB=` (1024 KB) | `MINIBENCH_CSV_KB=KB` | – |
| storico: righe tenute archiviando | riga `TIENI=` (1000) | `MINIBENCH_TIENI=N` | `-A` |
| durata / precisione | riga `X=1` | – | `-x N` |
| disco (consuma) | spento di default | – | `-D` / `-d DIR` |
| copie dello storico | – | – | `-o FILE` (ripetibile) |
| non scrivere nello storico | – | – | `-n` |
| vCPU usate | – | – | `-c N` / `-c LISTA` |

Chi lo installa su un server condiviso lo tiene prudente (freno acceso, disco spento); chi lo passa ad altri o fa tanti campioni di fila lo apre (freno spento). `MINIBENCH_CONFERMA` e `MINIBENCH_AFFINITY` sono interni: li usa lo script quando si rilancia da solo.

### ⚠️ Attenzione a `/tmp`: spesso è in RAM

Su molti sistemi (Debian 13 compreso) `/tmp` è `tmpfs`, cioè sta **in RAM**. Un test disco fatto lì misura la RAM, non il disco. Le prime versioni dello script facevano proprio così: sul server di origine segnavano 1,0 GB/s in scrittura e 4,5 GB/s in lettura, mentre il disco vero fa **0,55 GB/s** in tutte e due.
Adesso il test disco si fa nella cartella dello script e il tipo di filesystem viene scritto nell'output e nel CSV (`disco_fs`). Se è `tmpfs` compare un avviso.
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

## CPU vecchie e nuove, Intel e AMD

Le estensioni hanno gli stessi nomi su Intel e AMD, e lo script le tratta allo stesso modo.

```
livello:      x86-64-v3  (v1 = CPU vecchie, v2 ~2009, v3 = AVX2 ~2015, v4 = AVX-512)
istruzioni:   sse4_2 aes sha_ni avx avx2 vaes vpclmulqdq
mancano:      avx512f avx512_vnni avx_vnni gfni amx_tile
== ISTRUZIONI CPU (1 core, 3 s ciascuna)
base (nessuna estensione): 0.15 GB/s   <- confrontabile fra CPU diverse
SHA  (SHA-NI):  1.05 GB/s   x7.0 rispetto alla base
AES  (AES-NI + VAES):  1.77 GB/s
vett (AVX2):  1.30 GB/s
```

| Prova | Cosa usa | A cosa serve |
|---|---|---|
| **base** | sha256 con OpenSSL costretto a **non** usare estensioni (`OPENSSL_ia32cap=0:0`) | stesso codice su ogni CPU x86: è l'unico numero da confrontare fra macchine diverse |
| **SHA** | sha256 nativo: SHA-NI se c'è | quanto rendono le estensioni ("x7" qui) |
| **AES** | AES-128-GCM nativo: AES-NI, oppure VAES + VPCLMULQDQ sulle ultime | cifratura (TLS, VPN, dischi cifrati) |
| **vett** | ChaCha20-Poly1305 nativo: SSE, AVX2 o AVX-512, la più larga che c'è | calcolo vettoriale |

Su una CPU vecchia senza un'estensione la prova gira lo stesso, in software: niente errori, solo numeri più bassi. Il **livello x86-64** riassume tutto in una parola: v1 per le CPU vecchie, v2 dal 2009 circa (SSE4.2), v3 con AVX2 dal 2015 circa (Haswell, Zen), v4 con AVX-512 (Xeon Skylake-SP e successivi, Zen 4).

---

## Affinity spiegata semplice (`-c`)

**Cos'è.** Dici al sistema: "questo programma può girare **solo** su queste vCPU". Senza `-c` il test usa tutte le vCPU; con `-c` lo chiudi in un recinto.

**Di default (senza `-c`) prova su tutte le vCPU che trova**, sul server di origine 8:

| Prova | Processi |
|---|---|
| CPU 1 core | 1 |
| CPU tutti i core | 1 per vCPU (8) |
| CPU solo core reali | 1 per core (4), solo se c'è SMT |

"Tutte" può voler dire meno vCPU in due casi:
- **Affinity già ristretta:** lo lanci già sotto `taskset`, quindi `nproc` vede solo le vCPU permesse e il test si adegua. Lo scrive nella riga `test su:`.
- **Limite CPU:** gira dentro un container o un servizio limitato (Docker `cpus: "2"`, systemd `CPUQuota`). Lancia comunque un processo per vCPU, ma ne rendono solo quante il limite concede: lo segnala in `limite cgroup` e calcola la scala sulle CPU concesse.

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
| Istruzioni CPU | sha256 **base** senza estensioni (`OPENSSL_ia32cap=0:0`), AES-128-GCM, ChaCha20-Poly1305, 3 s ciascuna | GB/s | alto |
| Disco 4k random (solo `-D`/`-d`) | letture da 4 KB in punti casuali, O_DIRECT, una alla volta, per 3 s | IOPS | alto |
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
cpu1_GBs, cpu_tutti_GBs, disco_scrittura_GBs, disco_lettura_GBs, disco_4k_GBs (vecchio, vuoto),
giro_min_s, giro_max_s,
steal_riposo_pct, steal_carico_pct,
durata_s, clocksource, ntp_sync, drift_raw_mono_s, load1, vcpu,
cpu_core_GBs, scala_pct, cpu_modello, core, thread_per_core, limite_cgroup,
vcpu_sistema, core_sistema, affinity, x, disco_fs, disco_dir,
disco_4k_iops, openssl_ver, python_ver, container,
cpu1_base_GBs, aes_GBs, vett_GBs, x86_livello, cpu_flag, schema
```

- `x`: il moltiplicatore di `-x` (1 = test normale).
- `disco_fs` e `disco_dir`: dove è stato fatto il test disco. Nelle righe vecchie risulta `tmpfs /tmp`, cioè RAM.

- `vcpu` e `core`: quelli **usati dal test** (dipendono da `-c`).
- `vcpu_sistema` e `core_sistema`: quelli della macchina.
- `affinity`: l'elenco esatto delle vCPU usate.

---

## Conferma degli allarmi

Se lanci il test **senza `-x`** e scatta un allarme, l'allarme **non viene mandato subito**:

1. il test scrive `POSSIBILE ALLARME` e non mette niente nello storico;
2. si rilancia da solo con `-x 3` (~1 minuto) e lo confronta con lo **stesso** storico;
3. se l'allarme si ripete scrive **`ALLARME CONFERMATO dal test lungo x3`**; altrimenti scrive **`non confermato: era rumore`** e salva il test lungo, con `conferma=1` nel CSV.

Con `-x` messo a mano la conferma non c'è: la precisione l'hai già scelta tu.

Provato sul server di origine:

| Simulazione | Risultato |
|---|---|
| CPU lenta sia nel test veloce sia nella conferma | `🚨 ALLARME CONFERMATO dal test lungo x3`, in 87 s |
| CPU lenta solo nel test veloce | `✅ allarme del test veloce NON confermato dal test lungo x3: era rumore`, in 88 s |

---

## Cambio del 1° novembre 2026: default veloce (schema 2)

**Cosa:** il test di default dura circa **23 secondi** invece di 50. La precisione la sceglie chi lo lancia, con `-x`.

| Prova | Prima | Ora (`-x 1`) |
|---|---|---|
| steal a riposo | 20 s | 5 s |
| CPU 1 core | 3 s | **3 s** (vedi quarta revisione) |
| istruzioni (base, AES, vett) | 3 s ciascuna | 1 s ciascuna |
| CPU tutti i core, solo core | 5 s ciascuna | **3 s** ciascuna (vedi sotto) |
| giri CPU | 5 | 3 |
| disco | ogni volta | **solo con `-D` o `-d DIR`**, 1 passata + 1 s di 4k random |
| **totale** | ~50 s | **~23 s** (~26 s con il disco), misurati su 8 vCPU con SMT |

`-x 3` vale circa il vecchio default (~50–60 s), `-x 10` è alta precisione (~3 min).

**Perché:**
- **Gli agenti AI** possono lanciarlo spesso senza occupare la macchina, e scelgono loro `-x` quando serve.
- **Salvare i dischi:** ogni test disco scrive 512 MB (per N con `-x`). Di default il disco non si tocca.
- **Precisione su richiesta:** chi vuole numeri più stabili usa `-x`.

**Perché non tutto a un giro solo:** è stato valutato e scartato.
- Lo steal misurato su 2 s è casuale, perché il provider ruba CPU a raffiche.
- Con un giro solo il giro più veloce e il più lento coincidono, e la consistenza non si vede più.
- Misure troppo corte fanno scattare gli allarmi a vuoto.

**Storico:** nel CSV c'è la colonna `schema`. Si confrontano solo test dello stesso schema e con lo stesso `-x`.
- **1:** i test vecchi, a 50 s.
- **2:** default veloce, con il multi-core a 1 s. È durato pochi minuti, vedi sotto.
- **3:** come il 2, ma con il multi-core a 3 s. È quello attuale.

### Seconda revisione (1° novembre, 08:50): il multi-core a 1 s faceva falsi allarmi

Due test uguali a 15 secondi di distanza, senza carico, hanno dato CPU tutti i core 12,39 → 9,56 GB/s (77 %), e quindi un allarme falso. Il motivo: con `openssl speed -multi 8 -seconds 1` l'avvio e la sincronizzazione degli 8 processi pesano quanto la misura. Per la stessa ragione anche la "scala" usciva troppo bassa.

| Proposta del revisore | Fatto |
|---|---|
| Multi-core a 3 s anche nel default | **sì**: CPU tutti i core e "solo core" a 3 s (+4 s, default ~20 s) |
| Allarmi solo con almeno 3 test di riferimento | **sì**: allarmi su CPU e indice spenti finché i test di riferimento sono meno di 3 (`MIN_RIF_ALLARME`). Lo steal dà l'allarme sempre, perché è un valore assoluto |
| Soglia CPU dall'80 al 70 % | **no**: è un rattoppo, lo sconsigliava anche il revisore |

Verifica dopo la correzione: tre test di fila sul server di origine danno 5,37 / 5,92 / 6,81 GB/s con nessun allarme, in circa 20,5 s ciascuno. Uno scarto del ±12 % resta: è la variabilità reale della VPS, e si riduce con `-x`.

### Terza e quarta revisione (1° novembre, ~09:00)

| Problema | Correzione |
|---|---|
| **Il disco faceva abortire tutto.** Dove O_DIRECT non c'è (tmpfs, ZFS, NFS, alcuni overlayfs) il 4k andava in errore, la misura restava vuota e il test usciva con `exit 3`, buttando anche CPU e steal | il disco non è più fra le misure obbligatorie: se fallisce esce **n/d**, con una nota, e il test va avanti. Provato con un `dd` finto che fallisce: CPU e steal ci sono, disco n/d, exit 0 |
| **Lo steal con `-c`** era quello di tutta la macchina | ora è calcolato **solo sulle vCPU del test**, sommando le righe `cpuN` di `/proc/stat`. In container o con limite cgroup resta quello di tutta la VM, e lo script lo dice |
| **Il timer del 4k** guardava l'orologio ogni 64 letture: su un disco da ~100 IOPS sforava di mezzo secondo | ora controlla a ogni lettura |
| **La scala** = CN / (C1 × N) divideva una misura da 3 s per una da 1 s | CPU 1 core portata a **3 s**, come il multi-core |
| **La durata dichiarata** (~20 s) era rimasta quella di prima | misurata di nuovo: **~23 s**, ~26 s con il disco |

---

## Revisione del 1° novembre 2026 (cosa è stato corretto)

Una revisione esterna ha trovato questi difetti, ora corretti:

| # | Problema | Correzione |
|---|---|---|
| 1 | Il "4k" non era random: `skip` spostava di 4 MB al massimo e poi leggeva 80 MB di fila | 4k **random** vero su tutto il file, O_DIRECT, risultato in **IOPS** (`disco_4k_iops`). I valori vecchi non si confrontano |
| 2 | Un aggiornamento di openssl o python cambia le misure, e lo script dava la colpa al provider | colonne `openssl_ver` e `python_ver`; si confrontano solo test con le stesse versioni |
| 3 | Una misura fallita finiva nello storico come valore vuoto, senza errore | ogni misura viene controllata: se una manca, errore e niente riga nello storico |
| 4 | `$F` senza virgolette: `-d` su cartelle con spazi rompeva il test | virgolette ovunque, provato con una cartella con gli spazi |
| 5 | `exec taskset … || errore`: l'errore non poteva mai comparire | lista vCPU e `taskset` controllati **prima** dell'exec; `-c 0-20` su 8 vCPU ora dà errore |
| 6 | Il lucchetto in `/tmp` poteva essere creato o tenuto da chiunque | lucchetto accanto allo storico; per gli utenti senza permessi, uno personale |
| 7 | In un container lo steal di `/proc/stat` è quello di tutta la VM | rileva il container (`systemd-detect-virt`) e lo dice, anche nel riassunto `-t` |
| 8 | Il README diceva 37 s, lo script 45 | allineati |

Non è stato aggiunto `set -euo pipefail` a tutto lo script: farebbe uscire con errore anche dove un risultato vuoto è normale (per esempio `grep` che non trova niente). Al suo posto c'è il controllo esplicito delle misure del punto 3.

---

## Come leggere i risultati

- Un test solo non dice niente: conta l'andamento nello storico.
- I test di notte sono ottimisti, perché gli altri clienti dormono. L'overselling si vede nelle ore di punta: fare test anche tra le 10 e le 13 e tra le 18 e le 22.
- CPU tutti i core in calo, con CPU 1 core normale e steal a 0: forse l'host è carico e abbassa la frequenza. Lo steal in quel caso non lo vede.
- Prima di dare la colpa all'host, guardare la sezione "Processi pesanti": lavori tuoi sul server falsano la misura multi-core.
- Non misura RAM (overcommit) né rete (banda condivisa).

Valori di riferimento del server di origine, 1 novembre 2026 di notte, 8 vCPU EPYC Milan:
steal 0/0 % · CPU 1 core ~1,06 GB/s · 8 core 5,5–7,0 GB/s · giri 1,4–1,6 s · disco ext4 W ~0,55 / R ~0,55 GB/s · 4k random ~5.800–6.700 IOPS · durata ~48 s.

---

## Da aggiustare per il web

Lo script è nato per uso interno. Prima di proporlo come strumento generico vanno sistemati questi punti:

- [x] **Riferimenti personali nei commenti:** tolti, resi generici.
- [x] **CPU e vCPU lette dal sistema** (`lscpu`, `nproc`, affinity, limite cgroup), non più scritte fisse nello script.
- [ ] **Valori di riferimento** del server di origine nei commenti: vanno spostati in un file a parte o ricavati dallo storico della macchina.
- [ ] **Fuso orario fisso** `Europe/Rome` nella colonna `offset_ita`: va reso configurabile o tolto, l'UTC basta.
- [ ] **Solo italiano:** testi e colonne. Valutare una versione in inglese o una variabile per la lingua.
- [x] **Misure fallite:** se uno strumento non risponde e una misura esce vuota, il test si ferma con errore e non scrive nello storico.
- [ ] **Controllo iniziale delle dipendenze:** manca ancora un elenco all'avvio di cosa non è installato.
- [ ] **Solo systemd:** `timedatectl` non c'è su Alpine, sui container e su altri sistemi. Serve un'alternativa (`chronyc`, `ntpq`, `adjtimex`).
- [x] **Disco:** prima scriveva in `/tmp`, che può essere tmpfs (RAM). Ora usa la cartella dello script o `-d DIR`, controlla lo spazio libero e avvisa se è tmpfs.
- [x] **Due lanci insieme:** risolto con un blocco `flock`, il secondo aspetta.
- [ ] **Storico accanto allo script:** se la cartella non è scrivibile, lo storico va perso. Serve un default in `~/.local/share` o un messaggio chiaro.
- [ ] **Cambio di formato del CSV:** se l'intestazione non corrisponde, la riga non viene scritta. Serve una migrazione automatica o un file nuovo.
- [ ] **ARM e macOS** non provati: `openssl speed` e `dd iflag=direct` cambiano.
- [x] **Licenza:** MIT (file `LICENSE`).

---

*Prima versione: 2026-11-01.*
