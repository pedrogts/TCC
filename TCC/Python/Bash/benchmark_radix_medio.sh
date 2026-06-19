#!/bin/bash
export LC_ALL=C

ENTRADA="dados1M_radix_medio.txt"
SAIDA="saida_radix.txt"
INTERPRETADOR="python3"
PROGRAMA="radix_puro.py"
REPETICOES=10
CSV="metricas_python_radix_medio.csv"
TIPO_CASO="medio"
QUANTIDADES="100000 200000 500000 1000000"

echo "linguagem,programa,caso,repeticao,quantidade,tempo_usuario_s,tempo_sistema_s,cpu_pct,tempo_decorrido_s,memoria_max_kb,falhas_pagina_menores,trocas_voluntarias,trocas_involuntarias,energia_pkg_j,energia_core_j" > "$CSV"

extrair_perf_energia() {
    grep "$2" "$1" | grep -oP '[\d\.,]+(?=\s+(Joules|J))' | tr -d ',' | head -1
}

cat << 'EOF' > medidor_preciso.py
import sys, os, resource, time
start = time.perf_counter()
pid = os.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
else:
    _, status, ru = os.wait4(pid, 0)
    elap = time.perf_counter() - start
    with open("dados_tempo.txt", "w") as f:
        f.write(f"USER:{ru.ru_utime:.9f}\nSYS:{ru.ru_stime:.9f}\nELAPSED:{elap:.9f}\n")
        f.write(f"MEM:{ru.ru_maxrss}\nMINFLT:{ru.ru_minflt}\nVCSW:{ru.ru_nvcsw}\nIVCSW:{ru.ru_nivcsw}\n")
EOF

# Agora o loop usa a variável QUANTIDADES definida na configuração
for QUANTIDADE in $QUANTIDADES; do
    echo "=============================="
    echo "A Executar $PROGRAMA — $TIPO_CASO CASO — $QUANTIDADE números"
    for i in $(seq 1 $REPETICOES); do
        echo "  Repetição $i/$REPETICOES..."
        TMP_PERF=$(mktemp)

        sudo perf stat -e power/energy-pkg/ -e power_core/energy-core/ -o "$TMP_PERF" \
            python3 medidor_preciso.py $INTERPRETADOR $PROGRAMA "$ENTRADA" "$SAIDA" "$QUANTIDADE"

        TEMPO_USER=$(grep "USER:" dados_tempo.txt | cut -d: -f2)
        TEMPO_SYS=$(grep "SYS:" dados_tempo.txt | cut -d: -f2)
        TEMPO_DEC=$(grep "ELAPSED:" dados_tempo.txt | cut -d: -f2)
        MEM=$(grep "MEM:" dados_tempo.txt | cut -d: -f2)
        FALHAS=$(grep "MINFLT:" dados_tempo.txt | cut -d: -f2)
        TROCAS_V=$(grep "VCSW:" dados_tempo.txt | cut -d: -f2)
        TROCAS_I=$(grep "IVCSW:" dados_tempo.txt | cut -d: -f2)
        CPU=$(awk -v u="$TEMPO_USER" -v s="$TEMPO_SYS" -v e="$TEMPO_DEC" 'BEGIN { if (e > 0) printf "%.0f\n", ((u+s)/e)*100; else print "0" }')

        ENERGIA_PKG=$(extrair_perf_energia "$TMP_PERF" "energy-pkg")
        ENERGIA_CORE=$(extrair_perf_energia "$TMP_PERF" "energy-core")

        echo "Python,$PROGRAMA,$TIPO_CASO,$i,$QUANTIDADE,$TEMPO_USER,$TEMPO_SYS,$CPU,$TEMPO_DEC,$MEM,$FALHAS,$TROCAS_V,$TROCAS_I,$ENERGIA_PKG,$ENERGIA_CORE" >> "$CSV"
        rm -f "$TMP_PERF" dados_tempo.txt
    done
done
rm -f medidor_preciso.py
echo "✔ Métricas salvas em: $CSV"