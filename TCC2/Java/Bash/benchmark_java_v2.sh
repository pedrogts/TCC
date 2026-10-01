#!/usr/bin/env bash
# =============================================================
# Benchmark Radix Sort — PARALELO (Java) — v2
#
# Mesmo método do benchmark_radix_par_v5.sh (C/OpenMP), para que a
# comparação C x Java seja justa. O CSV tem EXATAMENTE as mesmas
# colunas do v5: os dois arquivos podem ser concatenados e analisados
# juntos (a coluna "programa" distingue as linguagens).
#
# Correções em relação ao benchmark_java.sh (que seguia o v4):
#  J1  Validação em TODAS as execuções (aquecimento, tempo e energia):
#        - código de saída = 0
#        - VERIFICACAO=OK informado pelo programa
#        - N_THREADS real = n_threads pedido
#        - saída idêntica (cmp byte a byte) a uma referência gerada
#          com o GNU sort. O teste em awk do v4 SEMPRE aprovava
#          (o bloco END roda mesmo após o exit) e não conferia o
#          número de linhas.
#  J2  Referência gerada com o GNU sort (gnusort no Ubuntu 26.04, cujo
#      sort padrão é o uutils) e sempre validada: linhas, ordem e soma
#      módulo 1e9+7.
#  J3  Rodada(s) de aquecimento descartada(s) por configuração.
#  J4  Ordem das configurações de threads embaralhada a cada repetição.
#  J5  Afinidade por padrão (PIN=1): taskset nos N primeiros núcleos
#      FÍSICOS, equivalente ao OMP_PROC_BIND=close do lado C.
#  J6  Heap fixo por padrão (-Xms = -Xmx): evita o heap crescer no meio
#      da medição. Registra JAVA_OPTS e a versão da JVM no ambiente.
#  J7  Tempos por fase no CSV (leitura, sort, verificação, escrita) e
#      threads pedidas x reais; CSVs com data/hora no nome.
#  J8  perf com -x ';' -o arquivo (parsing robusto) e sudo -v renovado
#      em segundo plano.
#  J9  Checagem de pré-requisitos, de espaço em disco e resumo final
#      com mediana de tempo_sort_s e speedup relativo a 1 thread.
#
# Uso:
#   bash benchmark_java_v2.sh
#   bash benchmark_java_v2.sh 1 4 16
#   THREADS="1 4 16" TAMANHOS="10000000" REPETICOES=3 bash benchmark_java_v2.sh
#
# Variáveis (todas opcionais):
#   SRC_DIR       pasta dos .java        (padrão: ../RadixSort, senão a pasta do script)
#   GEN_DIR       pasta do gerador       (padrão: ../../Gerador de Arquivos, senão a do script)
#   DIR_ENTRADAS  pasta das entradas     (padrão: $GEN_DIR/arquivos_teste)
#   MAIN_CLASS    classe principal       (padrão: detectada automaticamente)
#   TAMANHOS      quantidades            (padrão: 10000000 50000000 100000000)
#   THREADS       nº de threads          (padrão: 1 2 4 8 16 32)
#   REPETICOES    repetições medidas     (padrão: 10)
#   AQUECIMENTO   execuções descartadas  (padrão: 1)
#   EMBARALHAR    1 = embaralha ordem    (padrão: 1)
#   ENERGIA       auto | 0               (padrão: auto)
#   PIN           1 = taskset | 0        (padrão: 1)
#   JAVA_OPTS     opções da JVM          (padrão: -Xms4g -Xmx4g)
#   SORT_BIN      sort da referência     (padrão: gnusort/GNU sort)
#
# Antes de rodar:  sudo cpupower frequency-set -g performance
# =============================================================
set -uo pipefail
export LC_ALL=C

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------- funções utilitárias ----------------
erro() { echo "ERRO: $*" >&2; exit 1; }
eh_inteiro_positivo() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
valor() { sed -n "s/^$1=//p" "$2" | head -1; }
campo_time() { sed -n "s|^[[:space:]]*$1: ||p" "$2" | head -1; }   # '|' por causa de "I/O"
segundos_elapsed() {
    awk -F: '{ if (NF == 3) print $1*3600 + $2*60 + $3; else if (NF == 2) print $1*60 + $2; }' <<< "$1"
}
rotulo() {
    local n=$1
    if (( n % 1000000 == 0 )); then echo "$((n / 1000000))M"
    elif (( n % 1000 == 0 )); then echo "$((n / 1000))k"
    else echo "$n"; fi
}

