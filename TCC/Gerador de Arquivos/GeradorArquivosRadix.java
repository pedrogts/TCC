import java.io.*;
import java.util.*;

public class GeradorArquivosRadix {

    public static void gerar(int n, int d) throws IOException {
        int minD = (int) Math.pow(10, d - 1);
        int maxD = (int) Math.pow(10, d) - 1;

        ArrayList<Integer> melhor = gerarAleatorio(n, 1, 9);
        salvar(melhor, "radix_melhor_1M.txt");

        ArrayList<Integer> medio = gerarAleatorio(n, 1, maxD);
        salvar(medio, "radix_medio_1M.txt");

        ArrayList<Integer> pior = gerarAleatorio(n, minD, maxD);
        salvar(pior, "radix_pior_1M.txt");
    }

    private static ArrayList<Integer> gerarAleatorio(int n, int min, int max) {
        Random rand = new Random();
        ArrayList<Integer> lista = new ArrayList<>(n);
        for (int i = 0; i < n; i++) lista.add(min + rand.nextInt(max - min + 1));
        return lista;
    }

    private static void salvar(ArrayList<Integer> lista, String nomeArquivo) throws IOException {
        File arquivo = new File(GeradorArquivosMain.DIR_SAIDA, nomeArquivo);
        try (PrintWriter pw = new PrintWriter(new FileWriter(arquivo))) {
            for (Integer num : lista) {
                pw.println(num);
            }
        }
        System.out.println("  -> " + arquivo.getPath());
    }
}