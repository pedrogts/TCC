# Análise Comparativa de Desempenho: Smoothsort vs Radix Sort

Trabalho de Conclusão de Curso — Análise comparativa de desempenho dos algoritmos de ordenação **Smoothsort** e **Radix Sort** em computação paralela e não paralela, implementados em C, Python e Java.

---

## Sumário

- [Pré-requisitos](#pré-requisitos)
- [Arquivos de Entrada](#arquivos-de-entrada)
- [Como Executar](#como-executar)
  - [C](#c)
  - [Python](#python)
  - [Java](#java)
- [Saídas Geradas](#saídas-geradas)
- [Métricas Coletadas](#métricas-coletadas)

---

## Pré-requisitos

Certifique-se de que os seguintes itens estão instalados no sistema Linux:

- **GCC** (compilador C, suporte a C17)
- **Java 21+** (JDK)
- **Python 3.12+**
- **`perf`** — ferramenta do kernel Linux para medir energia
- **`/usr/bin/time`** — versão GNU do time
- Permissão de `sudo` (necessária para coleta de energia via `perf stat`)

Para instalar as dependências no Ubuntu/Debian:

```bash
sudo apt update
sudo apt install gcc default-jdk python3 linux-tools-common linux-tools-generic time
```

---

## Arquivos de Entrada

Os arquivos de dados devem estar na mesma pasta dos scripts. Os arquivos necessários são:

| Arquivo | Descrição |
|---|---|
| `dados1M_radix_melhor.txt` | 1M de valores — melhor caso para Radix Sort |
| `dados1M_radix_medio.txt` | 1M de valores — caso médio para Radix Sort |
| `dados1M_radix_pior.txt` | 1M de valores — pior caso para Radix Sort |
| `dados1M_smooth_melhor.txt` | 1M de valores — melhor caso para Smoothsort |
| `dados1M_smooth_medio.txt` | 1M de valores — caso médio para Smoothsort |
| `dados1M_smooth_pior.txt` | 1M de valores — pior caso para Smoothsort |

---

## Como Executar

### C

**1. Compile os programas:**

```bash
gcc -O2 -o radix_sort_v3 radix_sort_v3.c
gcc -O2 -o smoothsort_v3 smoothsort_v3.c
```

**2. Execute os benchmarks:**

```bash
bash benchmark_radix_pior_caso_v3.sh
bash benchmark_radix_medio_caso_v3.sh
bash benchmark_radix_melhor_caso_v3.sh
bash benchmark_smooth_medio_caso_v3.sh
bash benchmark_smooth_pior_caso_v3.sh
bash benchmark_smooth_melhor_caso_v3.sh
bash benchmark_radix_5M_v2.sh
bash benchmark_smooth_5M_v2.sh
```

---

### Python

**1. Dê permissão de execução aos scripts:**

```bash
chmod +x benchmark_radix_melhor.sh benchmark_radix_medio.sh benchmark_radix_pior.sh benchmark_smooth_melhor.sh benchmark_smooth_medio.sh benchmark_smooth_pior.sh
chmod +x benchmark_python_radix_5M.sh benchmark_python_smooth_5M.sh
```

**2. Execute os benchmarks:**

```bash
sudo ./benchmark_radix_melhor.sh
sudo ./benchmark_radix_medio.sh
sudo ./benchmark_radix_pior.sh
sudo ./benchmark_smooth_melhor.sh
sudo ./benchmark_smooth_medio.sh
sudo ./benchmark_smooth_pior.sh
sudo ./benchmark_python_radix_5M.sh
sudo ./benchmark_python_smooth_5M.sh
```

> **Nota:** `sudo` é necessário para a coleta de energia via `perf stat`.

---

### Java

**1. Habilite a coleta de métricas do perf:**

```bash
sudo sysctl kernel.perf_event_paranoid=-1
```

**2. Execute os benchmarks:**

```bash
bash rodar_radix_melhor.sh
bash rodar_radix_medio.sh
bash rodar_radix_pior.sh
bash rodar_smooth_melhor.sh
bash rodar_smooth_medio.sh
bash rodar_smooth_pior.sh
bash rodar_java_radix_5M.sh
bash rodar_java_smooth_5M.sh
```

---

## Saídas Geradas

Cada script gera arquivos CSV com as métricas coletadas, salvos na mesma pasta de execução:

**C** — dois CSVs por cenário:
- `metricas_<algoritmo>_<caso>.csv` — tempo e memória
- `energia_<algoritmo>_<caso>.csv` — consumo de energia

**Python** — um CSV por cenário:
- `metricas_python_<algoritmo>_<caso>.csv`

**Java** — um CSV por cenário:
- `metricas_<algoritmo>_<caso>.csv`

---

## Métricas Coletadas

| Métrica | Descrição |
|---|---|
| `tempo_sort_s` | Tempo interno de ordenação (medido pelo programa, em segundos) |
| `tempo_usuario_s` | Tempo de CPU em modo usuário |
| `tempo_sistema_s` | Tempo de CPU em modo kernel |
| `cpu_pct` | Percentual de CPU utilizado |
| `tempo_decorrido_s` | Tempo real decorrido (wall clock) |
| `memoria_max_kb` | Memória máxima residente (RSS) em KB |
| `falhas_pagina_menores` | Falhas de página menores (minor page faults) |
| `trocas_voluntarias` | Trocas de contexto voluntárias |
| `trocas_involuntarias` | Trocas de contexto involuntárias |
| `energia_pkg_j` | Energia consumida pelo pacote (CPU + cache) em Joules |
| `energia_core_j` | Energia consumida pelos núcleos em Joules |
