#!/usr/bin/env bash
# =============================================================
# Benchmark Radix Sort v5 — PARALELO (OpenMP) — cenário geral
#
# Mudanças em relação à v4 (detalhes no relatório LaTeX):
#  B1  Programa padrão: ./radix_paralelo_v3 (a v4 usava a v1 por padrão).
#  B2  Validação em TODAS as execuções (aquecimento, tempo e energia):
#        - código de saída = 0
#        - VERIFICACAO=OK informado pelo programa
#        - N_THREADS real = n_threads pedido
#        - saída idêntica (cmp byte a byte) a uma referência gerada
#          com GNU sort -n — independente do nosso código. Pega
#          saída truncada, desordenada ou com elementos trocados.
#      (A v4 validava só a 1ª repetição e seu teste em awk SEMPRE
#       retornava "SIM" por causa do bloco END.)
#  B3  Rodada(s) de aquecimento descartada(s) por configuração.
#  B4  Ordem das configurações de threads embaralhada a cada
#      repetição (evita viés de aquecimento térmico/ordem).
#  B5  Afinidade explícita: OMP_PROC_BIND=close (antes "true", cuja
#      política é definida pela implementação), OMP_DYNAMIC=false.
#  B6  LC_ALL=C (o perf em pt_BR imprime "1.234,56") e perf com
#      saída separada (-x ';' -o arquivo) — parsing robusto.
#  B7  sudo -v no início + renovação em segundo plano: a coleta de
#      energia não trava pedindo senha no meio do benchmark.
#  B8  CSV com tempos separados (leitura, sort, verificação, escrita)
#      e com threads pedidas x reais. CSVs com data/hora no nome
#      (não sobrescreve resultados anteriores).
#  B9  Checagem de espaço em disco, de pré-requisitos e resumo final
#      com mediana de tempo_sort_s e speedup relativo a 1 thread.
#  B10 Referência gerada com o GNU sort (gnusort no Ubuntu 26.04, cujo
#      sort padrão é o uutils/Rust e corrompeu a referência com -S) e
#      SEMPRE validada: nº de linhas, ordem e soma módulo 1e9+7.
#
# Uso:
#   ./benchmark_radix_par_v5.sh
#   THREADS="1 4 16" TAMANHOS="10000000" REPETICOES=3 ./benchmark_radix_par_v5.sh
#
# Variáveis (todas opcionais):
#   BASE_DIR      pasta de trabalho            (padrão: ~/Downloads)
#   PROGRAMA      executável                   (padrão: ./radix_paralelo_v3)
#   DIR_ENTRADAS  pasta das entradas           (padrão: arquivos_teste)
#   TAMANHOS      quantidades                  (padrão: 10000000 50000000 100000000)
#   THREADS       nº de threads                (padrão: 1 2 4 8 16 32)
#   REPETICOES    repetições medidas           (padrão: 10)
#   AQUECIMENTO   execuções descartadas/config (padrão: 1)
#   EMBARALHAR    1 = embaralha ordem threads  (padrão: 1)
#   ENERGIA       auto | 0                     (padrão: auto)
#   OMP_PROC_BIND close | spread | ...         (padrão: close)
#   OMP_PLACES    cores | threads | ...        (padrão: cores)
#   SORT_BIN      sort p/ a referência         (padrão: gnusort/GNU sort)
#
# Antes de rodar (recomendado):
#   sudo cpupower frequency-set -g performance
# =============================================================
set -uo pipefail

BASE_DIR="${BASE_DIR:-$HOME/Downloads}"
cd "$BASE_DIR" || { echo "Erro: pasta '$BASE_DIR' não encontrada"; exit 1; }

