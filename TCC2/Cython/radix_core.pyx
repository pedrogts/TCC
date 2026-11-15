# cython: language_level=3
import cython

@cython.boundscheck(False)
@cython.wraparound(False)
cpdef int get_max(int[:] arr) noexcept:
    """Busca o valor máximo do vetor em nível C."""
    cdef int max_val = 0
    cdef int i
    cdef int n = arr.shape[0]
    for i in range(n):
        if arr[i] > max_val:
            max_val = arr[i]
    return max_val

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cpdef int radix_sort_core(int[:] arr, int[:] buf, int max_val) noexcept:
    """Laço principal do Radix Sort utilizando divisão inteira e arrays de C."""
    cdef int exp = 1
    cdef int passadas = 0
    cdef int i, v, d, acum
    cdef int n = arr.shape[0]
    
    # Contadores e posições locais alocados na stack de C
    cdef int cont[10]
    cdef int pos[10]
    
    # Memoryviews para alternar referências rapidamente
    cdef int[:] src = arr
    cdef int[:] dst = buf
    cdef int[:] temp
    
    while (max_val / exp) > 0:
        # Fase 1: contagem
        for i in range(10): 
            cont[i] = 0
            
        for i in range(n):
            v = src[i]
            d = (v / exp) % 10
            cont[d] += 1
            
        # Fase 2: soma de prefixos exclusiva
        acum = 0
        for i in range(10):
            pos[i] = acum
            acum += cont[i]
            
        # Fase 3: distribuição estável
        for i in range(n):
            v = src[i]
            d = (v / exp) % 10
            dst[pos[d]] = v
            pos[d] += 1
            
        # Troca de papéis entre origem e destino
        temp = src
        src = dst
        dst = temp
        
        exp *= 10
        passadas += 1
        
    return passadas

@cython.boundscheck(False)
@cython.wraparound(False)
cpdef tuple verificar_core(int[:] arr):
    """Verifica a ordem, soma e xor sem overhead do interpretador Python."""
    cdef long long s = 0
    cdef long long x = 0
    cdef int ant = -1
    cdef int i, v
    cdef int n = arr.shape[0]
    
    for i in range(n):
        v = arr[i]
        if v < ant:
            return (0, i, ant, v, s, x) # 0 = erro de ordem
        ant = v
        s += v
        x ^= v
        
    return (1, -1, -1, -1, s, x) # 1 = sucesso