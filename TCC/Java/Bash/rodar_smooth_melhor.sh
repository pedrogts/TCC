#!/bin/bash

ENTRADA="dados1M_smooth_melhor.txt"
SAIDA="saida.txt"
PROGRAMA="MainSmoothSort"
REPETICOES=10
CSV="metricas_smooth_melhor.csv"

echo "programa,repeticao,quantidade,tempo_usuario_s,tempo_sistema_s,cpu_pct,tempo_decorrido_s,memoria_max_kb,falhas_pagina_menores,trocas_voluntarias,trocas_involuntarias,energia_pkg_j,energia_core_j" > $CSV

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
    grep "$2" "$1" | grep -oP '[\d\.,]+(?=\s+Joules)' | tr ',' '.' | head -1
}

for QUANTIDADE in 100000 200000 500000 1000000; do
    echo "=============================="
    echo "Rodando $PROGRAMA — $QUANTIDADE numeros"
    echo "=============================="

    for i in $(seq 1 $REPETICOES); do
        echo "  Repeticao $i/$REPETICOES..."

        TMP_TIME=$(mktemp)
        TMP_PERF=$(mktemp)

        { /usr/bin/time -v java $PROGRAMA $ENTRADA $SAIDA $QUANTIDADE; } 2> "$TMP_TIME" &
        JAVA_PID=$!

        perf stat -a -e power/energy-pkg/,power_core/energy-core/ \
            2> "$TMP_PERF" &
        PERF_PID=$!

        wait $JAVA_PID
        kill -INT $PERF_PID 2>/dev/null
        wait $PERF_PID 2>/dev/null

        TEMPO_USER=$(extrair_time "$TMP_TIME" "User time")
        TEMPO_SYS=$(extrair_time "$TMP_TIME" "System time")
        CPU=$(extrair_time "$TMP_TIME" "Percent of CPU")
        TEMPO_DEC=$(extrair_tempo_decorrido "$TMP_TIME")
        MEM=$(extrair_time "$TMP_TIME" "Maximum resident")
        FALHAS=$(extrair_time "$TMP_TIME" "Minor")
        TROCAS_V=$(extrair_time "$TMP_TIME" "Voluntary context")
        TROCAS_I=$(extrair_time "$TMP_TIME" "Involuntary context")
        ENERGIA_PKG=$(extrair_perf_energia "$TMP_PERF" "energy-pkg")
        ENERGIA_CORE=$(extrair_perf_energia "$TMP_PERF" "energy-core")

        echo "$PROGRAMA,$i,$QUANTIDADE,$TEMPO_USER,$TEMPO_SYS,$CPU,$TEMPO_DEC,$MEM,$FALHAS,$TROCAS_V,$TROCAS_I,$ENERGIA_PKG,$ENERGIA_CORE" >> $CSV

        rm -f "$TMP_TIME" "$TMP_PERF"
    done
done

echo "Metricas salvas em: $CSV"
