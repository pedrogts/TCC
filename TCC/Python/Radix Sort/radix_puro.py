import sys

def counting_sort(arr, exp):
    n = len(arr)
    output = [0] * n
    count = [0] * 10
    for i in range(n):
        index = arr[i] // exp
        count[index % 10] += 1
    for i in range(1, 10):
        count[i] += count[i - 1]
    i = n - 1
    while i >= 0:
        index = arr[i] // exp
        output[count[index % 10] - 1] = arr[i]
        count[index % 10] -= 1
        i -= 1
    for i in range(n):
        arr[i] = output[i]

def radix_sort(arr):
    if not arr:
        return
    max_num = max(arr)
    exp = 1
    while max_num // exp > 0:
        counting_sort(arr, exp)
        exp *= 10

if __name__ == "__main__":
    # Verifica se o Linux enviou os 3 parâmetros corretos
    if len(sys.argv) != 4:
        print("Uso correto: python3 radix_puro.py <entrada.txt> <saida.txt> <quantidade>")
        sys.exit(1)

    arquivo_entrada = sys.argv[1]
    arquivo_saida = sys.argv[2]
    quantidade = int(sys.argv[3])

    # 1. Leitura estrita da quantidade solicitada pelo Bash
    arr = []
    with open(arquivo_entrada, 'r') as f:
        for linha in f:
            linha = linha.strip()
            if linha.isdigit():
                arr.append(int(linha))
                if len(arr) == quantidade:
                    break  # Para de ler assim que atingir o tamanho N

    # 2. Ordenação Pura
    radix_sort(arr)

    # 3. Escrita do ficheiro de saída
    with open(arquivo_saida, 'w') as f:
        for num in arr:
            f.write(f"{num}\n")