PROGRAMA="${PROGRAMA:-./radix_paralelo_v3}"
DIR_ENTRADAS="${DIR_ENTRADAS:-arquivos_teste}"
TAMANHOS="${TAMANHOS:-10000000 50000000 100000000}"
THREADS="${THREADS:-1 2 4 8 16 32}"
REPETICOES="${REPETICOES:-10}"
AQUECIMENTO="${AQUECIMENTO:-1}"
EMBARALHAR="${EMBARALHAR:-1}"
ENERGIA="${ENERGIA:-auto}"
DIR_REF="${DIR_REF:-referencias}"

STAMP="$(date +%Y%m%d_%H%M%S)"
CSV_TEMPO="metricas_radix_par_v5_${STAMP}.csv"
CSV_ENERGIA="energia_radix_par_v5_${STAMP}.csv"
AMBIENTE="ambiente_par_v5_${STAMP}.txt"
DIR_FALHAS="falhas_v5_${STAMP}"

export LC_ALL=C
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"
export OMP_DYNAMIC=false

# ---------------- funções utilitárias ----------------
erro() { echo "ERRO: $*" >&2; exit 1; }

eh_inteiro_positivo() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

valor() { sed -n "s/^$1=//p" "$2" | head -1; }                  # CHAVE=valor do programa
# campo do /usr/bin/time -v (delimitador '|' porque há campos com '/', ex.: "I/O")
campo_time() { sed -n "s|^[[:space:]]*$1: ||p" "$2" | head -1; }

segundos_elapsed() {   # "h:mm:ss" ou "m:ss.cc" -> segundos
    awk -F: '{ if (NF == 3) print $1*3600 + $2*60 + $3; else if (NF == 2) print $1*60 + $2; }' <<< "$1"
}

rotulo() {             # 10000000 -> 10M ; 1500000 -> 1500k (igual ao gerador Java)
    local n=$1
    if (( n % 1000000 == 0 )); then echo "$((n / 1000000))M"
    elif (( n % 1000 == 0 )); then echo "$((n / 1000))k"
    else echo "$n"; fi
}

lista_threads() {      # ordem das configurações numa repetição
    if [ "$EMBARALHAR" = "1" ]; then tr ' ' '\n' <<< "$THREADS" | grep -v '^$' | shuf | tr '\n' ' '
    else echo "$THREADS"; fi
}

# Registra falha, guarda o log e aborta
falhar() {   # $1=mensagem $2=log
    mkdir -p "$DIR_FALHAS"
    [ -n "${2:-}" ] && [ -f "$2" ] && cp "$2" "$DIR_FALHAS/"
    erro "$1 (log guardado em $DIR_FALHAS/)"
}

# Valida uma execução. $1=rc $2=log do programa $3=threads pedidas $4=rótulo
validar() {
    local rc=$1 log=$2 th=$3 id=$4
    [ "$rc" -eq 0 ] || falhar "[$id] programa terminou com código $rc: $(grep -m1 '^Erro' "$log")" "$log"
    [ "$(valor VERIFICACAO "$log")" = "OK" ] || falhar "[$id] programa não informou VERIFICACAO=OK" "$log"
    local nth; nth="$(valor N_THREADS "$log")"
    [ "$nth" = "$th" ] || falhar "[$id] pedidas $th threads, programa usou '$nth'" "$log"
    [ -f "$SAIDA" ] || falhar "[$id] arquivo de saída não foi criado" "$log"
    if ! cmp -s "$REF" "$SAIDA"; then
        falhar "[$id] saída difere da referência ($(wc -l < "$SAIDA") linhas; esperado $QUANTIDADE)" "$log"
    fi
}

# ---------------- pré-requisitos ----------------
[ -x "$PROGRAMA" ] || erro "programa '$PROGRAMA' não encontrado/executável"
[ -x /usr/bin/time ] || erro "/usr/bin/time não encontrado (Debian/Ubuntu: sudo apt install time)"
for cmd in cmp head wc shuf awk sed df; do
    command -v "$cmd" >/dev/null || erro "comando '$cmd' não encontrado"
done

