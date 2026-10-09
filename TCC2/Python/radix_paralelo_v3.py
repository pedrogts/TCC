#!/usr/bin/env python3
import sys
import time
import ctypes
import multiprocessing as mp
import os

VERSAO = "v3_py"


def ler_entrada(nome_arq, arr, n):
    """Lê os inteiros do arquivo, linha por linha, e calcula soma/XOR."""
    soma = 0
    xr = 0
    lidos = 0
    try:
        with open(nome_arq, 'r') as f:
            for linha in f:
                for val_str in linha.split():
                    if lidos >= n:
                        break
                    v = int(val_str)
                    arr[lidos] = v
                    soma += v
                    xr ^= v
                    lidos += 1
                if lidos >= n:
                    break
    except FileNotFoundError:
        print(f"Erro: não foi possível abrir '{nome_arq}'", file=sys.stderr)
        sys.exit(2)

    if lidos < n:
        print(f"Erro: '{nome_arq}' contém apenas {lidos} números, mas foram solicitados {n}", file=sys.stderr)
        sys.exit(2)

    return soma, xr


def escrever_saida(caminho, arr, n):
    """Escreve o vetor ordenado em arquivo com buffer e renomeação atômica."""
    tmp_nome = f"{caminho}.tmp"
    try:
        with open(tmp_nome, 'w') as f:
            bloco = []
            for i in range(n):
                bloco.append(str(arr[i]))
                # Grava no disco a cada 100k elementos para evitar estouro de RAM
                if len(bloco) >= 100000:
                    f.write('\n'.join(bloco) + '\n')
                    bloco.clear()
            if bloco:
                f.write('\n'.join(bloco) + '\n')

        # Renomeação atômica
        if os.path.exists(caminho):
            os.remove(caminho)
        os.rename(tmp_nome, caminho)
    except Exception as e:
        print(f"Erro: falha ao escrever '{caminho}': {e}", file=sys.stderr)
        if os.path.exists(tmp_nome):
            os.remove(tmp_nome)
        sys.exit(5)


def worker_radix(t, nt, n, max_val, src_shared, dst_shared, hist_shared, barrier):
    """Lógica principal de ordenação processada por cada thread/processo."""
    exp = 1
    passada = 0

    ini = t * n // nt
    fim = (t + 1) * n // nt
    h_offset = t * 10

    while max_val // exp > 0:
        if passada % 2 == 0:
            src, dst = src_shared, dst_shared
        else:
            src, dst = dst_shared, src_shared

        # FASE 1: contagem local
        for d in range(10):
            hist_shared[h_offset + d] = 0

        for i in range(ini, fim):
            digito = (src[i] // exp) % 10
            hist_shared[h_offset + digito] += 1

        barrier.wait()

        # FASE 2: prefixo global
        if t == 0:
            pos = 0
            for d in range(10):
                for tt in range(nt):
                    idx = tt * 10 + d
                    c = hist_shared[idx]
                    hist_shared[idx] = pos
                    pos += c

        barrier.wait()

        # FASE 3: distribuição estável
        local_h = [hist_shared[h_offset + d] for d in range(10)]
        for i in range(ini, fim):
            v = src[i]
            digito = (v // exp) % 10
            pos = local_h[digito]
            dst[pos] = v
            local_h[digito] += 1

        exp *= 10
        passada += 1
        barrier.wait()


def verificar(arr, n, soma_ent, xor_ent):

    s = 0
    x = 0
    for i in range(n):
        if i > 0 and arr[i - 1] > arr[i]:
            print(f"Erro: verificação falhou — posição {i} fora de ordem ({arr[i - 1]} > {arr[i]})", file=sys.stderr)
            sys.exit(4)
        s += arr[i]
        x ^= arr[i]

    if s != soma_ent or x != xor_ent:
        print("Erro: verificação falhou — os elementos ordenados não correspondem aos da entrada", file=sys.stderr)
        sys.exit(4)


if __name__ == '__main__':
    t0 = time.perf_counter()

    # Restaura o formato original exigido pelo script .sh
    if len(sys.argv) not in [4, 5]:
        print(f"Uso: {sys.argv[0]} <arquivo_entrada> <arquivo_saida> <quantidade> [n_threads]", file=sys.stderr)
        sys.exit(1)

    arquivo_entrada = sys.argv[1]
    arquivo_saida = sys.argv[2]
    quantidade = int(sys.argv[3])
    n_threads = int(sys.argv[4]) if len(sys.argv) == 5 else os.cpu_count()

    arr_shared = mp.RawArray(ctypes.c_int, quantidade)
    buf_shared = mp.RawArray(ctypes.c_int, quantidade)
    hist_shared = mp.RawArray(ctypes.c_longlong, n_threads * 10)

    # Coleta: TEMPO_LEITURA_S
    t_leit0 = time.perf_counter()
    soma_ent, xor_ent = ler_entrada(arquivo_entrada, arr_shared, quantidade)
    t_leit1 = time.perf_counter()

    max_val = 0
    for i in range(quantidade):
        if arr_shared[i] > max_val:
            max_val = arr_shared[i]

    temp_max = max_val
    passadas = 0
    while temp_max > 0:
        passadas += 1
        temp_max //= 10
    if max_val == 0:
        passadas = 1

    # Coleta: TEMPO_SORT_S
    t_sort0 = time.perf_counter()

    if n_threads > 1:
        barrier = mp.Barrier(n_threads)
        processos = []
        for t in range(n_threads):
            p = mp.Process(target=worker_radix,
                           args=(t, n_threads, quantidade, max_val, arr_shared, buf_shared, hist_shared, barrier))
            p.start()
            processos.append(p)

        for p in processos:
            p.join()
    else:
        class FakeBarrier:
            def wait(self): pass


        worker_radix(0, 1, quantidade, max_val, arr_shared, buf_shared, hist_shared, FakeBarrier())

    t_sort1 = time.perf_counter()

    array_final = buf_shared if passadas % 2 != 0 else arr_shared

    # Coleta: TEMPO_VERIFICACAO_S
    t_ver0 = time.perf_counter()
    verificar(array_final, quantidade, soma_ent, xor_ent)
    t_ver1 = time.perf_counter()

    # Coleta: TEMPO_ESCRITA_S
    t_esc0 = time.perf_counter()
    escrever_saida(arquivo_saida, array_final, quantidade)
    t_esc1 = time.perf_counter()

    # Coleta: TEMPO_DECORRIDO_S
    t1 = time.perf_counter()

    # Impressão exata exigida pelo benchmark no stderr
    print(f"VERSAO={VERSAO}", file=sys.stderr)
    print(f"N_THREADS={n_threads}", file=sys.stderr)
    print(f"N_PASSADAS={passadas}", file=sys.stderr)
    print(f"TEMPO_LEITURA_S={(t_leit1 - t_leit0):.9f}", file=sys.stderr)
    print(f"TEMPO_SORT_S={(t_sort1 - t_sort0):.9f}", file=sys.stderr)
    print(f"TEMPO_VERIFICACAO_S={(t_ver1 - t_ver0):.9f}", file=sys.stderr)
    print(f"TEMPO_ESCRITA_S={(t_esc1 - t_esc0):.9f}", file=sys.stderr)
    print(f"TEMPO_DECORRIDO_S={(t1 - t0):.9f}", file=sys.stderr)
    print("VERIFICACAO=OK", file=sys.stderr)