import java.util.*;

public class SmoothSort {

    private static int leonardo(int n) {
        if (n <= 1) return 1;
        int a = 1, b = 1;
        for (int i = 2; i <= n; i++) {
            int temp = a + b + 1;
            a = b;
            b = temp;
        }
        return b;
    }

    private static <C extends Comparable<? super C>> void peneirar(C[] m, int pdeslocamento, int cabeca) {
        C val = m[cabeca];
        while (pdeslocamento > 1) {
            int dir = cabeca - 1;
            int esq = cabeca - 1 - leonardo(pdeslocamento - 2);
            if (val.compareTo(m[esq]) >= 0 && val.compareTo(m[dir]) >= 0) break;
            if (m[esq].compareTo(m[dir]) >= 0) {
                m[cabeca] = m[esq];
                cabeca = esq;
                pdeslocamento -= 1;
            } else {
                m[cabeca] = m[dir];
                cabeca = dir;
                pdeslocamento -= 2;
            }
        }
        m[cabeca] = val;
    }

    private static <C extends Comparable<? super C>> void trincar(C[] m, int p, int pdeslocamento, int cabeca, boolean ehConfiavel) {
        C val = m[cabeca];
        while (p != 1) {
            int enteado = cabeca - leonardo(pdeslocamento);
            if (m[enteado].compareTo(val) <= 0) break;
            if (!ehConfiavel && pdeslocamento > 1) {
                int dir = cabeca - 1;
                int esq = cabeca - 1 - leonardo(pdeslocamento - 2);
                if (m[dir].compareTo(m[enteado]) >= 0 || m[esq].compareTo(m[enteado]) >= 0) break;
            }
            m[cabeca] = m[enteado];
            cabeca = enteado;
            int rastro = Integer.numberOfTrailingZeros(p & ~1);
            p >>>= rastro;
            pdeslocamento += rastro;
            ehConfiavel = false;
        }
        if (!ehConfiavel) {
            m[cabeca] = val;
            peneirar(m, pdeslocamento, cabeca);
        }
    }

    public static void ordenar(Integer[] m, int inicio, int fim) {
        int cabeca = inicio;
        int p = 1;
        int pdeslocamento = 1;
        while (cabeca < fim) {
            if ((p & 3) == 3) {
                peneirar(m, pdeslocamento, cabeca);
                p >>>= 2;
                pdeslocamento += 2;
            } else {
                if (leonardo(pdeslocamento - 1) >= fim - cabeca) {
                    trincar(m, p, pdeslocamento, cabeca, false);
                } else {
                    peneirar(m, pdeslocamento, cabeca);
                }
                if (pdeslocamento == 1) {
                    p <<= 1;
                    pdeslocamento--;
                } else {
                    p <<= (pdeslocamento - 1);
                    pdeslocamento = 1;
                }
            }
            p |= 1;
            cabeca++;
        }
        trincar(m, p, pdeslocamento, cabeca, false);
        while (pdeslocamento != 1 || p != 1) {
            if (pdeslocamento <= 1) {
                int rastro = Integer.numberOfTrailingZeros(p & ~1);
                p >>>= rastro;
                pdeslocamento += rastro;
            } else {
                p <<= 2;
                p ^= 7;
                pdeslocamento -= 2;
                trincar(m, p >>> 1, pdeslocamento + 1, cabeca - leonardo(pdeslocamento) - 1, true);
                trincar(m, p, pdeslocamento, cabeca - 1, true);
            }
            cabeca--;
        }
    }
}