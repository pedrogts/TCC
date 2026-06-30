import java.io.*;
import java.util.*;
import java.nio.file.Files;
import java.nio.file.Paths;

public class MainRadixSort {

    public static void main(String[] args) throws IOException {
        if (args.length < 2) {
            System.out.println("Uso: java MainRadixSort <arquivo_entrada> <arquivo_saida> [quantidade]");
            return;
        }

        List<String> linhas = Files.readAllLines(Paths.get(args[0]));

        int quantidade = linhas.size();
        if (args.length >= 3) {
            quantidade = Math.min(Integer.parseInt(args[2]), linhas.size());
        }

        int[] arr = linhas.subList(0, quantidade)
                .stream()
                .mapToInt(Integer::parseInt)
                .toArray();

        System.out.println("Ordenando " + quantidade + " numeros com RadixSort...");
        RadixSort.ordenar(arr, arr.length);

        List<String> resultado = new ArrayList<>();
        for (int v : arr) resultado.add(String.valueOf(v));
        Files.write(Paths.get(args[1]), resultado);
        System.out.println("Arquivo ordenado salvo em: " + args[1]);
    }
}