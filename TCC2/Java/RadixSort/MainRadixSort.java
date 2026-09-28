import java.io.*;
import java.nio.file.*;
import java.util.*;

public class MainRadixSortParalelo {

    static final String VERSAO = "v3-java";
    static final int MAX_THREADS = 1024;
    static final int TAM_BUF_ES = 1 << 20;

    static final int OK = 0, ERRO_ARGS = 1, ERRO_ENTRADA = 2, ERRO_RECURSO = 3,
            ERRO_VERIFICACAO = 4, ERRO_SAIDA = 5;

    static final class ErroPrograma extends Exception {
        final int codigo;
        ErroPrograma(int codigo, String msg) { super(msg); this.codigo = codigo; }
    }

    static double agora() { return System.nanoTime() / 1e9; }

    static int lerInteiroPositivo(String s, String nome, long limite) throws ErroPrograma {
        try {
            long v = Long.parseLong(s);
            if (v > 0 && v <= limite) return (int) v;
        } catch (NumberFormatException ignorado) { }
        throw new ErroPrograma(ERRO_ARGS, "Erro: " + nome + " inválido: '" + s
                + "' (esperado inteiro entre 1 e " + limite + ")");
    }

    static final class Leitor {
        final InputStream in;
        final byte[] buf = new byte[TAM_BUF_ES];
        int len = 0, pos = 0;
        boolean fim = false;
        long linha = 1;
        int valor;

        Leitor(InputStream in) { this.in = in; }

        int prox() throws IOException {
            if (pos == len) {
                if (fim) return -1;
                len = in.read(buf, 0, buf.length);
                pos = 0;
                if (len <= 0) { len = 0; fim = true; return -1; }
            }
            return buf[pos++] & 0xFF;
        }

        static boolean ehEspaco(int c) { return c == ' ' || c == '\n' || c == '\r' || c == '\t'; }

        int pularEspacos() throws IOException {
            int c;
            do {
                c = prox();
                if (c == '\n') linha++;
            } while (ehEspaco(c));
            return c;
        }

        boolean lerNumero(String nomeArq) throws IOException, ErroPrograma {
            int c = pularEspacos();
            if (c == -1) return false;
            if (c == '-')
                throw new ErroPrograma(ERRO_ENTRADA, "Erro: '" + nomeArq + "' linha " + linha
                        + ": número negativo — não suportado por esta versão");
            if (c < '0' || c > '9')
                throw new ErroPrograma(ERRO_ENTRADA, "Erro: '" + nomeArq + "' linha " + linha
                        + ": caractere inválido '" + car(c) + "' (código " + c
                        + "); esperado um inteiro por linha");
            long v = 0;
            while (c >= '0' && c <= '9') {
                v = v * 10 + (c - '0');
                if (v > Integer.MAX_VALUE)
                    throw new ErroPrograma(ERRO_ENTRADA, "Erro: '" + nomeArq + "' linha " + linha
                            + ": valor maior que " + Integer.MAX_VALUE);
                c = prox();
            }
            if (c == '\n') linha++;
            else if (c != -1 && !ehEspaco(c))
                throw new ErroPrograma(ERRO_ENTRADA, "Erro: '" + nomeArq + "' linha " + linha
                        + ": caractere inválido '" + car(c) + "' (código " + c + ") logo após o número");
            valor = (int) v;
            return true;
        }

        static char car(int c) { return (c >= 32 && c < 127) ? (char) c : '?'; }
    }

    static final class Checksum { long soma; int xor; }

    static void lerEntrada(String nomeArq, int[] arr, int n, Checksum ck) throws ErroPrograma {
        try (InputStream in = new FileInputStream(nomeArq)) {
            Leitor L = new Leitor(in);
            long s = 0;
            int x = 0, lidos = 0;
            while (lidos < n && L.lerNumero(nomeArq)) {
                arr[lidos++] = L.valor;
                s += L.valor;
                x ^= L.valor;
            }
            if (lidos < n)
                throw new ErroPrograma(ERRO_ENTRADA, "Erro: '" + nomeArq + "' contém apenas "
                        + lidos + " números, mas foram solicitados " + n);
            if (L.pularEspacos() != -1)
                System.err.println("Aviso: '" + nomeArq + "' contém mais dados após os "
                        + n + " números solicitados (ignorados)");
            ck.soma = s;
            ck.xor = x;
        } catch (FileNotFoundException e) {
            throw new ErroPrograma(ERRO_ENTRADA, "Erro: não foi possível abrir '" + nomeArq + "': " + e.getMessage());
        } catch (IOException e) {
            throw new ErroPrograma(ERRO_ENTRADA, "Erro: falha de leitura em '" + nomeArq + "': " + e.getMessage());
        }
    }

