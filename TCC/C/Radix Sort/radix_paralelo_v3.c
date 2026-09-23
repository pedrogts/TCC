/* =============================================================
 * Radix Sort LSD — Versão PARALELA (OpenMP) — v3
 *
 * Base: v2 (histogramas alinhados a 64 bytes contra false sharing).
 * A v3 corrige os erros apontados na revisão e reorganiza a
 * medição de tempo. Resumo (detalhes no relatório LaTeX):
 *
 *  CORREÇÕES
 *   C1  Número de threads garantido: omp_set_dynamic(0) +
 *       omp_set_num_threads(n) + verificação prévia; se o runtime
 *       entregar menos threads que o pedido, o programa ABORTA
 *       (antes: ordenava errado silenciosamente).
 *   C2  get_max usa o mesmo número de threads das demais fases
 *       (antes: sempre omp_get_max_threads()).
 *   C3  N_THREADS informa o número REAL de threads da equipe.
 *   C4  Argumentos validados com strtol (antes: atoi; "1e6" virava 1).
 *   C5  Leitura com parser próprio: rejeita caracteres inválidos,
 *       números negativos e valores > INT_MAX, com número da linha.
 *       Menos números que o solicitado agora é ERRO (antes: aviso
 *       e a saída saía menor). Aceita finais de linha LF e CRLF.
 *   C6  exp em long long (antes: overflow de int com valores >= 1e9).
 *   C7  Escrita verificada (fwrite/fflush/fclose). A saída é gravada
 *       em <saida>.tmp e renomeada só no fim: um arquivo de saída
 *       incompleto NUNCA fica no disco com o nome final.
 *   C8  Verificação pós-ordenação (fora da medição): ordem crescente
 *       + soma e XOR dos elementos iguais aos da entrada.
 *   C9  Índices em long long/size_t (long tem 32 bits no Windows) e
 *       alocação alinhada portável (_aligned_malloc no Windows).
 *   C10 Códigos de saída distintos por tipo de erro (ver abaixo).
 *
 *  MEDIÇÃO / DESEMPENHO
 *   M1  Buffer auxiliar e histogramas alocados UMA vez (antes: a
 *       cada passada, dentro da região medida).
 *   M2  Troca de ponteiros entre passadas (ping-pong) no lugar do
 *       memcpy sequencial de n elementos por passada.
 *   M3  Uma única região paralela por passada (contagem, prefixo
 *       e distribuição), em vez de duas.
 *   M4  Região de aquecimento antes da medição: a criação do pool
 *       de threads fica fora de TEMPO_SORT_S.
 *   M5  Tempos separados: leitura, sort, verificação, escrita, total.
 *   M6  E/S bufferizada própria (fread/fwrite), bem mais rápida que
 *       fscanf/fprintf.
 *
 * Interface (compatível com a v2):
 *   ./radix_paralelo_v3 <entrada> <saida> <quantidade> [n_threads]
 *
 * Saída em stderr (uma métrica por linha, formato CHAVE=valor):
 *   VERSAO, N_THREADS, N_PASSADAS, TEMPO_LEITURA_S, TEMPO_SORT_S,
 *   TEMPO_VERIFICACAO_S, TEMPO_ESCRITA_S, TEMPO_DECORRIDO_S,
 *   VERIFICACAO
 *
 * Códigos de saída:
 *   0 sucesso | 1 argumentos | 2 entrada | 3 memória/threads
 *   4 verificação falhou | 5 escrita da saída
 *
 * Compilar:  gcc -O2 -fopenmp radix_paralelo_v3.c -o radix_paralelo_v3
 * Depuração: acrescente -DRADIX_DEBUG para imprimir o tamanho da
 *            equipe em cada região paralela (usado pelos testes).
 * ============================================================= */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <time.h>
#include <sys/stat.h>
#include <omp.h>

#define VERSAO        "v3"
#define MAX_THREADS   1024
#define TAM_BUF_ES    (1u << 20)      /* 1 MiB para leitura/escrita */

enum { OK = 0, ERRO_ARGS = 1, ERRO_ENTRADA = 2, ERRO_RECURSO = 3,
       ERRO_VERIFICACAO = 4, ERRO_SAIDA = 5 };

