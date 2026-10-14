import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

public class RadixSortParalelo implements AutoCloseable {

    public static final class RadixSortException extends Exception {
        public RadixSortException(String msg) { super(msg); }
    }

    private static final int PASSO = 32;

    private static final int PASSO_L = 16;

    private static final int SPIN_PADRAO = 8192;

    private final int nt;
    private final int spinMax;
    private final ExecutorService pool;

    private int[] buf;
    private double esperaMaxS = 0;
    private double esperaMediaS = 0;

    public RadixSortParalelo(int nThreads) {
        this.nt = nThreads;
        final int spinConfig = Math.max(0, Integer.getInteger("radix.spin", SPIN_PADRAO));

        this.spinMax = (nThreads <= Runtime.getRuntime().availableProcessors()) ? spinConfig : 0;
        this.pool = Executors.newFixedThreadPool(nThreads, r -> {
            Thread th = new Thread(r);
            th.setDaemon(true);
            return th;
        });
    }

    public int getNThreads() { return nt; }
    public int getSpinMax() { return spinMax; }

    public double getEsperaBarreiraMaxS() { return esperaMaxS; }

    public double getEsperaBarreiraMediaS() { return esperaMediaS; }

    public void aquecer() throws RadixSortException {
        CyclicBarrier aquece = new CyclicBarrier(nt);
        List<Future<?>> fs = new ArrayList<>(nt);
        for (int t = 0; t < nt; t++)
            fs.add(pool.submit(() -> {
                aquece.await(10, TimeUnit.SECONDS);
                return null;
            }));
        try {
            for (Future<?> f : fs) f.get();
        } catch (InterruptedException | ExecutionException e) {
            throw new RadixSortException("Erro: não foi possível obter " + nt + " threads simultâneas: " + e);
        }
    }

    public void preparar(int n) throws RadixSortException {
        if (n <= 1) return;
        if (buf != null && buf.length == n) return;
        buf = null;
        try {
            buf = new int[n];
        } catch (OutOfMemoryError e) {
            throw new RadixSortException("Erro: falha ao alocar memória");
        }
    }

    public int ordenar(int[] arr) throws RadixSortException {
        final int n = arr.length;
        esperaMaxS = 0;
        esperaMediaS = 0;
        if (n <= 1) return 0;

        preparar(n);
        final int[] aux = this.buf;

        final Execucao ex = new Execucao(arr, aux, nt, spinMax);
        List<Future<?>> fs = new ArrayList<>(nt);
        for (int t = 0; t < nt; t++) {
            final int id = t;
            fs.add(pool.submit(() -> ex.trabalhador(id)));
        }
        try {
            for (Future<?> f : fs) f.get();
        } catch (InterruptedException | ExecutionException e) {
            throw new RadixSortException("Erro: falha na execução paralela: " + e);
        }
        if (ex.falha != null)
            throw new RadixSortException("Erro: falha em uma thread de ordenação: " + ex.falha);

        long max = 0, soma = 0;
        for (int t = 0; t < nt; t++) {
            final long v = ex.esperaNs[t * PASSO_L];
            if (v > max) max = v;
            soma += v;
        }
        esperaMaxS = max / 1e9;
        esperaMediaS = (soma / (double) nt) / 1e9;

        final int p = ex.passadas;
        if ((p & 1) == 1)
            System.arraycopy(aux, 0, arr, 0, n);
        return p;
    }

    @Override
    public void close() {
        pool.shutdownNow();
    }

    private static final class BarreiraQuebrada extends RuntimeException {
        BarreiraQuebrada() { super(null, null, false, false); }
    }

    private static final class BarreiraSpin {
        private final int n;
        private final int spinMax;
        private final AtomicInteger restantes;
        private volatile int geracao = 0;
        private volatile boolean quebrada = false;
        private final BarreiraQuebrada sinal = new BarreiraQuebrada();

