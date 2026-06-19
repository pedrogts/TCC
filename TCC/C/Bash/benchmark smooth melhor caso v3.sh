#!/bin/bash
cd ~/Downloads || { echo "Erro: pasta ~/Downloads não encontrada"; exit 1; }

# =============================================================
# Benchmark Smoothsort v3 — Melhor Caso
# Arquivo único: dados1M_smooth_melhor.txt (1M valores)
# Tamanhos: 100k, 200k, 500k, 1M
# =============================================================

ENTRADA="dados1M_smooth_melhor.txt"
PROGRAMA="./smoothsort_v3"
REPETICOES=10
CSV_TEMPO="metricas_smooth_melhor.csv"
CSV_ENERGIA="energia_smooth_melhor.csv"

echo "programa,caso,repeticao,quantidade,tempo_sort_s,tempo_usuario_s,tempo_sistema_s,cpu_pct,tempo_decorrido_s,memoria_max_kb,falhas_pagina_menores,trocas_voluntarias,trocas_involuntarias" > "$CSV_TEMPO"
echo "programa,caso,repeticao,quantidade,energia_pkg_j,energia_core_j" > "$CSV_ENERGIA"

extrair_time() {
    grep "$2" "$1" | grep -oP '[\d\.]+' | head -1
}

extrair_tempo_decorrido() {
    grep "Elapsed" "$1" | grep -oP '(\d+:)?\d+:\d+\.\d+' | head -1 | awk -F: '{
        if (NF == 3) print ($1*3600) + ($2*60) + $3
        else print ($1*60) + $2
    }'
}

extrair_perf_energia() {
    grep "$2" "$1" | grep -oP '[\d\.,]+(?=\s+Joules)' | sed 's|,|.|' | head -1
}

extrair_tempo_sort() {
    grep "TEMPO_SORT_S" "$1" | grep -oP '[\d\.]+' | head -1
}

# Wall clock medido DENTRO do programa C (CLOCK_MONOTONIC, ns) — robusto
extrair_tempo_decorrido_interno() {
    grep "TEMPO_DECORRIDO_S" "$1" | grep -oP '[\d\.]+' | head -1
}

for QUANTIDADE in 100000 200000 500000 1000000; do
    echo "=============================="
    echo "Rodando $PROGRAMA — MELHOR CASO — $QUANTIDADE números"
    echo "=============================="

    echo "  --- Coleta de tempo/memória ---"
    for i in $(seq 1 $REPETICOES); do
        echo "  Repetição $i/$REPETICOES..."
        TMP_TIME=$(mktemp)

        /usr/bin/time -v $PROGRAMA "$ENTRADA" "saida_smooth_melhor.txt" "$QUANTIDADE" 2> "$TMP_TIME"

        TEMPO_SORT=$(extrair_tempo_sort "$TMP_TIME")
        TEMPO_USER=$(extrair_time "$TMP_TIME" "User time")
        TEMPO_SYS=$(extrair_time "$TMP_TIME" "System time")
        CPU=$(extrair_time "$TMP_TIME" "Percent of CPU")
        TEMPO_DEC=$(extrair_tempo_decorrido_interno "$TMP_TIME")
        # fallback: se o programa não imprimir, tenta o /usr/bin/time
        [ -z "$TEMPO_DEC" ] && TEMPO_DEC=$(extrair_tempo_decorrido "$TMP_TIME")
        MEM=$(extrair_time "$TMP_TIME" "Maximum resident")
        FALHAS=$(extrair_time "$TMP_TIME" "Minor")
        TROCAS_V=$(extrair_time "$TMP_TIME" "Voluntary context")
        TROCAS_I=$(extrair_time "$TMP_TIME" "Involuntary context")

        echo "$PROGRAMA,melhor,$i,$QUANTIDADE,$TEMPO_SORT,$TEMPO_USER,$TEMPO_SYS,$CPU,$TEMPO_DEC,$MEM,$FALHAS,$TROCAS_V,$TROCAS_I" >> "$CSV_TEMPO"
        rm -f "$TMP_TIME"
    done

    echo "  --- Coleta de energia ---"
    for i in $(seq 1 $REPETICOES); do
        echo "  Repetição $i/$REPETICOES..."
        TMP_PERF=$(mktemp)

        sudo perf stat -e power/energy-pkg/,power_core/energy-core/ \
            $PROGRAMA "$ENTRADA" "saida_smooth_melhor.txt" "$QUANTIDADE" 2> "$TMP_PERF"

        ENERGIA_PKG=$(extrair_perf_energia "$TMP_PERF" "energy-pkg")
        ENERGIA_CORE=$(extrair_perf_energia "$TMP_PERF" "energy-core")

        echo "$PROGRAMA,melhor,$i,$QUANTIDADE,$ENERGIA_PKG,$ENERGIA_CORE" >> "$CSV_ENERGIA"
        rm -f "$TMP_PERF"
    done
done

echo ""
echo "✔ Métricas de tempo salvas em: $CSV_TEMPO"
echo "✔ Métricas de energia salvas em: $CSV_ENERGIA"
