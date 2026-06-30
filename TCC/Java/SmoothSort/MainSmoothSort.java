import java.io.*;
import java.util.*;
import java.nio.file.Files;
import java.nio.file.Paths;

public class MainSmoothSort {

    public static void main(String[] args) throws IOException {
        if (args.length < 2) {
            System.out.println("Uso: java MainSmoothSort <arquivo_entrada> <arquivo_saida> [quantidade]");
            return;
        }

        List<String> linhas = Files.readAllLines(Paths.get(args[0]));

        int quantidade = linhas.size();
        if (args.length >= 3) {
            quantidade = Math.min(Integer.parseInt(args[2]), linhas.size());
        }

        Integer[] dados = linhas.subList(0, quantidade)
                .stream()
                .map(Integer::parseInt)
                .toArray(Integer[]::new);

        System.out.println("Ordenando " + quantidade + " numeros com SmoothSort...");
        SmoothSort.ordenar(dados, 0, dados.length - 1);

        List<String> resultado = new ArrayList<>();
        for (int v : dados) resultado.add(String.valueOf(v));
        Files.write(Paths.get(args[1]), resultado);
        System.out.println("Arquivo ordenado salvo em: " + args[1]);
    }
}