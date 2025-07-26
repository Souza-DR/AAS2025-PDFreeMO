# AAS2025-DFreeMO: Repositório de Experimentos Numéricos

Este repositório contém a infraestrutura para executar, armazenar e analisar os experimentos numéricos associados ao artigo científico (AAS2025, a ser submetido). O objetivo é fornecer um ambiente de teste robusto, reprodutível e extensível para avaliar o desempenho de solvers de otimização multiobjetivo.

---

## 🏛️ Estrutura do Projeto

-   **/src**: Contém o código-fonte principal do módulo `AAS2025DFreeMO.jl`, que encapsula toda a lógica de experimentação.
-   **/scripts**: Contém os scripts executáveis que definem e disparam os benchmarks.
-   **/data**: Diretório gerenciado pelo `DrWatson.jl` para armazenar os resultados dos experimentos (e.g., em `data/sims`).
-   **/test**: Futuro local para testes unitários da infraestrutura.

---

## 📦 Módulo `AAS2025DFreeMO.jl`

O coração deste repositório é o módulo `AAS2025DFreeMO`, que exporta um conjunto de `structs` e funções para facilitar a criação e execução de benchmarks.

### Componentes Exportados

#### Tipos de Configuração e Resultado

-   `ExperimentConfig`: Uma `struct` que armazena todos os parâmetros de **entrada** para uma única instância de um experimento (problema, solver, ponto inicial, etc.), **incluindo** as matrizes `A` pré-computadas que definem a parte não diferenciável `H`. Isso garante total reprodutibilidade dentro do par (problema, δ).
-   `ExperimentResult`: Uma `struct` que armazena os dados de **saída** de uma única execução, como número de iterações, tempo, e o valor final da função objetivo.
-   `SolverConfiguration`, `CommonSolverOptions`, `SolverSpecificOptions`: `structs` aninhadas para definir de forma clara e padronizada as configurações dos solvers.

#### Funções Principais

-   `generate_experiment_configs(...)`: Gera um vetor de objetos `ExperimentConfig` com base em listas de problemas, solvers, deltas e número de execuções.
-   `run_experiment(...)`: Recebe um vetor de `ExperimentConfig` e executa todos os experimentos, retornando um vetor de `ExperimentResult`.
-   `save_final_results(...)`: Salva um vetor de `ExperimentResult` em um arquivo JLD2, utilizando uma estrutura hierárquica (`solver/problema/run_id`).
-   `get_solver_options(...)`: Converte uma `SolverConfiguration` genérica para a `struct` de opções específica exigida pelo `MOSolvers.jl`.
-   `datas(...)`: Função utilitária para gerar as matrizes de dados usadas nos problemas robustos.

---

## 🚀 Fluxo de Trabalho Típico

O processo de execução de um benchmark é feito em três etapas principais, geralmente dentro de um script na pasta `/scripts`.

### 1. Definir os Parâmetros do Benchmark

Primeiro, defina quais problemas, solvers e configurações você deseja testar.

```julia
using DrWatson
@quickactivate "AAS2025-DFreeMO"
using .AAS2025DFreeMO
using Random

# --- 1. CONFIGURAÇÕES DOS SOLVERS ---
const COMMON_OPTIONS = CommonSolverOptions(max_iter=100, opt_tol=1e-6)
const SPECIFIC_OPTIONS = Dict(
    :DFreeMO => SolverSpecificOptions(max_subproblem_iter=50),
    :ProxGrad => SolverSpecificOptions(mu=1.0)
)

# --- 2. PARÂMETROS DO BENCHMARK ---
const SOLVERS = [:DFreeMO, :ProxGrad]
const PROBLEMS = [:ZDT1, :ZDT2]
const NRUN = 50
const DELTAS = [0.0, 0.05]
```

### 2. Gerar e Executar os Experimentos

Use as funções do módulo para gerar as configurações e executá-las.

```julia
function main()
    Random.seed!(42)
    
    # --- 3. GERAR CONFIGURAÇÕES ---
    configs = generate_experiment_configs(
        PROBLEMS, 
        SOLVERS, 
        NRUN, 
        DELTAS, 
        COMMON_OPTIONS;
        solver_specific_options = SPECIFIC_OPTIONS
    )
    println("Total de experimentos a serem executados: $(length(configs))")

    # --- 4. EXECUTAR OS EXPERIMENTOS ---
    results = run_experiment(configs)
    
    # --- 5. SALVAR OS RESULTADOS ---
    save_final_results(results, "zdt_benchmark")
    
    println("\nBenchmark concluído! Resultados salvos em: $(datadir("sims"))")
end

main()
```

### 3. Análise dos Resultados

Após a execução, os resultados são salvos no formato JLD2 em `data/sims/`. Você pode então carregar esses dados para análise posterior.

```julia
using JLD2

# Carregar um resultado específico
filepath = datadir("sims", "zdt_benchmark.jld2")
loaded_data = jldopen(filepath, "r") do file
    # Acessar o resultado do solver DFreeMO, no problema ZDT1, da primeira execução
    file["DFreeMO/ZDT1/run_1"]
end

println("Resultado carregado: ", loaded_data)
```

Essa estrutura garante um fluxo de trabalho claro, reprodutível e fácil de estender para novos solvers e problemas. 