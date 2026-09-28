#!/bin/bash
# =============================================================
# Benchmark Radix Sort v4 — PARALELO (OpenMP) — cenário geral
#
# Entradas: arquivos_teste/radix_geral_<TAM>.txt  (gerador Java V2, seed 42)
# Tamanhos padrão: 10M, 50M, 100M
# Threads padrão:  1 2 4 8 16 32   (Ryzen 9 9950X3D: 16C/32T)
# Repetições padrão: 10
#
# Pode sobrescrever sem editar o arquivo:
#   THREADS="1 4 16" TAMANHOS="10000000" REPETICOES=3 ./benchmark_radix_par_v4.sh
#
# Validação: na 1ª repetição de cada configuração, a saída é
# comparada (diff) com saida_seq_<TAM>.txt gerada pelo script
# sequencial v4 — rode o sequencial antes, ou a validação cai
# para o teste "está ordenada?".
#
# Antes de rodar (recomendado p/ medições estáveis):
#   sudo cpupower frequency-set -g performance
# =============================================================
cd ~/Downloads || { echo "Erro: pasta ~/Downloads não encontrada"; exit 1; }

PROGRAMA="${PROGRAMA:-./radix_paralelo_v1}"
DIR_ENTRADAS="${DIR_ENTRADAS:-arquivos_teste}"
TAMANHOS="${TAMANHOS:-10000000 50000000 100000000}"
THREADS="${THREADS:-1 2 4 8 16 32}"
REPETICOES="${REPETICOES:-10}"
CSV_TEMPO="metricas_radix_par_v4.csv"
CSV_ENERGIA="energia_radix_par_v4.csv"
AMBIENTE="ambiente_par_v4.txt"

# Fixa threads em núcleos físicos: evita migração entre núcleos/CCDs
# durante a execução (essencial no 9950X3D, que tem dois CCDs distintos)
export OMP_PROC_BIND=true
export OMP_PLACES=cores

[ -x "$PROGRAMA" ] || { echo "Erro: programa '$PROGRAMA' não encontrado/executável"; exit 1; }

# --- registro do ambiente (reprodutibilidade) ---
{
  echo "data: $(date -Iseconds)"
  echo "host: $(uname -a)"
  gcc --version | head -1
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
  echo "OMP_PROC_BIND=$OMP_PROC_BIND  OMP_PLACES=$OMP_PLACES"
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
    REF_SEQ="saida_seq_${ROTULO}.txt"
    SAIDA="saida_par.txt"

    [ -f "$ENTRADA" ] || { echo "AVISO: '$ENTRADA' não existe — pulando $ROTULO"; continue; }

    for TH in $THREADS; do
        echo "=============================="
        echo "PARALELO — geral — $ROTULO ($QUANTIDADE números) — $TH thread(s)"
        echo "=============================="

        echo "  --- Coleta de tempo/memória ---"
        for i in $(seq 1 "$REPETICOES"); do
            echo "  Repetição $i/$REPETICOES..."
            TMP_TIME=$(mktemp)
            /usr/bin/time -v "$PROGRAMA" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$TMP_TIME"

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

            echo "$PROGRAMA,geral,$i,$QUANTIDADE,$TH,$TEMPO_SORT,$TEMPO_USER,$TEMPO_SYS,$CPU,$TEMPO_DEC,$MEM,$FALHAS,$TROCAS_V,$TROCAS_I" >> "$CSV_TEMPO"
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
                sudo OMP_PROC_BIND=true OMP_PLACES=cores \
                    perf stat -e power/energy-pkg/,power_core/energy-core/ \
                    "$PROGRAMA" "$ENTRADA" "$SAIDA" "$QUANTIDADE" "$TH" 2> "$TMP_PERF"
                ENERGIA_PKG=$(extrair_perf_energia "$TMP_PERF" "energy-pkg")
                ENERGIA_CORE=$(extrair_perf_energia "$TMP_PERF" "energy-core")
                echo "$PROGRAMA,geral,$i,$QUANTIDADE,$TH,$ENERGIA_PKG,$ENERGIA_CORE" >> "$CSV_ENERGIA"
                rm -f "$TMP_PERF"
            done
        fi
    done
done

echo ""
echo "✔ Métricas de tempo salvas em: $CSV_TEMPO"
[ "$ENERGIA_OK" -eq 1 ] && echo "✔ Métricas de energia salvas em: $CSV_ENERGIA"
echo "✔ Ambiente registrado em: $AMBIENTE"