import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.BrokenBarrierException;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

public class RadixSortParalelo implements AutoCloseable {

    public static final class RadixSortException extends Exception {
        public RadixSortException(String msg) { super(msg); }
    }

    private final int nt;
    private final ExecutorService pool;

    public RadixSortParalelo(int nThreads) {
        this.nt = nThreads;
        this.pool = Executors.newFixedThreadPool(nThreads, r -> {
            Thread th = new Thread(r);
            th.setDaemon(true);
            return th;
        });
    }

    public int getNThreads() {
        return nt;
    }

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

    public int ordenar(int[] arr) throws RadixSortException {
        int n = arr.length;
        if (n <= 1) return 0;

        int[] buf;
        try {
            buf = new int[n];
        } catch (OutOfMemoryError e) {
            throw new RadixSortException("Erro: falha ao alocar memória");
        }

        Execucao ex = new Execucao(arr, buf, nt);
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

        int p = ex.passadas;
        if ((p & 1) == 1)
            System.arraycopy(buf, 0, arr, 0, n);
        return p;
    }

    @Override
    public void close() {
        pool.shutdownNow();
    }

    private static final class Execucao {
        final int[] arr, buf;
        final int n, nt;
        final int[][] hist;
        final int[] maxLocal;
        final CyclicBarrier bMax, bPrefixo, bFim;
        volatile Throwable falha = null;
        volatile int passadas = 0;

        Execucao(int[] arr, int[] buf, int nt) {
            this.arr = arr;
            this.buf = buf;
            this.n = arr.length;
            this.nt = nt;
            this.hist = new int[nt][10 + 32];
            this.maxLocal = new int[nt * 16];
            this.bMax = new CyclicBarrier(nt);
            this.bFim = new CyclicBarrier(nt);
            this.bPrefixo = new CyclicBarrier(nt, () -> {
                int pos = 0;
                for (int d = 0; d < 10; d++)
                    for (int t = 0; t < nt; t++) {
                        int c = hist[t][d];
                        hist[t][d] = pos;
                        pos += c;
                    }
            });
        }

        void quebrarBarreiras() {
            bMax.reset();
            bPrefixo.reset();
            bFim.reset();
        }

        void trabalhador(int t) {
            try {
                final int ini = (int) ((long) t * n / nt);
                final int fim = (int) ((long) (t + 1) * n / nt);
                final int[] h = hist[t];

                int mx = 0;
                for (int i = ini; i < fim; i++) if (arr[i] > mx) mx = arr[i];
                maxLocal[t * 16] = mx;
                bMax.await();
                int m = 0;
                for (int k = 0; k < nt; k++) m = Math.max(m, maxLocal[k * 16]);

                int[] src = arr, dst = buf;
                int p = 0;
                for (long exp = 1; m / exp > 0; exp *= 10) {
                    final int e = (int) exp;

                    Arrays.fill(h, 0, 10, 0);
                    for (int i = ini; i < fim; i++) h[(src[i] / e) % 10]++;

                    bPrefixo.await();

                    for (int i = ini; i < fim; i++) {
                        final int v = src[i];
                        dst[h[(v / e) % 10]++] = v;
                    }

                    bFim.await();

                    int[] tmp = src; src = dst; dst = tmp;
                    p++;
                }
                if (t == 0) passadas = p;
            } catch (BrokenBarrierException | InterruptedException e) {
            } catch (Throwable e) {
                falha = e;
                quebrarBarreiras();
            }
        }
    }
}