# B10: sort usado na referência. O Ubuntu 26.04 usa por padrão o sort do
# uutils (Rust), que produziu referência corrompida (linha partida em duas)
# com -S. Preferimos o GNU sort (no Ubuntu 26.04: 'gnusort'); SORT_BIN
# permite escolher outro. A referência é sempre validada (ver abaixo).
escolher_sort() {
    if [ -n "${SORT_BIN:-}" ]; then echo "$SORT_BIN"; return; fi
    local c
    for c in gnusort gsort sort; do
        command -v "$c" >/dev/null && "$c" --version 2>/dev/null | head -1 | grep -q GNU && { echo "$c"; return; }
    done
    echo sort
}
SORT_BIN="$(escolher_sort)"
command -v "$SORT_BIN" >/dev/null || erro "comando de ordenação '$SORT_BIN' não encontrado"
# -S (tamanho do buffer) só no GNU sort: evita estourar a RAM com 100M e
# não é repassado ao uutils, cujo -S corrompeu a saída.
SORT_OPTS=()
"$SORT_BIN" --version 2>/dev/null | head -1 | grep -q GNU && SORT_OPTS=(-S 25%)
if ! "$SORT_BIN" --version 2>/dev/null | head -1 | grep -q GNU; then
    echo "AVISO: '$SORT_BIN' não é o GNU sort ($("$SORT_BIN" --version 2>/dev/null | head -1))."
    echo "       A referência será validada; se falhar, instale o GNU sort (Ubuntu 26.04: já vem como 'gnusort')."
fi

# Valida a referência de forma independente do sort:
# nº de linhas, ordem crescente e soma módulo 1e9+7 iguais aos da entrada.
validar_referencia() {   # <entrada> <referência> <quantidade>
    local ent=$1 ref=$2 q=$3 linhas ordem s_ent s_ref
    linhas=$(wc -l < "$ref")
    [ "$linhas" -eq "$q" ] || { echo "referência com $linhas linhas (esperado $q)"; return 1; }
    ordem=$(awk 'NR > 1 && $1 + 0 < ant { print "NAO"; nok = 1; exit } { ant = $1 + 0 } END { if (!nok) print "SIM" }' "$ref")
    [ "$ordem" = "SIM" ] || { echo "referência fora de ordem"; return 1; }
    s_ent=$(head -n "$q" "$ent" | awk '{ s = (s + $1) % 1000000007 } END { printf "%d", s }')
    s_ref=$(awk '{ s = (s + $1) % 1000000007 } END { printf "%d", s }' "$ref")
    [ "$s_ent" = "$s_ref" ] || { echo "referência com elementos diferentes da entrada"; return 1; }
    return 0
}
for v in $TAMANHOS; do eh_inteiro_positivo "$v" || erro "TAMANHOS contém valor inválido: '$v'"; done
for v in $THREADS;  do eh_inteiro_positivo "$v" || erro "THREADS contém valor inválido: '$v'"; done
eh_inteiro_positivo "$REPETICOES" || erro "REPETICOES inválido: '$REPETICOES'"
[[ "$AQUECIMENTO" =~ ^[0-9]+$ ]] || erro "AQUECIMENTO inválido: '$AQUECIMENTO'"

NPROC="$(nproc 2>/dev/null || echo '?')"
for v in $THREADS; do
    [ "$NPROC" != "?" ] && (( v > NPROC )) && echo "AVISO: $v threads > $NPROC CPUs lógicas (sobreinscrição)"
done

DIR_TRAB="$(mktemp -d "$BASE_DIR/.bench_v5_XXXXXX")" || erro "não foi possível criar pasta temporária"
SAIDA="$DIR_TRAB/saida_par.txt"
LOG="$DIR_TRAB/execucao.log"
KEEPALIVE_PID=""
limpar() {
    [ -n "$KEEPALIVE_PID" ] && kill "$KEEPALIVE_PID" 2>/dev/null
    rm -rf "$DIR_TRAB"
}
trap limpar EXIT
trap 'echo; echo "Interrompido."; exit 130' INT TERM