        BarreiraSpin(int n, int spinMax) {
            this.n = n;
            this.spinMax = spinMax;
            this.restantes = new AtomicInteger(n);
        }

        void quebrar() { quebrada = true; }

        void esperar() {
            if (quebrada) throw sinal;
            final int g = geracao;
            if (restantes.decrementAndGet() == 0) {
                restantes.set(n);
                geracao = g + 1;
                return;
            }
            int spins = 0;
            while (geracao == g) {
                if (quebrada) throw sinal;
                if (spins < spinMax) {
                    spins++;
                    Thread.onSpinWait();
                } else {
                    Thread.yield();
                    if (Thread.interrupted()) {
                        quebrada = true;
                        throw sinal;
                    }
                }
            }
        }
    }

    private static int maximoEUnidades(int[] a, int ini, int fim, int[] cont) {
        int mx = 0;
        for (int i = ini; i < fim; i++) {
            final int v = a[i];
            if (v > mx) mx = v;
            cont[v % 10]++;
        }
        return mx;
    }

    private static void contar(int[] src, int ini, int fim, int e, int[] cont) {
        for (int i = ini; i < fim; i++) cont[(src[i] / e) % 10]++;
    }

    private static void distribuir(int[] src, int[] dst, int ini, int fim, int e, int[] pos) {
        for (int i = ini; i < fim; i++) {
            final int v = src[i];
            dst[pos[(v / e) % 10]++] = v;
        }
    }

    private static final class Execucao {
        final int[] arr, buf;
        final int n, nt;
        final int[] hist;
        final int[] maxLocal;
        final long[] esperaNs;
        final BarreiraSpin barreira;
        volatile Throwable falha = null;
        volatile int passadas = 0;

        Execucao(int[] arr, int[] buf, int nt, int spinMax) {
            this.arr = arr;
            this.buf = buf;
            this.n = arr.length;
            this.nt = nt;
            this.hist = new int[nt * PASSO];
            this.maxLocal = new int[nt * PASSO];
            this.esperaNs = new long[nt * PASSO_L];
            this.barreira = new BarreiraSpin(nt, spinMax);
        }

        private long esperarBarreira() {
            final long t0 = System.nanoTime();
            barreira.esperar();
            return System.nanoTime() - t0;
        }

        void trabalhador(int t) {
            try {
                final int ini = (int) ((long) t * n / nt);
                final int fim = (int) ((long) (t + 1) * n / nt);
                final int[] cont = new int[10];
                final int[] pos = new int[10];
                long espera = 0;

                maxLocal[t * PASSO] = maximoEUnidades(arr, ini, fim, cont);
                System.arraycopy(cont, 0, hist, t * PASSO, 10);
                espera += esperarBarreira();

                int m = 0;
                for (int k = 0; k < nt; k++) m = Math.max(m, maxLocal[k * PASSO]);

                int[] src = arr, dst = buf;
                int p = 0;
                for (long exp = 1; m / exp > 0; exp *= 10) {
                    final int e = (int) exp;
                    final boolean ultima = (m / (exp * 10)) == 0;

                    if (p > 0) {
                        Arrays.fill(cont, 0);
                        contar(src, ini, fim, e, cont);
                        System.arraycopy(cont, 0, hist, t * PASSO, 10);
                        espera += esperarBarreira();
                    }

                    int acum = 0;
                    for (int d = 0; d < 10; d++)
                        for (int k = 0; k < nt; k++) {
                            final int c = hist[k * PASSO + d];
                            if (k == t) pos[d] = acum;
                            acum += c;
                        }

                    distribuir(src, dst, ini, fim, e, pos);

                    if (!ultima) espera += esperarBarreira();

                    final int[] tmp = src; src = dst; dst = tmp;
                    p++;
                }
                if (t == 0) passadas = p;
                esperaNs[t * PASSO_L] = espera;
            } catch (BarreiraQuebrada ignorada) {

            } catch (Throwable e) {
                falha = e;
                barreira.quebrar();
            }
        }
    }
}
