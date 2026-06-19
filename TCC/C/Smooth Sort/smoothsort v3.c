#include <stdio.h>
#include <stdlib.h>
#include <time.h>

/*
 * Smoothsort v2 — com medição interna via clock_gettime
 */

static unsigned long long LEO[64];

static void init_leo(void) {
    LEO[0]=1; LEO[1]=1;
    for(int i=2;i<64;i++) LEO[i]=LEO[i-1]+LEO[i-2]+1;
}

static int *A;

static void sift(int root, int k) {
    while (k >= 2) {
        int rc = root - 1;
        int lc = root - 1 - (int)LEO[k-2];
        if (A[root] >= A[lc] && A[root] >= A[rc]) break;
        if (A[lc] >= A[rc]) { int t=A[root];A[root]=A[lc];A[lc]=t; root=lc; k--;   }
        else                { int t=A[root];A[root]=A[rc];A[rc]=t; root=rc; k-=2; }
    }
}

static void trinkle(int root, int *orders, int tree_idx) {
    int cur = root;
    int k   = orders[tree_idx];
    for (int i = tree_idx; i > 0; i--) {
        int prev = cur - (int)LEO[k];
        if (A[cur] >= A[prev]) break;
        if (k >= 2) {
            int rc = cur - 1;
            int lc = rc - (int)LEO[k-2];
            if (A[prev] <= A[lc] || A[prev] <= A[rc]) break;
        }
        int t=A[cur]; A[cur]=A[prev]; A[prev]=t;
        cur = prev;
        k   = orders[i-1];
    }
    sift(cur, k);
}

static void smoothsort(int n) {
    if (n <= 1) return;
    init_leo();

    int orders[64], sz = 0;

    for (int i = 0; i < n; i++) {
        if (sz >= 2 && orders[sz-2] == orders[sz-1] + 1) {
            sz--;
            orders[sz-1]++;
        } else if (sz >= 1 && orders[sz-1] == 1) {
            orders[sz++] = 0;
        } else {
            orders[sz++] = 1;
        }
        trinkle(i, orders, sz-1);
    }

    for (int i = n-1; i >= 0; i--) {
        int k = orders[--sz];
        if (k >= 2) {
            int rc = i - 1;
            int lc = rc - (int)LEO[k-2];
            orders[sz++] = k-1;
            trinkle(lc, orders, sz-1);
            orders[sz++] = k-2;
            trinkle(rc, orders, sz-1);
        }
    }
}

int main(int argc, char *argv[]) {
    /* Wall clock do processo inteiro — início */
    struct timespec wall_inicio, wall_fim;
    clock_gettime(CLOCK_MONOTONIC, &wall_inicio);

    if (argc != 4) {
        fprintf(stderr,"Uso: %s <entrada> <saida> <quantidade>\n",argv[0]);
        return EXIT_FAILURE;
    }

    int n = atoi(argv[3]);
    if (n <= 0) { fprintf(stderr,"Erro: quantidade inválida\n"); return EXIT_FAILURE; }

    FILE *fin = fopen(argv[1],"r");
    if (!fin) { fprintf(stderr,"Erro abrindo %s\n",argv[1]); return EXIT_FAILURE; }

    A = malloc(n * sizeof(int));
    if (!A) { fprintf(stderr,"Erro: memória\n"); fclose(fin); return EXIT_FAILURE; }

    int lidos=0;
    while(lidos<n && fscanf(fin,"%d",&A[lidos])==1) lidos++;
    fclose(fin);
    n=lidos;

    /* Medição de tempo — apenas o sort */
    struct timespec t_inicio, t_fim;
    clock_gettime(CLOCK_MONOTONIC, &t_inicio);

    smoothsort(n);

    clock_gettime(CLOCK_MONOTONIC, &t_fim);

    double tempo_sort = (t_fim.tv_sec - t_inicio.tv_sec) +
                        (t_fim.tv_nsec - t_inicio.tv_nsec) / 1e9;

    fprintf(stderr, "TEMPO_SORT_S=%.9f\n", tempo_sort);

    FILE *fout = fopen(argv[2],"w");
    if (!fout) { fprintf(stderr,"Erro criando %s\n",argv[2]); free(A); return EXIT_FAILURE; }
    for(int i=0;i<n;i++) fprintf(fout,"%d\n",A[i]);
    fclose(fout);
    free(A);

    /* Wall clock do processo inteiro — fim (leitura + sort + escrita) */
    clock_gettime(CLOCK_MONOTONIC, &wall_fim);
    double tempo_decorrido = (wall_fim.tv_sec - wall_inicio.tv_sec) +
                             (wall_fim.tv_nsec - wall_inicio.tv_nsec) / 1e9;
    fprintf(stderr, "TEMPO_DECORRIDO_S=%.9f\n", tempo_decorrido);

    return EXIT_SUCCESS;
}