# ---------------- energia (perf/RAPL) ----------------
ENERGIA_OK=0
EVENTOS=""
if [ "$ENERGIA" != "0" ]; then
    if ! command -v perf >/dev/null 2>&1; then
        echo "AVISO: 'perf' não encontrado — coleta de energia será PULADA."
    elif ! sudo -v; then
        echo "AVISO: sem sudo — coleta de energia será PULADA."
    else
        for ev in power/energy-pkg/ power_core/energy-core/ power/energy-cores/; do
            sudo -n perf stat -e "$ev" true >/dev/null 2>&1 && EVENTOS="${EVENTOS:+$EVENTOS,}$ev"
        done
        if [ -z "$EVENTOS" ]; then
            echo "AVISO: contadores RAPL indisponíveis — coleta de energia será PULADA."
        else
            ENERGIA_OK=1
            # mantém o sudo válido durante todo o benchmark (B7)
            ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
            KEEPALIVE_PID=$!
            echo "Energia: eventos = $EVENTOS"
        fi
    fi
fi

# ---------------- registro do ambiente ----------------
{
  echo "data: $(date -Iseconds)"
  echo "script: benchmark_radix_par_v5.sh"
  echo "programa: $PROGRAMA"
  echo "sha256 programa: $(sha256sum "$PROGRAMA" 2>/dev/null | cut -d' ' -f1)"
  echo "host: $(uname -a)"
  gcc --version 2>/dev/null | head -1
  echo "nproc: $NPROC"
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
  echo "OMP_PROC_BIND=$OMP_PROC_BIND  OMP_PLACES=$OMP_PLACES  OMP_DYNAMIC=$OMP_DYNAMIC"
  echo "TAMANHOS=$TAMANHOS"
  echo "THREADS=$THREADS  REPETICOES=$REPETICOES  AQUECIMENTO=$AQUECIMENTO  EMBARALHAR=$EMBARALHAR"
  echo "sort da referência: $SORT_BIN ($("$SORT_BIN" --version 2>/dev/null | head -1))"
  echo "energia: $([ $ENERGIA_OK -eq 1 ] && echo "$EVENTOS" || echo 'não coletada')"
  echo "----- lscpu -----";   lscpu 2>/dev/null
  echo "----- memória -----"; free -h 2>/dev/null
  echo "----- disco -----";   df -h "$BASE_DIR" 2>/dev/null
} > "$AMBIENTE"
echo "Ambiente registrado em $AMBIENTE"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
[ -n "$GOV" ] && [ "$GOV" != "performance" ] && \
  echo "AVISO: governor='$GOV' (ideal: performance). Considere: sudo cpupower frequency-set -g performance"

echo "programa,versao,caso,repeticao,ordem_execucao,quantidade,n_threads_pedidas,n_threads_reais,n_passadas,tempo_leitura_s,tempo_sort_s,tempo_verificacao_s,tempo_escrita_s,tempo_decorrido_s,tempo_usuario_s,tempo_sistema_s,cpu_pct,tempo_time_s,memoria_max_kb,falhas_pagina_maiores,falhas_pagina_menores,trocas_voluntarias,trocas_involuntarias,data_hora" > "$CSV_TEMPO"
[ $ENERGIA_OK -eq 1 ] && echo "programa,caso,repeticao,ordem_execucao,quantidade,n_threads,energia_pkg_j,energia_core_j,tempo_sort_s,tempo_decorrido_s,data_hora" > "$CSV_ENERGIA"

mkdir -p "$DIR_REF"
ORDEM=0

