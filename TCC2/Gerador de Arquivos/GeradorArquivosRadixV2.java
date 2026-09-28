import java.io.*;
import java.util.*;

/**
 * =============================================================
 * GeradorArquivosRadixV2
 *
 * Gera arquivos de teste para o benchmark do Radix Sort
 * (comparacao sequencial vs. paralelo).
 *
 * Cenario unico: geral/aleatorio — inteiros uniformes em
 * [1, 999_999_999] (ate 9 digitos), um por linha.
 *
 * Mudancas em relacao a versao anterior:
 *  - SEED FIXA (42): toda execucao gera exatamente os mesmos
 *    arquivos, garantindo reprodutibilidade dos experimentos e
 *    comparacao justa entre as versoes sequencial e paralela.
 *  - ESCRITA EM STREAMING: cada numero e escrito direto no
 *    arquivo via BufferedWriter, sem guardar a lista na memoria.
 *    O consumo de RAM fica constante (~alguns KB), permitindo
 *    gerar 100M+ elementos sem ajustar o heap da JVM (-Xmx).
 *
 * Uso:
 *   javac GeradorArquivosRadixV2.java
 *   java GeradorArquivosRadixV2              -> gera 10M, 50M e 100M
 *   java GeradorArquivosRadixV2 1000000      -> gera so o(s) tamanho(s) dado(s)
 *
 * Saida (em arquivos_teste/):
 *   radix_geral_10M.txt   (~100 MB)
 *   radix_geral_50M.txt   (~500 MB)
 *   radix_geral_100M.txt  (~1 GB)
 * =============================================================
 */
public class GeradorArquivosRadixV2 {

    /** Semente fixa: mesma sequencia em toda execucao (reprodutibilidade). */
    public static final long SEED = 42L;

    /** Faixa dos valores: 1 a 999.999.999 (ate 9 digitos). */
    public static final int MIN = 1;
    public static final int MAX = 999_999_999;

    /** Tamanhos padrao quando nenhum argumento e passado. */
    public static final long[] TAMANHOS_PADRAO = {10_000_000L, 50_000_000L, 100_000_000L};

    public static final String DIR_SAIDA = "arquivos_teste";

    public static void main(String[] args) throws IOException {
        long[] tamanhos;
        if (args.length == 0) {
            tamanhos = TAMANHOS_PADRAO;
        } else {
            tamanhos = new long[args.length];
            for (int i = 0; i < args.length; i++) {
                tamanhos[i] = Long.parseLong(args[i]);
                if (tamanhos[i] <= 0) {
                    System.err.println("Erro: tamanho deve ser positivo: " + args[i]);
                    return;
                }
            }
        }

        new File(DIR_SAIDA).mkdirs();
        System.out.println("Gerador V2 — cenario geral, valores em [" + MIN + ", " + MAX + "], seed=" + SEED);

        for (long n : tamanhos) {
            gerar(n);
        }
        System.out.println("\nConcluido! Arquivos em: " + DIR_SAIDA + "/");
    }

    private static void gerar(long n) throws IOException {
        String nome = "radix_geral_" + rotulo(n) + ".txt";
        File arquivo = new File(DIR_SAIDA, nome);

        // Random proprio por arquivo, sempre com a mesma seed:
        // cada arquivo e reprodutivel de forma independente
        // (gerar so o de 50M da o mesmo 50M de sempre).
        Random rand = new Random(SEED);

        long inicio = System.nanoTime();
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(arquivo), 1 << 20)) {
            StringBuilder sb = new StringBuilder(16);
            for (long i = 0; i < n; i++) {
                int valor = MIN + rand.nextInt(MAX - MIN + 1);
                sb.setLength(0);
                sb.append(valor).append('\n');
                bw.write(sb.toString());
            }
        }
        double segundos = (System.nanoTime() - inicio) / 1e9;

        System.out.printf("  -> %s  (%,d numeros, %.1f MB, %.1fs)%n",
                arquivo.getPath(), n, arquivo.length() / 1e6, segundos);
    }

    /** 10_000_000 -> "10M"; 1_500_000 -> "1500k"; 1234 -> "1234". */
    private static String rotulo(long n) {
        if (n % 1_000_000 == 0) return (n / 1_000_000) + "M";
        if (n % 1_000 == 0)     return (n / 1_000) + "k";
        return Long.toString(n);
    }
}