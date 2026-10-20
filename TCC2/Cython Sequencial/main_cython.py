#!/usr/bin/env python3 
import sys
import time
import array
from radix_core import radix_sort_cython

def main():
    t0 = time.time()
    
    if len(sys.argv) not in (4, 5):
        print(f"Uso: {sys.argv[0]} <entrada> <saida> <quantidade>", file=sys.stderr)
        sys.exit(1)
        
    arq_entrada = sys.argv[1]
    arq_saida = sys.argv[2]
    quantidade = int(sys.argv[3])
    
    # LEITURA
    t_leit0 = time.time()
    # Usamos array('i') porque é compatível de forma nativa com as memoryviews do Cython
    arr = array.array('i')
    soma_ent = 0
    xor_ent = 0
    
    try:
        with open(arq_entrada, 'r') as f:
            for _ in range(quantidade):
                v = int(f.readline())
                arr.append(v)
                soma_ent += v
                xor_ent ^= v
    except Exception as e:
        print(f"Erro na leitura: {e}", file=sys.stderr)
        sys.exit(2)
    t_leit1 = time.time()

    # SORT (Chama a função Cython em C)
    t_sort0 = time.time()
    passadas = radix_sort_cython(arr)
    t_sort1 = time.time()

    # VERIFICAÇÃO
    t_ver0 = time.time()
    soma_out = 0
    xor_out = 0
    for i in range(quantidade):
        if i > 0 and arr[i-1] > arr[i]:
            print(f"Erro: Array fora de ordem na posição {i}", file=sys.stderr)
            sys.exit(4)
        soma_out += arr[i]
        xor_out ^= arr[i]
        
    if soma_ent != soma_out or xor_ent != xor_out:
        print("Erro: Verificação de soma/XOR falhou", file=sys.stderr)
        sys.exit(4)
    t_ver1 = time.time()

    # ESCRITA
    t_esc0 = time.time()
    try:
        with open(arq_saida + '.tmp', 'w') as f:
            # Escrever em blocos é mais rápido
            f.write('\n'.join(map(str, arr)) + '\n')
        import os
        os.rename(arq_saida + '.tmp', arq_saida)
    except Exception as e:
        print(f"Erro na escrita: {e}", file=sys.stderr)
        sys.exit(5)
    t_esc1 = time.time()

    t1 = time.time()
    
    # IMPRESSÃO DAS MÉTRICAS (Padrão do Benchmark)
    print("VERSAO=v1-cython-seq", file=sys.stderr)
    print("N_THREADS=1", file=sys.stderr)
    print(f"N_PASSADAS={passadas}", file=sys.stderr)
    print(f"TEMPO_LEITURA_S={t_leit1 - t_leit0:.9f}", file=sys.stderr)
    print(f"TEMPO_SORT_S={t_sort1 - t_sort0:.9f}", file=sys.stderr)
    print(f"TEMPO_VERIFICACAO_S={t_ver1 - t_ver0:.9f}", file=sys.stderr)
    print(f"TEMPO_ESCRITA_S={t_esc1 - t_esc0:.9f}", file=sys.stderr)
    print(f"TEMPO_DECORRIDO_S={t1 - t0:.9f}", file=sys.stderr)
    print("VERIFICACAO=OK", file=sys.stderr)

if __name__ == '__main__':
    main()