# ---------------- laço principal ----------------
for QUANTIDADE in $TAMANHOS; do
    ROTULO="$(rotulo "$QUANTIDADE")"
    ENTRADA="$DIR_ENTRADAS/radix_geral_${ROTULO}.txt"
    REF="$DIR_REF/ref_${ROTULO}.txt"

    [ -f "$ENTRADA" ] || { echo "AVISO: '$ENTRADA' não existe — pulando $ROTULO"; continue; }

    # espaço em disco: saída (+ .tmp) ~ tamanho da entrada, + referência
    TAM_ENT_KB=$(( $(wc -c < "$ENTRADA") / 1024 ))
    LIVRE_KB=$(df -Pk "$BASE_DIR" | awk 'NR==2 {print $4}')
    NEC_KB=$(( TAM_ENT_KB * 3 + 102400 ))
    (( LIVRE_KB > NEC_KB )) || erro "espaço em disco insuficiente para $ROTULO: livre ${LIVRE_KB} KB, necessário ~${NEC_KB} KB"

    # referência independente (GNU sort), gerada uma vez e reutilizada
    if [ ! -s "$REF" ] || [ "$ENTRADA" -nt "$REF" ]; then
        LINHAS=$(wc -l < "$ENTRADA")
        (( LINHAS >= QUANTIDADE )) || erro "'$ENTRADA' tem $LINHAS linhas, menos que $QUANTIDADE"
        echo "Gerando referência $REF com '$SORT_BIN -n' (uma única vez)..."
        head -n "$QUANTIDADE" "$ENTRADA" | "$SORT_BIN" -n "${SORT_OPTS[@]}" > "$REF.tmp" \
            || { rm -f "$REF.tmp"; erro "falha ao gerar a referência $REF"; }
        if ! MOTIVO=$(validar_referencia "$ENTRADA" "$REF.tmp" "$QUANTIDADE"); then
            rm -f "$REF.tmp"
            erro "o '$SORT_BIN' gerou uma referência INVÁLIDA ($MOTIVO). Use o GNU sort: SORT_BIN=gnusort"
        fi
        mv "$REF.tmp" "$REF"
    else
        # referência já existente (ex.: gerada por versão antiga): revalida
        MOTIVO=$(validar_referencia "$ENTRADA" "$REF" "$QUANTIDADE") \
            || erro "referência existente $REF é inválida ($MOTIVO). Apague a pasta '$DIR_REF' e rode de novo"
    fi

    echo "=============================="
    echo "PARALELO v5 — geral — $ROTULO ($QUANTIDADE números)"
    echo "=============================="

    # ---- aquecimento (B3): executa e valida, não registra ----
    if (( AQUECIMENTO > 0 )); then
        for TH in $THREADS; do
            for ((a = 1; a <= AQUECIMENTO; a++)); do
                rm -f "$SAIDA"
                "$PROGRAMA" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$LOG"
                validar $? "$LOG" "$TH" "aquecimento $ROTULO/${TH}t"
            done
        done
        echo "  aquecimento concluído e validado ($AQUECIMENTO por configuração)"
    fi

    # ---- coleta de tempo/memória ----
    echo "  --- Coleta de tempo/memória ---"
    for ((i = 1; i <= REPETICOES; i++)); do
        for TH in $(lista_threads); do
            ORDEM=$((ORDEM + 1))
            rm -f "$SAIDA"
            /usr/bin/time -v "$PROGRAMA" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$LOG"
            RC=$?
            validar "$RC" "$LOG" "$TH" "tempo $ROTULO/${TH}t/rep$i"

            ELAPSED="$(segundos_elapsed "$(campo_time 'Elapsed (wall clock) time (h:mm:ss or m:ss)' "$LOG")")"
            CPU="$(campo_time 'Percent of CPU this job got' "$LOG" | tr -d '%')"
            echo "$PROGRAMA,$(valor VERSAO "$LOG"),geral,$i,$ORDEM,$QUANTIDADE,$TH,$(valor N_THREADS "$LOG"),$(valor N_PASSADAS "$LOG"),$(valor TEMPO_LEITURA_S "$LOG"),$(valor TEMPO_SORT_S "$LOG"),$(valor TEMPO_VERIFICACAO_S "$LOG"),$(valor TEMPO_ESCRITA_S "$LOG"),$(valor TEMPO_DECORRIDO_S "$LOG"),$(campo_time 'User time (seconds)' "$LOG"),$(campo_time 'System time (seconds)' "$LOG"),$CPU,$ELAPSED,$(campo_time 'Maximum resident set size (kbytes)' "$LOG"),$(campo_time 'Major (requiring I/O) page faults' "$LOG"),$(campo_time 'Minor (reclaiming a frame) page faults' "$LOG"),$(campo_time 'Voluntary context switches' "$LOG"),$(campo_time 'Involuntary context switches' "$LOG"),$(date -Iseconds)" >> "$CSV_TEMPO"
            printf "  rep %2d/%d  %2d threads  sort=%ss  OK\n" "$i" "$REPETICOES" "$TH" "$(valor TEMPO_SORT_S "$LOG")"
        done
    done

    # ---- coleta de energia ----
    if [ $ENERGIA_OK -eq 1 ]; then
        echo "  --- Coleta de energia ---"
        PERF_OUT="$DIR_TRAB/perf.txt"
        for ((i = 1; i <= REPETICOES; i++)); do
            for TH in $(lista_threads); do
                ORDEM=$((ORDEM + 1))
                rm -f "$SAIDA" "$PERF_OUT"
                sudo -n env LC_ALL=C OMP_PROC_BIND="$OMP_PROC_BIND" OMP_PLACES="$OMP_PLACES" OMP_DYNAMIC=false \
                    perf stat -x ';' -e "$EVENTOS" -o "$PERF_OUT" -- \
                    "$PROGRAMA" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$LOG"
                RC=$?
                validar "$RC" "$LOG" "$TH" "energia $ROTULO/${TH}t/rep$i"
                E_PKG=$(awk -F';' '$3 ~ /energy-pkg/ && $1 ~ /^[0-9.]+$/ {print $1; exit}' "$PERF_OUT")
                E_CORE=$(awk -F';' '$3 ~ /energy-core/ && $1 ~ /^[0-9.]+$/ {print $1; exit}' "$PERF_OUT")
                echo "$PROGRAMA,geral,$i,$ORDEM,$QUANTIDADE,$TH,$E_PKG,$E_CORE,$(valor TEMPO_SORT_S "$LOG"),$(valor TEMPO_DECORRIDO_S "$LOG"),$(date -Iseconds)" >> "$CSV_ENERGIA"
                printf "  rep %2d/%d  %2d threads  pkg=%sJ  OK\n" "$i" "$REPETICOES" "$TH" "${E_PKG:-NA}"
            done
        done
    fi
