#!/bin/bash
# =============================================================
# Benchmark Radix Sort — PARALELO (Java) — cenário geral
#
# Mesmo método do benchmark_radix_par_v4.sh (C/OpenMP), para a
# comparação C x Java ser justa:
#   - duas fases por configuração: (1) tempo/memória com
#     /usr/bin/time -v; (2) energia com perf stat
#     (power/energy-pkg/ e power_core/energy-core/, via sudo)
#   - mesmos CSVs, mesmas colunas, mesmo ambiente registrado
#   - mesma validação (diff com saida_seq_<TAM>.txt ou teste de ordem)
#   - energia do processo inteiro, sem subtrair consumo ocioso
#
# Diferenças inevitáveis (Java não é OpenMP):
#   - sem OMP_PROC_BIND/OMP_PLACES; use PIN=1 para restringir o
#     processo a N núcleos físicos com taskset (aproximação)
#   - a memória máxima inclui o heap da JVM
#
# Uso:
#   bash benchmark_java.sh                 (pergunta as threads)
#   bash benchmark_java.sh 1 4 16          (threads como argumento)
#   THREADS="1 4 16" TAMANHOS="10000000" REPETICOES=3 bash benchmark_java.sh
#
# Variáveis: TAMANHOS THREADS REPETICOES JAVA_OPTS PIN MAIN_CLASS
#            SRC_DIR GEN_DIR REF_DIR
#
# Antes de rodar (medições estáveis):
#   sudo cpupower frequency-set -g performance
# =============================================================

BASH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SRC_DIR:-$BASH_DIR/../RadixSort}"
GEN_DIR="${GEN_DIR:-$BASH_DIR/../../Gerador de Arquivos}"
SRC_DIR="$(cd "$SRC_DIR" 2>/dev/null && pwd)" || { echo "Erro: pasta do radix não encontrada (SRC_DIR)"; exit 1; }
GEN_DIR="$(cd "$GEN_DIR" 2>/dev/null && pwd)" || { echo "Erro: pasta do gerador não encontrada (GEN_DIR)"; exit 1; }

export LC_ALL=C

DIR_ENTRADAS="${DIR_ENTRADAS:-$GEN_DIR/arquivos_teste}"
REF_DIR="${REF_DIR:-$BASH_DIR}"
TAMANHOS="${TAMANHOS:-10000000 50000000 100000000}"
REPETICOES="${REPETICOES:-10}"
JAVA_OPTS="${JAVA_OPTS:--Xmx4g}"
PIN="${PIN:-0}"
TIME_BIN="${TIME_BIN:-/usr/bin/time}"