    static void verificar(int[] arr, Checksum ck) throws ErroPrograma {
        long s = 0;
        int x = 0;
        for (int i = 0; i < arr.length; i++) {
            if (i > 0 && arr[i - 1] > arr[i])
                throw new ErroPrograma(ERRO_VERIFICACAO, "Erro: verificação falhou — posição " + i
                        + " fora de ordem (" + arr[i - 1] + " > " + arr[i] + ")");
            s += arr[i];
            x ^= arr[i];
        }
        if (s != ck.soma || x != ck.xor)
            throw new ErroPrograma(ERRO_VERIFICACAO,
                    "Erro: verificação falhou — os elementos ordenados não correspondem aos da entrada");
    }

    static void escreverSaida(String caminho, int[] arr) throws ErroPrograma {
        Path destino = Paths.get(caminho);
        boolean direto = Files.exists(destino) && !Files.isRegularFile(destino);
        Path tmp = Paths.get(caminho + ".tmp");
        Path alvo = direto ? destino : tmp;

        try {
            try (OutputStream out = Files.newOutputStream(alvo,
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE)) {
                byte[] buf = new byte[TAM_BUF_ES];
                int p = 0;
                byte[] dig = new byte[12];
                for (int i = 0; i < arr.length; i++) {
                    if (p > TAM_BUF_ES - 16) { out.write(buf, 0, p); p = 0; }
                    int v = arr[i], k = 0;
                    do { dig[k++] = (byte) ('0' + v % 10); v /= 10; } while (v != 0);
                    while (k > 0) buf[p++] = dig[--k];
                    buf[p++] = '\n';
                }
                if (p > 0) out.write(buf, 0, p);
            }
            if (!direto) {
                try {
                    Files.move(tmp, destino, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
                } catch (AtomicMoveNotSupportedException e) {
                    Files.move(tmp, destino, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        } catch (IOException e) {
            if (!direto) { try { Files.deleteIfExists(tmp); } catch (IOException ignorado) { } }
            throw new ErroPrograma(ERRO_SAIDA, "Erro: falha ao escrever '" + alvo + "': " + e);
        }
    }

    static int executar(String[] args) throws ErroPrograma {
        final double t0 = agora();

        if (args.length != 3 && args.length != 4)
            throw new ErroPrograma(ERRO_ARGS,
                    "Uso: java MainRadixSortParalelo <arquivo_entrada> <arquivo_saida> <quantidade> [n_threads]");

        final String arquivoEntrada = args[0];
        final String arquivoSaida = args[1];
        final int quantidade = lerInteiroPositivo(args[2], "quantidade", Integer.MAX_VALUE);
        final int nThreads = (args.length == 4)
                ? lerInteiroPositivo(args[3], "n_threads", MAX_THREADS)
                : Runtime.getRuntime().availableProcessors();

        try (RadixSortParalelo sorter = new RadixSortParalelo(nThreads)) {
            try {
                sorter.aquecer();
            } catch (RadixSortParalelo.RadixSortException e) {
                throw new ErroPrograma(ERRO_RECURSO, e.getMessage());
            }

            int[] arr;
            try {
                arr = new int[quantidade];
            } catch (OutOfMemoryError e) {
                throw new ErroPrograma(ERRO_RECURSO, "Erro: falha ao alocar memória para " + quantidade + " números");
            }
            Checksum ck = new Checksum();
            final double tLeit0 = agora();
            lerEntrada(arquivoEntrada, arr, quantidade, ck);
            final double tLeit1 = agora();

            int passadas;
            final double tSort0 = agora();
            try {
                passadas = sorter.ordenar(arr);
            } catch (RadixSortParalelo.RadixSortException e) {
                throw new ErroPrograma(ERRO_RECURSO, e.getMessage());
            }
            final double tSort1 = agora();

            final double tVer0 = agora();
            verificar(arr, ck);
            final double tVer1 = agora();

            final double tEsc0 = agora();
            escreverSaida(arquivoSaida, arr);
            final double tEsc1 = agora();

            final double t1 = agora();
            System.err.printf(Locale.ROOT, "VERSAO=%s%n", VERSAO);
            System.err.printf(Locale.ROOT, "N_THREADS=%d%n", sorter.getNThreads());
            System.err.printf(Locale.ROOT, "N_PASSADAS=%d%n", passadas);
            System.err.printf(Locale.ROOT, "TEMPO_LEITURA_S=%.9f%n", tLeit1 - tLeit0);
            System.err.printf(Locale.ROOT, "TEMPO_SORT_S=%.9f%n", tSort1 - tSort0);
            System.err.printf(Locale.ROOT, "TEMPO_VERIFICACAO_S=%.9f%n", tVer1 - tVer0);
            System.err.printf(Locale.ROOT, "TEMPO_ESCRITA_S=%.9f%n", tEsc1 - tEsc0);
            System.err.printf(Locale.ROOT, "TEMPO_DECORRIDO_S=%.9f%n", t1 - t0);
            System.err.println("VERIFICACAO=OK");
            return OK;
        }
    }

    public static void main(String[] args) {
        int codigo;
        try {
            codigo = executar(args);
        } catch (ErroPrograma e) {
            System.err.println(e.getMessage());
            codigo = e.codigo;
        }
        System.exit(codigo);
    }
}