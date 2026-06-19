import java.io.*;

public class GeradorArquivosMain {

    public static final int TAMANHO = 1_000_000;
    public static final int DIGITOS = 9;
    public static final String DIR_SAIDA = "arquivos_teste";

    public static void main(String[] args) throws IOException {
        new File(DIR_SAIDA).mkdirs();

        System.out.println("Gerando arquivos para n = " + TAMANHO + ", d = " + DIGITOS + "...");
        GeradorArquivosRadix.gerar(TAMANHO, DIGITOS);
        GeradorArquivosSmooth.gerar(TAMANHO);

        System.out.println("\nConcluído! Arquivos gerados em: " + DIR_SAIDA + "/");
    }
}