if [ $# -gt 0 ]; then
    THREADS="$*"
elif [ -z "${THREADS:-}" ]; then
    if [ -t 0 ]; then
        read -r -p "Quantas threads? (ex: 4  ou  1 2 4 8 16 32) [1 2 4 8 16 32]: " RESP
        THREADS="${RESP:-1 2 4 8 16 32}"
    else
        THREADS="1 2 4 8 16 32"
    fi
fi
for T in $THREADS; do
    if ! [[ "$T" =~ ^[0-9]+$ ]] || [ "$T" -lt 1 ] || [ "$T" -gt 1024 ]; then
        echo "Erro: número de threads inválido: '$T' (esperado inteiro entre 1 e 1024)"; exit 1
    fi
done

CLASSES="$BASH_DIR/classes"
BUILD_SRC="$BASH_DIR/build_src"
CSV_TEMPO="$BASH_DIR/metricas_radix_java.csv"
CSV_ENERGIA="$BASH_DIR/energia_radix_java.csv"
AMBIENTE="$BASH_DIR/ambiente_java.txt"
SAIDA="$BASH_DIR/saida_java.txt"
PROGRAMA_ROTULO="java_paralelo"

command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1 || { echo "Erro: java/javac não encontrados no PATH"; exit 1; }
[ -x "$TIME_BIN" ] || { echo "Erro: '$TIME_BIN' não encontrado (instale: sudo apt install time)"; exit 1; }
JAVA_BIN="$(command -v java)"

# --- compilação (copia cada .java com o nome da sua classe pública) ---
shopt -s nullglob
ORIGINAIS=("$SRC_DIR"/*.java)
[ ${#ORIGINAIS[@]} -gt 0 ] || { echo "Erro: nenhum .java encontrado em $SRC_DIR"; exit 1; }
rm -rf "$BUILD_SRC" "$CLASSES"
mkdir -p "$BUILD_SRC" "$CLASSES"
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
    [ -n "$MAIN_FILE" ] || { echo "Erro: nenhuma classe com main em $SRC_DIR (use MAIN_CLASS=Nome)"; exit 1; }
    MAIN_CLASS=$(basename "$MAIN_FILE" .java)
fi

GERADOR="$GEN_DIR/GeradorArquivosRadixV2.java"
[ -f "$GERADOR" ] && FONTES+=("$GERADOR")

echo "Radix: $SRC_DIR (main: $MAIN_CLASS)"
echo "Compilando..."
javac -d "$CLASSES" "${FONTES[@]}" || { echo "Erro: falha na compilação"; exit 1; }

JAVA_CMD=("$JAVA_BIN" $JAVA_OPTS -cp "$CLASSES" "$MAIN_CLASS")

# --- gera entradas que faltam ---
mkdir -p "$DIR_ENTRADAS"
for QUANTIDADE in $TAMANHOS; do
    ROTULO="$QUANTIDADE"
    [ $((QUANTIDADE % 1000000)) -eq 0 ] && ROTULO="$((QUANTIDADE / 1000000))M"
    ARQ="$DIR_ENTRADAS/radix_geral_${ROTULO}.txt"
    if [ ! -f "$ARQ" ]; then
        if [ -f "$GERADOR" ]; then
            echo "Gerando $ARQ ..."
            (cd "$GEN_DIR" && java -cp "$CLASSES" GeradorArquivosRadixV2 "$QUANTIDADE") || { echo "Erro: falha ao gerar $ARQ"; exit 1; }
        else
            echo "AVISO: '$ARQ' não existe e o gerador não foi encontrado — $ROTULO será pulado"
        fi
    fi
done

# --- registro do ambiente (reprodutibilidade) ---
{
  echo "data: $(date -Iseconds)"
  echo "host: $(uname -a)"
  java -version 2>&1 | head -1
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
  echo "JAVA_OPTS=$JAVA_OPTS  PIN=$PIN  MAIN_CLASS=$MAIN_CLASS"
  echo "----- lscpu -----"
  lscpu
  echo "----- memória -----"
  free -h
} > "$AMBIENTE"
echo "Ambiente registrado em $AMBIENTE"

GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
[ -n "$GOV" ] && [ "$GOV" != "performance" ] && \
  echo "AVISO: governor='$GOV' (ideal: performance). Considere: sudo cpupower frequency-set -g performance"

echo "programa,caso,repeticao,quantidade,n_threads,tempo_sort_s,tempo_usuario_s,tempo_sistema_s,cpu_pct,tempo_decorrido_s,memoria_max_kb,falhas_pagina_menores,trocas_voluntarias,trocas_involuntarias" > "$CSV_TEMPO"
echo "programa,caso,repeticao,quantidade,n_threads,energia_pkg_j,energia_core_j" > "$CSV_ENERGIA"

extrair_time()              { grep "$2" "$1" | grep -oP '[\d\.]+' | head -1; }
extrair_tempo_sort()        { grep "TEMPO_SORT_S" "$1" | grep -oP '[\d\.]+' | head -1; }
extrair_tempo_decorrido_interno() { grep "TEMPO_DECORRIDO_S" "$1" | grep -oP '[\d\.]+' | head -1; }
extrair_tempo_decorrido() {
    grep "Elapsed" "$1" | grep -oP '(\d+:)?\d+:\d+\.\d+' | head -1 | awk -F: '{
        if (NF == 3) print ($1*3600) + ($2*60) + $3
        else print ($1*60) + $2
    }'
}
extrair_perf_energia() { grep "$2" "$1" | grep -oP '[\d\.,]+(?=\s+Joules)' | sed 's|,|.|' | head -1; }

# taskset opcional: restringe o processo a N núcleos físicos (só se N <= nº de núcleos)
PIN_PREFIX=()
montar_pin() {
    PIN_PREFIX=()
    [ "$PIN" = "1" ] || return 0
    command -v taskset >/dev/null 2>&1 || return 0
    local NUCLEOS LISTA NC
    NUCLEOS=$(lscpu -p=CPU,CORE,SOCKET 2>/dev/null | grep -v '^#' | awk -F, '!v[$2","$3]++ {print $1}')
    NC=$(echo "$NUCLEOS" | grep -c .)
    if [ "$1" -le "$NC" ]; then
        LISTA=$(echo "$NUCLEOS" | head -n "$1" | paste -sd,)
        PIN_PREFIX=(taskset -c "$LISTA")
    fi
}

# perf de energia disponível?
ENERGIA_OK=1
if ! command -v perf >/dev/null 2>&1; then
    echo "AVISO: 'perf' não encontrado — coleta de energia será PULADA."
    ENERGIA_OK=0
elif ! sudo perf stat -e power/energy-pkg/ true 2>/dev/null; then
    echo "AVISO: contadores RAPL indisponíveis — coleta de energia será PULADA."
    ENERGIA_OK=0
fi

for QUANTIDADE in $TAMANHOS; do
    ROTULO="$QUANTIDADE"
    [ $((QUANTIDADE % 1000000)) -eq 0 ] && ROTULO="$((QUANTIDADE / 1000000))M"
    ENTRADA="$DIR_ENTRADAS/radix_geral_${ROTULO}.txt"
    REF_SEQ="$REF_DIR/saida_seq_${ROTULO}.txt"

    [ -f "$ENTRADA" ] || { echo "AVISO: '$ENTRADA' não existe — pulando $ROTULO"; continue; }

    for TH in $THREADS; do
        montar_pin "$TH"
        echo "=============================="
        echo "PARALELO (Java) — geral — $ROTULO ($QUANTIDADE números) — $TH thread(s)"
        echo "=============================="

        echo "  --- Coleta de tempo/memória ---"
        for i in $(seq 1 "$REPETICOES"); do
            echo "  Repetição $i/$REPETICOES..."
            TMP_TIME=$(mktemp)
            "$TIME_BIN" -v ${PIN_PREFIX[@]+"${PIN_PREFIX[@]}"} "${JAVA_CMD[@]}" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$TMP_TIME"

            TEMPO_SORT=$(extrair_tempo_sort "$TMP_TIME")
            TEMPO_USER=$(extrair_time "$TMP_TIME" "User time")
            TEMPO_SYS=$(extrair_time "$TMP_TIME" "System time")
            CPU=$(extrair_time "$TMP_TIME" "Percent of CPU")
            TEMPO_DEC=$(extrair_tempo_decorrido_interno "$TMP_TIME")
            [ -z "$TEMPO_DEC" ] && TEMPO_DEC=$(extrair_tempo_decorrido "$TMP_TIME")
            MEM=$(extrair_time "$TMP_TIME" "Maximum resident")
            FALHAS=$(extrair_time "$TMP_TIME" "Minor")
            TROCAS_V=$(extrair_time "$TMP_TIME" "Voluntary context")
            TROCAS_I=$(extrair_time "$TMP_TIME" "Involuntary context")

            if [ -z "$TEMPO_SORT" ]; then
                echo "ERRO: execução falhou (sem TEMPO_SORT_S). Últimas linhas:"
                tail -n 8 "$TMP_TIME" | sed 's/^/      /'
                rm -f "$TMP_TIME"; exit 1
            fi

            echo "$PROGRAMA_ROTULO,geral,$i,$QUANTIDADE,$TH,$TEMPO_SORT,$TEMPO_USER,$TEMPO_SYS,$CPU,$TEMPO_DEC,$MEM,$FALHAS,$TROCAS_V,$TROCAS_I" >> "$CSV_TEMPO"
            rm -f "$TMP_TIME"

            # validação de corretude (1ª repetição de cada configuração)
            if [ "$i" -eq 1 ]; then
                if [ -f "$REF_SEQ" ]; then
                    if diff -q "$REF_SEQ" "$SAIDA" >/dev/null; then
                        echo "    validação: idêntica à saída sequencial (diff OK)"
                    else
                        echo "ERRO: saída difere da sequencial ($ROTULO, $TH threads) — abortando"; exit 1
                    fi
                else
                    ORDENADO=$(awk 'NR>1 && $0+0 < ant {print "NAO"; exit} {ant=$0+0} END {print "SIM"}' "$SAIDA" | tail -1)
                    echo "    validação: sem $REF_SEQ; teste de ordenação=$ORDENADO"
                    [ "$ORDENADO" = "SIM" ] || { echo "ERRO: saída NÃO ordenada — abortando"; exit 1; }
                fi
            fi
        done

        if [ "$ENERGIA_OK" -eq 1 ]; then
            echo "  --- Coleta de energia ---"
            for i in $(seq 1 "$REPETICOES"); do
                echo "  Repetição $i/$REPETICOES..."
                TMP_PERF=$(mktemp)
                sudo env LC_ALL=C \
                    perf stat -e power/energy-pkg/,power_core/energy-core/ \
                    ${PIN_PREFIX[@]+"${PIN_PREFIX[@]}"} "${JAVA_CMD[@]}" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$TMP_PERF"
                ENERGIA_PKG=$(extrair_perf_energia "$TMP_PERF" "energy-pkg")
                ENERGIA_CORE=$(extrair_perf_energia "$TMP_PERF" "energy-core")
                echo "$PROGRAMA_ROTULO,geral,$i,$QUANTIDADE,$TH,$ENERGIA_PKG,$ENERGIA_CORE" >> "$CSV_ENERGIA"
                rm -f "$TMP_PERF"
            done
        fi
    done
done

echo ""
echo "✔ Métricas de tempo salvas em: $CSV_TEMPO"
[ "$ENERGIA_OK" -eq 1 ] && echo "✔ Métricas de energia salvas em: $CSV_ENERGIA"
echo "✔ Ambiente registrado em: $AMBIENTE"