done

# ---------------- resumo: mediana de tempo_sort_s ----------------
echo ""
echo "Resumo — mediana de tempo_sort_s (speedup relativo a 1 thread da própria v3):"
printf "  %-12s %-8s %-4s %-14s %s\n" "quantidade" "threads" "n" "mediana_s" "speedup"
tail -n +2 "$CSV_TEMPO" | awk -F, '{print $6","$7","$11}' | sort -t, -k1,1n -k2,2n -k3,3g | awk -F, '
    function emite() {
        med = (n % 2) ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2
        if (th == 1) base[q] = med
        s = (q in base && med > 0) ? sprintf("%.2fx", base[q] / med) : "-"
        printf "  %-12s %-8s %-4d %-14.6f %s\n", q, th, n, med, s
    }
    { k = $1 "," $2
      if (k != ant && ant != "") emite()
      if (k != ant) { n = 0; ant = k; q = $1; th = $2 }
      v[++n] = $3 }
    END { if (ant != "") emite() }'

echo ""
echo "✔ Todas as execuções foram validadas contra a referência (GNU sort)."
echo "✔ Métricas de tempo salvas em: $CSV_TEMPO"
[ $ENERGIA_OK -eq 1 ] && echo "✔ Métricas de energia salvas em: $CSV_ENERGIA"
echo "✔ Ambiente registrado em: $AMBIENTE"
exit 0
