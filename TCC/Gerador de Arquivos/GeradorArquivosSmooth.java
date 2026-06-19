import java.io.*;
import java.util.*;

public class GeradorArquivosSmooth {

    public static void gerar(int n) throws IOException {
        ArrayList<Integer> melhor = gerarCrescente(n);
        salvar(melhor, "smooth_melhor_1M.txt");

        ArrayList<Integer> medio = gerarAleatorio(n, 1, 9_999_999);
        salvar(medio, "smooth_medio_1M.txt");

        ArrayList<Integer> pior = gerarDecrescente(n);
        salvar(pior, "smooth_pior_1M.txt");
    }

    private static ArrayList<Integer> gerarCrescente(int n) {
        ArrayList<Integer> lista = new ArrayList<>(n);
        for (int i = 1; i <= n; i++) lista.add(i);
        return lista;
    }

    private static ArrayList<Integer> gerarDecrescente(int n) {
        ArrayList<Integer> lista = new ArrayList<>(n);
        for (int i = n; i >= 1; i--) lista.add(i);
        return lista;
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