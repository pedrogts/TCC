#!/usr/bin/env python3
"""
Radix Sort LSD — versão SEQUENCIAL (Cython) — v4.1
"""
import ctypes
import multiprocessing as mp
import os
import stat
import sys
import time
import radix_core

VERSAO = "v4.1-cython-seq"
INT_MAX = 2147483647
OK, ERRO_ARGS, ERRO_ENTRADA, ERRO_RECURSO, ERRO_VERIFICACAO, ERRO_SAIDA = 0, 1, 2, 3, 4, 5


class ErroPrograma(Exception):
    def __init__(self, codigo, msg):
        super().__init__(msg)
        self.codigo = codigo


def ler_inteiro_positivo(s, nome, limite):
    if s.isascii() and s.isdigit():
        v = int(s)
        if 0 < v <= limite:
            return v
    raise ErroPrograma(ERRO_ARGS, f"Erro: {nome} inválido: '{s}' (esperado inteiro entre 1 e {limite})")


def car(b):
    return chr(b) if 32 <= b < 127 else '?'


def erro_token(nome_arq, linha, tok):
    if tok.startswith(b'-'):
        return ErroPrograma(ERRO_ENTRADA, f"Erro: '{nome_arq}' linha {linha}: número negativo — não suportado por esta versão")
    if not (48 <= tok[0] <= 57):
        return ErroPrograma(ERRO_ENTRADA, f"Erro: '{nome_arq}' linha {linha}: caractere inválido '{car(tok[0])}' "
                                          f"(código {tok[0]}); esperado um inteiro por linha")
    for b in tok:
        if not (48 <= b <= 57):
            return ErroPrograma(ERRO_ENTRADA, f"Erro: '{nome_arq}' linha {linha}: caractere inválido '{car(b)}' "
                                              f"(código {b}) logo após o número")
    return ErroPrograma(ERRO_ENTRADA, f"Erro: '{nome_arq}' linha {linha}: valor maior que {INT_MAX}")


def ler_entrada(nome_arq, arr, n):
    lidos = 0
    soma = 0
    xr = 0
    try:
        with open(nome_arq, 'rb') as f:
            linha = 0
            for raw in f:
                linha += 1
                for tok in raw.split():
                    if lidos == n:
                        print(f"Aviso: '{nome_arq}' contém mais dados após os {n} números solicitados (ignorados)",
                              file=sys.stderr)
                        return soma, xr
                    if not tok.isdigit():
                        raise erro_token(nome_arq, linha, tok)
                    v = int(tok)
                    if v > INT_MAX:
                        raise erro_token(nome_arq, linha, tok)
                    arr[lidos] = v
                    lidos += 1
                    soma += v
                    xr ^= v
    except OSError as e:
        raise ErroPrograma(ERRO_ENTRADA, f"Erro: não foi possível abrir '{nome_arq}': {e.strerror}")
    if lidos < n:
        raise ErroPrograma(ERRO_ENTRADA, f"Erro: '{nome_arq}' contém apenas {lidos} números, mas foram solicitados {n}")
    return soma, xr


def verificar(arr, soma_ent, xor_ent):
    status, i, ant, v, s, x = radix_core.verificar_core(arr)
    if status == 0:
        raise ErroPrograma(ERRO_VERIFICACAO, f"Erro: verificação falhou — posição {i} fora de ordem ({ant} > {v})")
    if s != soma_ent or x != xor_ent:
        raise ErroPrograma(ERRO_VERIFICACAO, "Erro: verificação falhou — os elementos ordenados não correspondem aos da entrada")


def escrever_saida(caminho, arr):
    try:
        direto = not stat.S_ISREG(os.stat(caminho).st_mode)
    except OSError:
        direto = False
    tmp = caminho + ".tmp"
    alvo = caminho if direto else tmp
    try:
        with open(alvo, 'w', newline='\n') as f:
            bloco = 100000
            for i in range(0, len(arr), bloco):
                f.write('\n'.join(map(str, arr[i:i + bloco])))
                f.write('\n')
        if not direto:
            os.replace(tmp, caminho)
    except OSError as e:
        if not direto:
            try:
                os.remove(tmp)
            except OSError:
                pass
        raise ErroPrograma(ERRO_SAIDA, f"Erro: falha ao escrever '{alvo}': {e}")


def executar(argv):
    t0 = time.perf_counter()
    if len(argv) not in (4, 5):
        raise ErroPrograma(ERRO_ARGS, f"Uso: {argv[0]} <arquivo_entrada> <arquivo_saida> <quantidade> [n_threads=1]")
    arquivo_entrada, arquivo_saida = argv[1], argv[2]
    quantidade = ler_inteiro_positivo(argv[3], "quantidade", INT_MAX)
    if len(argv) == 5:
        try:
            ler_inteiro_positivo(argv[4], "n_threads", 1)
        except ErroPrograma as e:
            raise ErroPrograma(ERRO_ARGS, f"{e}\nErro: esta é a versão sequencial; n_threads deve ser 1")

    t_prep0 = time.perf_counter()
    try:
        arr = mp.RawArray(ctypes.c_int, quantidade)
        buf = mp.RawArray(ctypes.c_int, quantidade)
    except (MemoryError, OSError) as e:
        raise ErroPrograma(ERRO_RECURSO, f"Erro: falha ao alocar memória para {quantidade} números: {e}")
    t_prep1 = time.perf_counter()

    t_leit0 = time.perf_counter()
    soma, xr = ler_entrada(arquivo_entrada, arr, quantidade)
    t_leit1 = time.perf_counter()

    # Delega funções pesadas ao Cython
    max_val = radix_core.get_max(arr)

    t_sort0 = time.perf_counter()
    passadas = radix_core.radix_sort_core(arr, buf, max_val)
    # Se o número de passadas for ímpar, o vetor ordenado estará em 'buf'
    final = buf if passadas % 2 != 0 else arr
    t_sort1 = time.perf_counter()

    t_ver0 = time.perf_counter()
    verificar(final, soma, xr)
    t_ver1 = time.perf_counter()

    t_esc0 = time.perf_counter()
    escrever_saida(arquivo_saida, final)
    t_esc1 = time.perf_counter()

    t1 = time.perf_counter()
    e = sys.stderr
    print(f"VERSAO={VERSAO}", file=e)
    print("N_THREADS=1", file=e)
    print(f"N_PASSADAS={passadas}", file=e)
    print(f"TEMPO_PREPARO_S={t_prep1 - t_prep0:.9f}", file=e)
    print(f"TEMPO_LEITURA_S={t_leit1 - t_leit0:.9f}", file=e)
    print(f"TEMPO_SORT_S={t_sort1 - t_sort0:.9f}", file=e)
    print(f"TEMPO_VERIFICACAO_S={t_ver1 - t_ver0:.9f}", file=e)
    print(f"TEMPO_ESCRITA_S={t_esc1 - t_esc0:.9f}", file=e)
    print(f"TEMPO_DECORRIDO_S={t1 - t0:.9f}", file=e)
    print("VERIFICACAO=OK", file=e)
    return OK


def main():
    try:
        codigo = executar(sys.argv)
    except ErroPrograma as e:
        print(str(e), file=sys.stderr)
        codigo = e.codigo
    except MemoryError:
        print("Erro: memória insuficiente", file=sys.stderr)
        codigo = ERRO_RECURSO
    sys.exit(codigo)


if __name__ == '__main__':
    main()