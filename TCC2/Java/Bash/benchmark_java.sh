#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
export LC_ALL=C

TAMANHOS=(${TAMANHOS:-10000000 50000000 100000000})
THREADS=(${THREADS:-1 2 4 8})
REPS=${REPS:-5}
JAVA_OPTS=${JAVA_OPTS:--Xmx4g}
SAIDA=${SAIDA:-/dev/null}

DIR=arquivos_teste
CLASSES=classes
LOGDIR=logs_java
CSV=resultados_java.csv

rotulo() {
    local n=$1
    if (( n % 1000000 == 0 )); then echo "$((n / 1000000))M"
    elif (( n % 1000 == 0 )); then echo "$((n / 1000))k"
    else echo "$n"
    fi
}

metrica() {
    grep "^$1=" "$2" | cut -d= -f2
}

if ! command -v javac >/dev/null 2>&1 || ! command -v java >/dev/null 2>&1; then
    echo "Erro: java/javac não encontrados no PATH" >&2
    exit 1
fi

echo "==> Compilando"
mkdir -p "$CLASSES"
FONTES=(RadixSortParalelo.java MainRadixSortParalelo.java)
[ -f GeradorArquivosRadixV2.java ] && FONTES+=(GeradorArquivosRadixV2.java)
for f in "${FONTES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "Erro: '$f' não encontrado nesta pasta" >&2
        exit 1
    fi
done
javac -d "$CLASSES" "${FONTES[@]}" || { echo "Erro: falha na compilação" >&2; exit 1; }

mkdir -p "$DIR" "$LOGDIR"
for n in "${TAMANHOS[@]}"; do
    arq="$DIR/radix_geral_$(rotulo "$n").txt"
    if [ ! -f "$arq" ]; then
        if [ -f GeradorArquivosRadixV2.java ]; then
            echo "==> Gerando $arq"
            java -cp "$CLASSES" GeradorArquivosRadixV2 "$n" || { echo "Erro: falha ao gerar $arq" >&2; exit 1; }
        else
            echo "Erro: '$arq' não existe e GeradorArquivosRadixV2.java não está nesta pasta" >&2
            exit 1
        fi
    fi
done

echo "tamanho,threads,rep,passadas,tempo_leitura_s,tempo_sort_s,tempo_verificacao_s,tempo_escrita_s,tempo_decorrido_s" > "$CSV"

echo "==> Benchmark: tamanhos=[${TAMANHOS[*]}] threads=[${THREADS[*]}] repeticoes=$REPS opts='$JAVA_OPTS' saida=$SAIDA"
falhas=0
for n in "${TAMANHOS[@]}"; do
    rot=$(rotulo "$n")
    arq="$DIR/radix_geral_$rot.txt"
    for t in "${THREADS[@]}"; do
        for ((r = 1; r <= REPS; r++)); do
            log="$LOGDIR/${rot}_t${t}_r${r}.log"
            java $JAVA_OPTS -cp "$CLASSES" MainRadixSortParalelo "$arq" "$SAIDA" "$n" "$t" 2> "$log"
            rc=$?
            if (( rc != 0 )); then
                echo "  [FALHA] n=$rot threads=$t rep=$r código=$rc"
                tail -n 3 "$log" | sed 's/^/      /'
                falhas=$((falhas + 1))
                continue
            fi
            passadas=$(metrica N_PASSADAS "$log")
            leit=$(metrica TEMPO_LEITURA_S "$log")
            sort_s=$(metrica TEMPO_SORT_S "$log")
            ver=$(metrica TEMPO_VERIFICACAO_S "$log")
            esc=$(metrica TEMPO_ESCRITA_S "$log")
            dec=$(metrica TEMPO_DECORRIDO_S "$log")
            echo "$n,$t,$r,$passadas,$leit,$sort_s,$ver,$esc,$dec" >> "$CSV"
            echo "  n=$rot threads=$t rep=$r  sort=${sort_s}s"
        done
    done
done

echo
echo "==> Resumo (TEMPO_SORT_S)"
printf "%-12s %-8s %-12s %-12s %-10s\n" "tamanho" "threads" "media_s" "min_s" "speedup"
awk -F, '
NR > 1 {
    k = $1 "," $2
    soma[k] += $6
    cnt[k]++
    if (!(k in mn) || $6 < mn[k]) mn[k] = $6
}
END {
    for (k in cnt) {
        split(k, p, ",")
        if (p[2] == 1) base[p[1]] = soma[k] / cnt[k]
    }
    for (k in cnt) {
        split(k, p, ",")
        media = soma[k] / cnt[k]
        sp = (p[1] in base && media > 0) ? sprintf("%.2fx", base[p[1]] / media) : "-"
        printf "%s,%s,%.6f,%.6f,%s\n", p[1], p[2], media, mn[k], sp
    }
}' "$CSV" | sort -t, -k1,1n -k2,2n | awk -F, '{ printf "%-12s %-8s %-12s %-12s %-10s\n", $1, $2, $3, $4, $5 }'

echo
echo "CSV completo: $CSV | logs: $LOGDIR/"
(( falhas > 0 )) && { echo "Atenção: $falhas execução(ões) falharam" >&2; exit 1; }
exit 0