#ifdef _WIN32
#  include <malloc.h>
#  define ALLOC_ALINHADO(tam) _aligned_malloc((tam), 64)
#  define FREE_ALINHADO(p)    _aligned_free(p)
#else
#  define ALLOC_ALINHADO(tam) aligned_alloc(64, (tam))
#  define FREE_ALINHADO(p)    free(p)
#endif

#ifdef RADIX_DEBUG
#  define DEBUG_REGIAO(nome) \
     do { if (omp_get_thread_num() == 0) \
            fprintf(stderr, "DEBUG_REGIAO %s threads=%d\n", (nome), omp_get_num_threads()); \
     } while (0)
#else
#  define DEBUG_REGIAO(nome) do { } while (0)
#endif

/* Histograma privado de uma thread, alinhado a 64 bytes (mantido da v2).
 * sizeof(HistPad) = 128: cada thread ocupa 2 linhas de cache exclusivas. */
typedef struct {
    _Alignas(64) long long h[10];
} HistPad;

static double agora(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

/* ------------------------------------------------------------------
 * Argumentos
 * ------------------------------------------------------------------ */
static int ler_inteiro_positivo(const char *s, const char *nome, long limite, int *out) {
    char *fim;
    errno = 0;
    long v = strtol(s, &fim, 10);
    if (errno != 0 || fim == s || *fim != '\0' || v <= 0 || v > limite) {
        fprintf(stderr, "Erro: %s inválido: '%s' (esperado inteiro entre 1 e %ld)\n", nome, s, limite);
        return 0;
    }
    *out = (int)v;
    return 1;
}

/* ------------------------------------------------------------------
 * Leitura bufferizada com validação
 * ------------------------------------------------------------------ */
typedef struct {
    FILE  *f;
    char  *buf;
    size_t len, pos;
    int    fim;
    long long linha;
} Leitor;

static int prox_char(Leitor *L) {
    if (L->pos == L->len) {
        if (L->fim) return EOF;
        L->len = fread(L->buf, 1, TAM_BUF_ES, L->f);
        L->pos = 0;
        if (L->len == 0) { L->fim = 1; return EOF; }
    }
    return (unsigned char)L->buf[L->pos++];
}

static int eh_espaco(int c) { return c == ' ' || c == '\n' || c == '\r' || c == '\t'; }

/* Pula separadores. Retorna o primeiro caractere não-separador (ou EOF). */
static int pular_espacos(Leitor *L) {
    int c;
    do {
        c = prox_char(L);
        if (c == '\n') L->linha++;
    } while (eh_espaco(c));
    return c;
}

/* 1 = número lido; 0 = fim do arquivo; -1 = erro (mensagem já impressa) */
static int ler_numero(Leitor *L, const char *nome_arq, int *out) {
    int c = pular_espacos(L);
    if (c == EOF) {
        if (ferror(L->f)) { fprintf(stderr, "Erro: falha de leitura em '%s': %s\n", nome_arq, strerror(errno)); return -1; }
        return 0;
    }
    if (c == '-') {
        fprintf(stderr, "Erro: '%s' linha %lld: número negativo — não suportado por esta versão\n", nome_arq, L->linha);
        return -1;
    }
    if (c < '0' || c > '9') {
        fprintf(stderr, "Erro: '%s' linha %lld: caractere inválido '%c' (código %d); esperado um inteiro por linha\n",
                nome_arq, L->linha, (c >= 32 && c < 127) ? c : '?', c);
        return -1;
    }
    long long v = 0;
    while (c >= '0' && c <= '9') {
        v = v * 10 + (c - '0');
        if (v > INT_MAX) {
            fprintf(stderr, "Erro: '%s' linha %lld: valor maior que %d\n", nome_arq, L->linha, INT_MAX);
            return -1;
        }
        c = prox_char(L);
    }
    if (c == '\n') L->linha++;
    else if (c != EOF && !eh_espaco(c)) {
        fprintf(stderr, "Erro: '%s' linha %lld: caractere inválido '%c' (código %d) logo após o número\n",
                nome_arq, L->linha, (c >= 32 && c < 127) ? c : '?', c);
        return -1;
    }
    *out = (int)v;
    return 1;
}

/* Lê exatamente n números. Calcula soma e XOR (usados na verificação). */
static int ler_entrada(const char *nome_arq, int *arr, long long n,
                       unsigned long long *soma, unsigned int *xr) {
    FILE *f = fopen(nome_arq, "rb");
    if (!f) { fprintf(stderr, "Erro: não foi possível abrir '%s': %s\n", nome_arq, strerror(errno)); return ERRO_ENTRADA; }
    Leitor L = { f, malloc(TAM_BUF_ES), 0, 0, 0, 1 };
    if (!L.buf) { fclose(f); fprintf(stderr, "Erro: falha ao alocar memória\n"); return ERRO_RECURSO; }

    unsigned long long s = 0;
    unsigned int x = 0;
    long long lidos = 0;
    int r = 1;
    while (lidos < n && (r = ler_numero(&L, nome_arq, &arr[lidos])) == 1) {
        s += (unsigned int)arr[lidos];
        x ^= (unsigned int)arr[lidos];
        lidos++;
    }
    int status = OK;
    if (r < 0) status = ERRO_ENTRADA;
    else if (lidos < n) {
        fprintf(stderr, "Erro: '%s' contém apenas %lld números, mas foram solicitados %lld\n", nome_arq, lidos, n);
        status = ERRO_ENTRADA;
    } else if (pular_espacos(&L) != EOF) {
        fprintf(stderr, "Aviso: '%s' contém mais dados após os %lld números solicitados (ignorados)\n", nome_arq, n);
    }
    free(L.buf);
    fclose(f);
    *soma = s;
    *xr = x;
    return status;
}

/* ------------------------------------------------------------------
 * Radix sort paralelo
 * ------------------------------------------------------------------ */

/* Máximo do array com o MESMO número de threads das outras fases (C2). */
static int get_max(const int *arr, long long n, int nt, int *erro_threads) {
    int mx = 0;                 /* a entrada só tem valores >= 0 */
    #pragma omp parallel num_threads(nt) reduction(max:mx)
    {
        DEBUG_REGIAO("get_max");
        if (omp_get_num_threads() != nt) {
            #pragma omp atomic write
            *erro_threads = 1;
        }
        #pragma omp for schedule(static)
        for (long long i = 0; i < n; i++)
            if (arr[i] > mx) mx = arr[i];
    }
    return mx;
}

/* Ordena arr[0..n-1]. Retorna OK ou ERRO_RECURSO. */
static int radix_sort(int *arr, long long n, int nt, int *passadas_out) {
    *passadas_out = 0;
    if (n <= 1) return OK;

    /* M1: alocações feitas uma única vez */
    int *buf = malloc((size_t)n * sizeof(int));
    HistPad *hist = ALLOC_ALINHADO((size_t)nt * sizeof(HistPad));
    if (!buf || !hist) {
        fprintf(stderr, "Erro: falha ao alocar memória\n");
        free(buf);
        if (hist) FREE_ALINHADO(hist);
        return ERRO_RECURSO;
    }
    /* Zera tudo: se o runtime entregar menos threads (erro detectado
     * abaixo), as entradas das threads inexistentes contam como 0 e
     * nenhuma escrita sai dos limites de dst antes do aborto. */
    memset(hist, 0, (size_t)nt * sizeof(HistPad));

    int erro_threads = 0;
    const int m = get_max(arr, n, nt, &erro_threads);
    int *src = arr, *dst = buf;
    int passadas = 0;

    /* C6: exp em long long — com m próximo de INT_MAX, exp chega a 1e10 */
    for (long long exp = 1; !erro_threads && m / exp > 0; exp *= 10) {
        const int e = (int)exp;   /* seguro: exp <= m <= INT_MAX dentro do laço */

        /* M3: contagem, prefixo e distribuição numa única região */
        #pragma omp parallel num_threads(nt)
        {
            DEBUG_REGIAO("radix_passada");
            const int t = omp_get_thread_num();
            if (omp_get_num_threads() != nt) {
                #pragma omp atomic write
                erro_threads = 1;
            }
            const long long ini = (long long)t * n / nt;
            const long long fim = (long long)(t + 1) * n / nt;
            long long *h = hist[t].h;

            /* FASE 1: contagem local */
            for (int d = 0; d < 10; d++) h[d] = 0;
            for (long long i = ini; i < fim; i++)
                h[(src[i] / e) % 10]++;

            #pragma omp barrier

            /* FASE 2: prefixo global na ordem (dígito, thread) — garante
             * faixas disjuntas e estabilidade. Barreira implícita no fim. */
            #pragma omp single
            {
                long long pos = 0;
                for (int d = 0; d < 10; d++)
                    for (int tt = 0; tt < nt; tt++) {
                        long long c = hist[tt].h[d];
                        hist[tt].h[d] = pos;
                        pos += c;
                    }
            }

            /* FASE 3: distribuição estável */
            for (long long i = ini; i < fim; i++) {
                const int v = src[i];
                dst[h[(v / e) % 10]++] = v;
            }
        }

        /* M2: troca de ponteiros no lugar do memcpy por passada */
        int *tmp = src; src = dst; dst = tmp;
        passadas++;
    }

    if (!erro_threads && src != arr)          /* nº ímpar de passadas */
        memcpy(arr, src, (size_t)n * sizeof(int));

    free(buf);
    FREE_ALINHADO(hist);
    *passadas_out = passadas;

    if (erro_threads) {
        fprintf(stderr, "Erro: o runtime OpenMP não entregou %d threads em uma região paralela\n", nt);
        return ERRO_RECURSO;
    }
    return OK;
}

/* ------------------------------------------------------------------
 * Verificação (C8): ordem + mesmo multiconjunto (soma e XOR)
 * ------------------------------------------------------------------ */
static int verificar(const int *arr, long long n, unsigned long long soma_ent, unsigned int xor_ent) {
    unsigned long long s = 0;
    unsigned int x = 0;
    for (long long i = 0; i < n; i++) {
        if (i > 0 && arr[i - 1] > arr[i]) {
            fprintf(stderr, "Erro: verificação falhou — posição %lld fora de ordem (%d > %d)\n", i, arr[i - 1], arr[i]);
            return ERRO_VERIFICACAO;
        }
        s += (unsigned int)arr[i];
        x ^= (unsigned int)arr[i];
    }
    if (s != soma_ent || x != xor_ent) {
        fprintf(stderr, "Erro: verificação falhou — os elementos ordenados não correspondem aos da entrada\n");
        return ERRO_VERIFICACAO;
    }
    return OK;
}

/* ------------------------------------------------------------------
 * Escrita (C7): bufferizada, com checagem de erros e renomeação atômica
 * ------------------------------------------------------------------ */
static int escrever_saida(const char *caminho, const int *arr, long long n) {
    /* Se o destino existe e NÃO é arquivo regular (ex.: /dev/null),
     * escreve direto nele; senão usa <caminho>.tmp + rename. */
    struct stat st;
    int direto = (stat(caminho, &st) == 0 && !S_ISREG(st.st_mode));

    size_t tam_nome = strlen(caminho) + 5;
    char *tmp_nome = malloc(tam_nome);
    char *buf = malloc(TAM_BUF_ES);
    if (!tmp_nome || !buf) { fprintf(stderr, "Erro: falha ao alocar memória\n"); free(tmp_nome); free(buf); return ERRO_RECURSO; }
    snprintf(tmp_nome, tam_nome, "%s.tmp", caminho);
    const char *alvo = direto ? caminho : tmp_nome;

    FILE *f = fopen(alvo, "wb");   /* "wb": sempre LF, também no Windows */
    if (!f) {
        fprintf(stderr, "Erro: não foi possível criar '%s': %s\n", alvo, strerror(errno));
        free(tmp_nome); free(buf);
        return ERRO_SAIDA;
    }

    size_t p = 0;
    for (long long i = 0; i < n; i++) {
        if (p > TAM_BUF_ES - 16) {
            if (fwrite(buf, 1, p, f) != p) goto falha;
            p = 0;
        }
        unsigned int v = (unsigned int)arr[i];
        char dig[12];
        int k = 0;
        do { dig[k++] = (char)('0' + v % 10); v /= 10; } while (v);
        while (k) buf[p++] = dig[--k];
        buf[p++] = '\n';
    }
    if (p && fwrite(buf, 1, p, f) != p) goto falha;
    if (fflush(f) != 0) goto falha;
    if (fclose(f) != 0) { f = NULL; goto falha; }
    f = NULL;

    if (!direto) {
#ifdef _WIN32
        remove(caminho);            /* rename não sobrescreve no Windows */
#endif
        if (rename(tmp_nome, caminho) != 0) {
            fprintf(stderr, "Erro: não foi possível renomear '%s' para '%s': %s\n", tmp_nome, caminho, strerror(errno));
            remove(tmp_nome);
            free(tmp_nome); free(buf);
            return ERRO_SAIDA;
        }
    }
    free(tmp_nome); free(buf);
    return OK;

falha:
    fprintf(stderr, "Erro: falha ao escrever '%s': %s\n", alvo, strerror(errno));
    if (f) fclose(f);
    if (!direto) remove(tmp_nome);  /* não deixa arquivo incompleto */
    free(tmp_nome); free(buf);
    return ERRO_SAIDA;
}

/* ------------------------------------------------------------------ */
int main(int argc, char *argv[]) {
    const double t0 = agora();

    if (argc != 4 && argc != 5) {
        fprintf(stderr, "Uso: %s <arquivo_entrada> <arquivo_saida> <quantidade> [n_threads]\n", argv[0]);
        return ERRO_ARGS;
    }
    const char *arquivo_entrada = argv[1];
    const char *arquivo_saida   = argv[2];

    int quantidade;
    if (!ler_inteiro_positivo(argv[3], "quantidade", INT_MAX, &quantidade)) return ERRO_ARGS;

    /* Threads: 4º argumento > OMP_NUM_THREADS > todos os núcleos */
    int n_threads;
    if (argc == 5) {
        if (!ler_inteiro_positivo(argv[4], "n_threads", MAX_THREADS, &n_threads)) return ERRO_ARGS;
    } else {
        n_threads = omp_get_max_threads();
    }

    /* C1 + M4: fixa o tamanho da equipe, confere e aquece o pool */
    omp_set_dynamic(0);
    omp_set_num_threads(n_threads);
    int reais = 0;
    #pragma omp parallel num_threads(n_threads)
    {
        DEBUG_REGIAO("aquecimento");
        #pragma omp single
        reais = omp_get_num_threads();
    }
    if (reais != n_threads) {
        fprintf(stderr, "Erro: pedidas %d threads, mas o runtime OpenMP entregou %d "
                        "(verifique OMP_THREAD_LIMIT e os limites do sistema)\n", n_threads, reais);
        return ERRO_RECURSO;
    }

    /* Leitura */
    int *arr = malloc((size_t)quantidade * sizeof(int));
    if (!arr) { fprintf(stderr, "Erro: falha ao alocar memória para %d números\n", quantidade); return ERRO_RECURSO; }
    unsigned long long soma = 0;
    unsigned int xr = 0;
    const double t_leit0 = agora();
    int st = ler_entrada(arquivo_entrada, arr, quantidade, &soma, &xr);
    const double t_leit1 = agora();
    if (st != OK) { free(arr); return st; }

    /* Ordenação — única parte medida em TEMPO_SORT_S */
    int passadas = 0;
    const double t_sort0 = agora();
    st = radix_sort(arr, quantidade, n_threads, &passadas);
    const double t_sort1 = agora();
    if (st != OK) { free(arr); return st; }

    /* Verificação (fora da medição do sort) */
    const double t_ver0 = agora();
    st = verificar(arr, quantidade, soma, xr);
    const double t_ver1 = agora();
    if (st != OK) { free(arr); return st; }

    /* Escrita */
    const double t_esc0 = agora();
    st = escrever_saida(arquivo_saida, arr, quantidade);
    const double t_esc1 = agora();
    free(arr);
    if (st != OK) return st;

    const double t1 = agora();
    fprintf(stderr, "VERSAO=%s\n", VERSAO);
    fprintf(stderr, "N_THREADS=%d\n", reais);
    fprintf(stderr, "N_PASSADAS=%d\n", passadas);
    fprintf(stderr, "TEMPO_LEITURA_S=%.9f\n", t_leit1 - t_leit0);
    fprintf(stderr, "TEMPO_SORT_S=%.9f\n", t_sort1 - t_sort0);
    fprintf(stderr, "TEMPO_VERIFICACAO_S=%.9f\n", t_ver1 - t_ver0);
    fprintf(stderr, "TEMPO_ESCRITA_S=%.9f\n", t_esc1 - t_esc0);
    fprintf(stderr, "TEMPO_DECORRIDO_S=%.9f\n", t1 - t0);
    fprintf(stderr, "VERIFICACAO=OK\n");
    return OK;
}