# ---------------- parâmetros ----------------
SRC_DIR="${SRC_DIR:-$AQUI/../RadixSort}"
GEN_DIR="${GEN_DIR:-$AQUI/../../Gerador de Arquivos}"
[ -d "$SRC_DIR" ] || SRC_DIR="$AQUI"
[ -d "$GEN_DIR" ] || GEN_DIR="$AQUI"
SRC_DIR="$(cd "$SRC_DIR" && pwd)" || erro "pasta dos fontes não encontrada (SRC_DIR)"
GEN_DIR="$(cd "$GEN_DIR" && pwd)" || erro "pasta do gerador não encontrada (GEN_DIR)"

DIR_ENTRADAS="${DIR_ENTRADAS:-$GEN_DIR/arquivos_teste}"
DIR_REF="${DIR_REF:-$AQUI/referencias}"
TAMANHOS="${TAMANHOS:-10000000 50000000 100000000}"
REPETICOES="${REPETICOES:-10}"
AQUECIMENTO="${AQUECIMENTO:-1}"
EMBARALHAR="${EMBARALHAR:-1}"
ENERGIA="${ENERGIA:-auto}"
PIN="${PIN:-1}"
JAVA_OPTS="${JAVA_OPTS:--Xms4g -Xmx4g}"
TIME_BIN="${TIME_BIN:-/usr/bin/time}"

