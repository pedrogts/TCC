import java.util.*;

public class RadixSort {

    static int maximo(int[] arr, int n) {
        int mx = arr[0];
        for (int i = 1; i < n; i++)
            if (arr[i] > mx)
                mx = arr[i];
        return mx;
    }

    static void contagemOrdenada(int[] arr, int n, int exp) {
        int[] saida = new int[n];
        int[] contagem = new int[10];
        Arrays.fill(contagem, 0);
        for (int i = 0; i < n; i++)
            contagem[(arr[i] / exp) % 10]++;
        for (int i = 1; i < 10; i++)
            contagem[i] += contagem[i - 1];
        for (int i = n - 1; i >= 0; i--) {
            saida[contagem[(arr[i] / exp) % 10] - 1] = arr[i];
            contagem[(arr[i] / exp) % 10]--;
        }
        for (int i = 0; i < n; i++)
            arr[i] = saida[i];
    }

    public static void ordenar(int[] arr, int n) {
        int m = maximo(arr, n);
        for (int exp = 1; m / exp > 0; exp *= 10)
            contagemOrdenada(arr, n, exp);
    }
}