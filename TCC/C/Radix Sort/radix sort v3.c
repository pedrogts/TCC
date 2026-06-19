#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Retorna o valor máximo do array */
static int get_max(const int *arr, int n) {
    int mx = arr[0];
    for (int i = 1; i < n; i++)
        if (arr[i] > mx) mx = arr[i];
    return mx;
}

/* Counting sort por dígito representado por exp */
static void counting_sort(int *arr, int n, int exp) {
    int *output = malloc(n * sizeof(int));
    if (!output) { fprintf(stderr, "Erro: falha ao alocar memória\n"); exit(EXIT_FAILURE); }

    int count[10] = {0};
    for (int i = 0; i < n; i++) count[(arr[i] / exp) % 10]++;
    for (int i = 1; i < 10; i++) count[i] += count[i-1];
    for (int i = n-1; i >= 0; i--) { output[count[(arr[i] / exp) % 10] - 1] = arr[i]; count[(arr[i] / exp) % 10]--; }

    memcpy(arr, output, n * sizeof(int));
    free(output);
}

/* Radix Sort LSD */
static void radix_sort(int *arr, int n) {
    int m = get_max(arr, n);
    for (int exp = 1; m / exp > 0; exp *= 10)
        counting_sort(arr, n, exp);
}

int main(int argc, char *argv[]) {
    /* Wall clock do processo inteiro — início */
    struct timespec wall_inicio, wall_fim;
    clock_gettime(CLOCK_MONOTONIC, &wall_inicio);

    if (argc != 4) {
        fprintf(stderr, "Uso: %s <arquivo_entrada> <arquivo_saida> <quantidade>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *arquivo_entrada = argv[1];
    const char *arquivo_saida   = argv[2];
    int quantidade = atoi(argv[3]);

    if (quantidade <= 0) { fprintf(stderr, "Erro: quantidade deve ser maior que zero\n"); return EXIT_FAILURE; }

    /* Leitura */
    FILE *fin = fopen(arquivo_entrada, "r");
    if (!fin) { fprintf(stderr, "Erro: não foi possível abrir '%s'\n", arquivo_entrada); return EXIT_FAILURE; }

    int *arr = malloc(quantidade * sizeof(int));
    if (!arr) { fprintf(stderr, "Erro: falha ao alocar memória\n"); fclose(fin); return EXIT_FAILURE; }

    int lidos = 0;
    while (lidos < quantidade && fscanf(fin, "%d", &arr[lidos]) == 1) lidos++;
    fclose(fin);

    if (lidos < quantidade) {
        fprintf(stderr, "Aviso: solicitado %d números, lidos %d\n", quantidade, lidos);
        quantidade = lidos;
    }

    /* Medição de tempo — apenas o sort */
    struct timespec t_inicio, t_fim;
    clock_gettime(CLOCK_MONOTONIC, &t_inicio);

    radix_sort(arr, quantidade);

    clock_gettime(CLOCK_MONOTONIC, &t_fim);

    /* Calcula tempo em segundos com 9 casas decimais (nanossegundos) */
    double tempo_sort = (t_fim.tv_sec - t_inicio.tv_sec) +
                        (t_fim.tv_nsec - t_inicio.tv_nsec) / 1e9;

    /* Imprime tempo no stderr para o script capturar */
    fprintf(stderr, "TEMPO_SORT_S=%.9f\n", tempo_sort);

    /* Escrita */
    FILE *fout = fopen(arquivo_saida, "w");
    if (!fout) { fprintf(stderr, "Erro: não foi possível criar '%s'\n", arquivo_saida); free(arr); return EXIT_FAILURE; }

    for (int i = 0; i < quantidade; i++) fprintf(fout, "%d\n", arr[i]);

    fclose(fout);
    free(arr);

    /* Wall clock do processo inteiro — fim (leitura + sort + escrita) */
    clock_gettime(CLOCK_MONOTONIC, &wall_fim);
    double tempo_decorrido = (wall_fim.tv_sec - wall_inicio.tv_sec) +
                             (wall_fim.tv_nsec - wall_inicio.tv_nsec) / 1e9;
    fprintf(stderr, "TEMPO_DECORRIDO_S=%.9f\n", tempo_decorrido);

    return EXIT_SUCCESS;
}
