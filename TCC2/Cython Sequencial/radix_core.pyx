# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True

from libc.stdlib cimport malloc, free
from libc.string cimport memcpy

cpdef int radix_sort_cython(int[:] arr):
    cdef int n = arr.shape[0]
    if n <= 1:
        return 0
    
    # 1. Encontrar o máximo
    cdef int m = 0
    cdef int i
    for i in range(n):
        if arr[i] > m:
            m = arr[i]
            
    # Alocar buffer auxiliar diretamente em C
    cdef int* buf = <int*>malloc(n * sizeof(int))
    if not buf:
        raise MemoryError("Falha ao alocar memória em C")
        
    cdef int exp = 1
    cdef int hist[10]
    cdef int passadas = 0
    cdef int* src = &arr[0]
    cdef int* dst = buf
    cdef int* tmp
    cdef int v, d, pos, count
    
    # 2. Ordenação dígito a dígito
    while m // exp > 0:
        # Zerar histograma
        for d in range(10):
            hist[d] = 0
            
        # Contagem
        for i in range(n):
            hist[(src[i] // exp) % 10] += 1
            
        # Soma de prefixos (Exclusiva)
        pos = 0
        for d in range(10):
            count = hist[d]
            hist[d] = pos
            pos += count
            
        # Distribuição
        for i in range(n):
            v = src[i]
            d = (v // exp) % 10
            dst[hist[d]] = v
            hist[d] += 1
            
        # Ping-pong de ponteiros
        tmp = src
        src = dst
        dst = tmp
        exp *= 10
        passadas += 1
        
    # Se o resultado final ficou no buffer auxiliar, copia de volta para o array original
    if src != &arr[0]:
        memcpy(&arr[0], src, n * sizeof(int))
        
    free(buf)
    return passadas