if [ $# -gt 0 ]; then THREADS="$*"; fi
THREADS="${THREADS:-1 2 4 8 16 32}"

STAMP="$(date +%Y%m%d_%H%M%S)"
CSV_TEMPO="$AQUI/metricas_radix_java_v2_${STAMP}.csv"
CSV_ENERGIA="$AQUI/energia_radix_java_v2_${STAMP}.csv"
AMBIENTE="$AQUI/ambiente_java_v2_${STAMP}.txt"
DIR_FALHAS="$AQUI/falhas_java_v2_${STAMP}"
PROGRAMA_ROTULO="java_paralelo"

# ---------------- pré-requisitos ----------------
command -v javac >/dev/null && command -v java >/dev/null || erro "java/javac não encontrados no PATH"
[ -x "$TIME_BIN" ] || erro "'$TIME_BIN' não encontrado (Debian/Ubuntu: sudo apt install time)"
for cmd in cmp head wc shuf awk sed df; do
    command -v "$cmd" >/dev/null || erro "comando '$cmd' não encontrado"
done
for v in $TAMANHOS; do eh_inteiro_positivo "$v" || erro "TAMANHOS contém valor inválido: '$v'"; done
for v in $THREADS;  do eh_inteiro_positivo "$v" || erro "THREADS contém valor inválido: '$v'"; done
eh_inteiro_positivo "$REPETICOES" || erro "REPETICOES inválido: '$REPETICOES'"
[[ "$AQUECIMENTO" =~ ^[0-9]+$ ]] || erro "AQUECIMENTO inválido: '$AQUECIMENTO'"

# J2: GNU sort para a referência
escolher_sort() {
    if [ -n "${SORT_BIN:-}" ]; then echo "$SORT_BIN"; return; fi
    local c
    for c in gnusort gsort sort; do
        command -v "$c" >/dev/null && "$c" --version 2>/dev/null | head -1 | grep -q GNU && { echo "$c"; return; }
    done
    echo sort
}
SORT_BIN="$(escolher_sort)"
SORT_OPTS=()
"$SORT_BIN" --version 2>/dev/null | head -1 | grep -q GNU && SORT_OPTS=(-S 25%) || {
    echo "AVISO: '$SORT_BIN' não é o GNU sort. A referência será validada; se falhar, use SORT_BIN=gnusort."
}

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

NPROC="$(nproc 2>/dev/null || echo '?')"
for v in $THREADS; do
    [ "$NPROC" != "?" ] && (( v > NPROC )) && echo "AVISO: $v threads > $NPROC CPUs lógicas (sobreinscrição)"
done

DIR_TRAB="$(mktemp -d "$AQUI/.bench_java_XXXXXX")" || erro "não foi possível criar pasta temporária"
SAIDA="$DIR_TRAB/saida_java.txt"
LOG="$DIR_TRAB/execucao.log"
KEEPALIVE_PID=""
limpar() {
    [ -n "$KEEPALIVE_PID" ] && kill "$KEEPALIVE_PID" 2>/dev/null
    rm -rf "$DIR_TRAB"
}
trap limpar EXIT
trap 'echo; echo "Interrompido."; exit 130' INT TERM

# ---------------- compilação (mesma lógica do script original) ----------------
CLASSES="$AQUI/classes"
BUILD_SRC="$DIR_TRAB/build_src"
shopt -s nullglob
ORIGINAIS=("$SRC_DIR"/*.java)
[ ${#ORIGINAIS[@]} -gt 0 ] || erro "nenhum .java encontrado em $SRC_DIR"
rm -rf "$CLASSES"; mkdir -p "$CLASSES" "$BUILD_SRC"
FONTES=()
for F in "${ORIGINAIS[@]}"; do
    NOME=$(grep -m1 -oE 'public[[:space:]]+(final[[:space:]]+|abstract[[:space:]]+)*class[[:space:]]+[A-Za-z0-9_]+' "$F" | awk '{print $NF}')
    [ -z "$NOME" ] && NOME=$(basename "$F" .java)
    cp "$F" "$BUILD_SRC/$NOME.java"
    FONTES+=("$BUILD_SRC/$NOME.java")
done

MAIN_CLASS="${MAIN_CLASS:-MainRadixSortParalelo}"
if [ ! -f "$BUILD_SRC/$MAIN_CLASS.java" ]; then
    MAIN_FILE=$(grep -l "public static void main" "${FONTES[@]}" | head -n1)
    [ -n "$MAIN_FILE" ] || erro "nenhuma classe com main em $SRC_DIR (use MAIN_CLASS=Nome)"
    MAIN_CLASS=$(basename "$MAIN_FILE" .java)
fi

GERADOR="$GEN_DIR/GeradorArquivosRadixV2.java"
[ -f "$GERADOR" ] && FONTES+=("$GERADOR")

echo "Fontes: $SRC_DIR (main: $MAIN_CLASS)"
echo "Compilando..."
javac -d "$CLASSES" "${FONTES[@]}" || erro "falha na compilação"

# shellcheck disable=SC2206
JAVA_CMD=("$(command -v java)" $JAVA_OPTS -cp "$CLASSES" "$MAIN_CLASS")

# ---------------- J5: afinidade com taskset ----------------
PIN_PREFIX=()
montar_pin() {   # $1 = nº de threads
    PIN_PREFIX=()
    [ "$PIN" = "1" ] || return 0
    command -v taskset >/dev/null || { echo "AVISO: taskset não encontrado — sem afinidade"; return 0; }
    local nucleos nc lista
    nucleos=$(lscpu -p=CPU,CORE,SOCKET 2>/dev/null | grep -v '^#' | awk -F, '!v[$2","$3]++ {print $1}')
    nc=$(echo "$nucleos" | grep -c .)
    if [ "$1" -le "$nc" ]; then
        lista=$(echo "$nucleos" | head -n "$1" | paste -sd,)
    else
        lista=$(lscpu -p=CPU 2>/dev/null | grep -v '^#' | head -n "$1" | paste -sd,)
    fi
    [ -n "$lista" ] && PIN_PREFIX=(taskset -c "$lista")
}

# ---------------- energia ----------------
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
            ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) >/dev/null 2>&1 &
            KEEPALIVE_PID=$!
            echo "Energia: eventos = $EVENTOS"
        fi
    fi
fi

# ---------------- entradas que faltam ----------------
mkdir -p "$DIR_ENTRADAS" "$DIR_REF"
for QUANTIDADE in $TAMANHOS; do
    ARQ="$DIR_ENTRADAS/radix_geral_$(rotulo "$QUANTIDADE").txt"
    if [ ! -f "$ARQ" ] && [ -f "$GERADOR" ]; then
        echo "Gerando $ARQ ..."
        ( cd "$GEN_DIR" && java -cp "$CLASSES" GeradorArquivosRadixV2 "$QUANTIDADE" ) || erro "falha ao gerar $ARQ"
    fi
done

# ---------------- ambiente ----------------
{
  echo "data: $(date -Iseconds)"
  echo "script: benchmark_java_v2.sh"
  echo "fontes: $SRC_DIR  (main: $MAIN_CLASS)"
  echo "sha256 fontes: $(cat "${ORIGINAIS[@]}" | sha256sum | cut -d' ' -f1)"
  echo "host: $(uname -a)"
  java -version 2>&1 | head -3
  echo "JAVA_OPTS=$JAVA_OPTS"
  echo "nproc: $NPROC"
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
  echo "PIN=$PIN (taskset nos núcleos físicos; equivalente a OMP_PROC_BIND=close)"
  echo "TAMANHOS=$TAMANHOS"
  echo "THREADS=$THREADS  REPETICOES=$REPETICOES  AQUECIMENTO=$AQUECIMENTO  EMBARALHAR=$EMBARALHAR"
  echo "sort da referência: $SORT_BIN ($("$SORT_BIN" --version 2>/dev/null | head -1))"
  echo "energia: $([ $ENERGIA_OK -eq 1 ] && echo "$EVENTOS" || echo 'não coletada')"
  echo "----- lscpu -----";   lscpu 2>/dev/null
  echo "----- memória -----"; free -h 2>/dev/null
  echo "----- disco -----";   df -h "$AQUI" 2>/dev/null
} > "$AMBIENTE"
echo "Ambiente registrado em $AMBIENTE"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
[ -n "$GOV" ] && [ "$GOV" != "performance" ] && \
  echo "AVISO: governor='$GOV' (ideal: performance). Considere: sudo cpupower frequency-set -g performance"

# mesmas colunas do benchmark_radix_par_v5.sh (os CSVs podem ser concatenados)
echo "programa,versao,caso,repeticao,ordem_execucao,quantidade,n_threads_pedidas,n_threads_reais,n_passadas,tempo_leitura_s,tempo_sort_s,tempo_verificacao_s,tempo_escrita_s,tempo_decorrido_s,tempo_usuario_s,tempo_sistema_s,cpu_pct,tempo_time_s,memoria_max_kb,falhas_pagina_maiores,falhas_pagina_menores,trocas_voluntarias,trocas_involuntarias,data_hora" > "$CSV_TEMPO"
[ $ENERGIA_OK -eq 1 ] && echo "programa,caso,repeticao,ordem_execucao,quantidade,n_threads,energia_pkg_j,energia_core_j,tempo_sort_s,tempo_decorrido_s,data_hora" > "$CSV_ENERGIA"

# ---------------- validação (J1) ----------------
falhar() {   # $1=mensagem $2=log
    mkdir -p "$DIR_FALHAS"
    [ -n "${2:-}" ] && [ -f "$2" ] && cp "$2" "$DIR_FALHAS/"
    erro "$1 (log guardado em $DIR_FALHAS/)"
}
validar() {   # $1=rc $2=log $3=threads pedidas $4=rótulo
    local rc=$1 log=$2 th=$3 id=$4 nth
    [ "$rc" -eq 0 ] || falhar "[$id] programa terminou com código $rc: $(grep -m1 -E '^(Erro|Exception|java\.)' "$log")" "$log"
    [ "$(valor VERIFICACAO "$log")" = "OK" ] || falhar "[$id] programa não informou VERIFICACAO=OK" "$log"
    nth="$(valor N_THREADS "$log")"
    [ "$nth" = "$th" ] || falhar "[$id] pedidas $th threads, programa usou '$nth'" "$log"
    [ -f "$SAIDA" ] || falhar "[$id] arquivo de saída não foi criado" "$log"
    cmp -s "$REF" "$SAIDA" || falhar "[$id] saída difere da referência ($(wc -l < "$SAIDA") linhas; esperado $QUANTIDADE)" "$log"
}
lista_threads() {
    if [ "$EMBARALHAR" = "1" ]; then tr ' ' '\n' <<< "$THREADS" | grep -v '^$' | shuf | tr '\n' ' '
    else echo "$THREADS"; fi
}

ORDEM=0

# ---------------- laço principal ----------------
for QUANTIDADE in $TAMANHOS; do
    ROTULO="$(rotulo "$QUANTIDADE")"
    ENTRADA="$DIR_ENTRADAS/radix_geral_${ROTULO}.txt"
    REF="$DIR_REF/ref_${ROTULO}.txt"

    [ -f "$ENTRADA" ] || { echo "AVISO: '$ENTRADA' não existe — pulando $ROTULO"; continue; }

    TAM_ENT_KB=$(( $(wc -c < "$ENTRADA") / 1024 ))
    LIVRE_KB=$(df -Pk "$AQUI" | awk 'NR==2 {print $4}')
    (( LIVRE_KB > TAM_ENT_KB * 3 + 102400 )) || erro "espaço em disco insuficiente para $ROTULO"

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
        MOTIVO=$(validar_referencia "$ENTRADA" "$REF" "$QUANTIDADE") \
            || erro "referência existente $REF é inválida ($MOTIVO). Apague a pasta '$DIR_REF' e rode de novo"
    fi

    echo "=============================="
    echo "PARALELO (Java) — geral — $ROTULO ($QUANTIDADE números)"
    echo "=============================="

    # ---- J3: aquecimento, validado e descartado ----
    if (( AQUECIMENTO > 0 )); then
        for TH in $THREADS; do
            montar_pin "$TH"
            for ((a = 1; a <= AQUECIMENTO; a++)); do
                rm -f "$SAIDA"
                ${PIN_PREFIX[@]+"${PIN_PREFIX[@]}"} "${JAVA_CMD[@]}" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$LOG"
                validar $? "$LOG" "$TH" "aquecimento $ROTULO/${TH}t"
            done
        done
        echo "  aquecimento concluído e validado ($AQUECIMENTO por configuração)"
    fi

    # ---- coleta de tempo/memória ----
    echo "  --- Coleta de tempo/memória ---"
    for ((i = 1; i <= REPETICOES; i++)); do
        for TH in $(lista_threads); do
            montar_pin "$TH"
            ORDEM=$((ORDEM + 1))
            rm -f "$SAIDA"
            "$TIME_BIN" -v ${PIN_PREFIX[@]+"${PIN_PREFIX[@]}"} "${JAVA_CMD[@]}" \
                "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$LOG"
            RC=$?
            validar "$RC" "$LOG" "$TH" "tempo $ROTULO/${TH}t/rep$i"

            ELAPSED="$(segundos_elapsed "$(campo_time 'Elapsed (wall clock) time (h:mm:ss or m:ss)' "$LOG")")"
            CPU="$(campo_time 'Percent of CPU this job got' "$LOG" | tr -d '%')"
            echo "$PROGRAMA_ROTULO,$(valor VERSAO "$LOG"),geral,$i,$ORDEM,$QUANTIDADE,$TH,$(valor N_THREADS "$LOG"),$(valor N_PASSADAS "$LOG"),$(valor TEMPO_LEITURA_S "$LOG"),$(valor TEMPO_SORT_S "$LOG"),$(valor TEMPO_VERIFICACAO_S "$LOG"),$(valor TEMPO_ESCRITA_S "$LOG"),$(valor TEMPO_DECORRIDO_S "$LOG"),$(campo_time 'User time (seconds)' "$LOG"),$(campo_time 'System time (seconds)' "$LOG"),$CPU,$ELAPSED,$(campo_time 'Maximum resident set size (kbytes)' "$LOG"),$(campo_time 'Major (requiring I/O) page faults' "$LOG"),$(campo_time 'Minor (reclaiming a frame) page faults' "$LOG"),$(campo_time 'Voluntary context switches' "$LOG"),$(campo_time 'Involuntary context switches' "$LOG"),$(date -Iseconds)" >> "$CSV_TEMPO"
            printf "  rep %2d/%d  %2d threads  sort=%ss  OK\n" "$i" "$REPETICOES" "$TH" "$(valor TEMPO_SORT_S "$LOG")"
        done
    done

    # ---- coleta de energia ----
    if [ $ENERGIA_OK -eq 1 ]; then
        echo "  --- Coleta de energia ---"
        PERF_OUT="$DIR_TRAB/perf.txt"
        for ((i = 1; i <= REPETICOES; i++)); do
            for TH in $(lista_threads); do
                montar_pin "$TH"
                ORDEM=$((ORDEM + 1))
                rm -f "$SAIDA" "$PERF_OUT"
                sudo -n env LC_ALL=C perf stat -x ';' -e "$EVENTOS" -o "$PERF_OUT" -- \
                    ${PIN_PREFIX[@]+"${PIN_PREFIX[@]}"} "${JAVA_CMD[@]}" \
                    "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$LOG"
                RC=$?
                validar "$RC" "$LOG" "$TH" "energia $ROTULO/${TH}t/rep$i"
                E_PKG=$(awk -F';' '$3 ~ /energy-pkg/ && $1 ~ /^[0-9.]+$/ {print $1; exit}' "$PERF_OUT")
                E_CORE=$(awk -F';' '$3 ~ /energy-core/ && $1 ~ /^[0-9.]+$/ {print $1; exit}' "$PERF_OUT")
                echo "$PROGRAMA_ROTULO,geral,$i,$ORDEM,$QUANTIDADE,$TH,$E_PKG,$E_CORE,$(valor TEMPO_SORT_S "$LOG"),$(valor TEMPO_DECORRIDO_S "$LOG"),$(date -Iseconds)" >> "$CSV_ENERGIA"
                printf "  rep %2d/%d  %2d threads  pkg=%sJ  OK\n" "$i" "$REPETICOES" "$TH" "${E_PKG:-NA}"
            done
        done
    fi
done

# ---------------- resumo ----------------
echo ""
echo "Resumo — mediana de tempo_sort_s (speedup relativo a 1 thread do próprio Java):"
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
echo "✔ Todas as execuções foram validadas contra a referência ($SORT_BIN)."
echo "✔ Métricas de tempo salvas em: $CSV_TEMPO"
[ $ENERGIA_OK -eq 1 ] && echo "✔ Métricas de energia salvas em: $CSV_ENERGIA"
echo "✔ Ambiente registrado em: $AMBIENTE"
echo ""
echo "Para comparar com o C: as colunas são as mesmas do benchmark_radix_par_v5.sh."
echo "  cat metricas_radix_par_v5_*.csv  > tudo.csv"
echo "  tail -q -n +2 metricas_radix_java_v2_*.csv >> tudo.csv"
exit 0
