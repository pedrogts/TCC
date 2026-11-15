import os
import random
import sys

def gerar_arquivo(nome, quantidade):
    print(f"A gerar {nome} com {quantidade} números...")
    os.makedirs(os.path.dirname(nome), exist_ok=True)
    with open(nome, 'w') as f:
        bloco = []
        for i in range(quantidade):
            # Gera números até ao limite do int em C (2^31 - 1)
            bloco.append(str(random.randint(0, 2147483647)))
            if len(bloco) >= 100000:
                f.write('\n'.join(bloco) + '\n')
                bloco.clear()
        if bloco:
            f.write('\n'.join(bloco) + '\n')
    print(f"Concluído: {nome}")

if __name__ == '__main__':
    # Gera apenas o ficheiro de 10 milhões para testar
    gerar_arquivo("arquivos_teste/radix_geral_10M.txt", 10000000)
