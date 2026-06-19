import sys

def smooth_sort(arr):
    if len(arr) < 2:
        return

    # Geração dos números de Leonardo
    leo = [1, 1]
    while leo[-1] < len(arr):
        leo.append(leo[-1] + leo[-2] + 1)

    def sift(root_idx, k):
        curr = root_idx
        while k >= 2:
            right = curr - 1
            left = right - leo[k - 2]
            max_idx = curr
            next_k = k
            if arr[left] > arr[max_idx]:
                max_idx = left
                next_k = k - 1
            if arr[right] > arr[max_idx]:
                max_idx = right
                next_k = k - 2
            if max_idx == curr:
                break
            arr[curr], arr[max_idx] = arr[max_idx], arr[curr]
            curr = max_idx
            k = next_k

    def trinkle(floresta, arr_end):
        idx = len(floresta) - 1
        curr_root = arr_end
        while idx > 0:
            prev_root = curr_root - leo[floresta[idx]]
            if arr[prev_root] > arr[curr_root]:
                if floresta[idx] >= 2:
                    right = curr_root - 1
                    left = right - leo[floresta[idx] - 2]
                    if arr[prev_root] <= arr[left] or arr[prev_root] <= arr[right]:
                        break
                arr[curr_root], arr[prev_root] = arr[prev_root], arr[curr_root]
                curr_root = prev_root
                idx -= 1
            else:
                break
        sift(curr_root, floresta[idx])

    floresta = []
    for i in range(len(arr)):
        if len(floresta) >= 2 and floresta[-2] == floresta[-1] + 1:
            floresta.pop()
            floresta[-1] += 1
        else:
            if len(floresta) >= 1 and floresta[-1] == 1:
                floresta.append(0)
            else:
                floresta.append(1)
        trinkle(floresta, i)

    for i in range(len(arr) - 1, 0, -1):
        k = floresta.pop()
        if k >= 2:
            floresta.append(k - 1)
            left_root = i - 1 - leo[k - 2]
            trinkle(floresta, left_root)
            floresta.append(k - 2)
            right_root = i - 1
            trinkle(floresta, right_root)

if __name__ == "__main__":
    # Garante que o Linux passou os parâmetros obrigatórios
    if len(sys.argv) != 4:
        print("Uso correto: python3 smooth_puro.py <entrada.txt> <saida.txt> <quantidade>")
        sys.exit(1)

    arquivo_entrada = sys.argv[1]
    arquivo_saida = sys.argv[2]
    quantidade = int(sys.argv[3])

    # 1. Leitura estrita delimitada pelo N do Bash
    arr = []
    with open(arquivo_entrada, 'r') as f:
        for linha in f:
            linha = linha.strip()
            if linha.isdigit():
                arr.append(int(linha))
                if len(arr) == quantidade:
                    break

    # 2. Execução do algoritmo na memória
    smooth_sort(arr)

    # 3. Escrita do resultado ordenado
    with open(arquivo_saida, 'w') as f:
        for num in arr:
            f.write(f"{num}\n")