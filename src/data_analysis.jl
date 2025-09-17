"""
Módulo de análise de dados para experimentos de otimização multiobjetivo.

Este módulo fornece funções utilitárias para carregar, filtrar e analisar dados
de experimentos salvos em arquivos JLD2.
"""

using JLD2
using MOProblems

# ========================================================================================
# FUNÇÕES DE LISTAGEM E DESCOBERTA DE DADOS
# ========================================================================================

"""
    list_jld2_files()

Lista todos os arquivos JLD2 disponíveis no diretório de simulações.

# Returns
- `Vector{String}`: Lista de nomes de arquivos JLD2 encontrados

# Note
Esta função procura arquivos no diretório `data/sims/` gerenciado pelo DrWatson.
"""
function list_jld2_files()
    sims_dir = datadir("sims")
    
    if !isdir(sims_dir)
        println("Diretório de simulações não encontrado: $sims_dir")
        return String[]
    end
    
    files = readdir(sims_dir)
    jld2_files = filter(file -> endswith(file, ".jld2"), files)
    
    if isempty(jld2_files)
        println("Nenhum arquivo JLD2 encontrado em: $sims_dir")
        return String[]
    end
    
    println("Arquivos JLD2 encontrados:")
    for (i, file) in enumerate(jld2_files)
        println("$i. $file")
    end
    
    return jld2_files
end

"""
    get_file_metadata(filepath::String)

Extrai metadados básicos de um arquivo JLD2 de experimentos.

# Arguments
- `filepath::String`: Caminho completo para o arquivo JLD2

# Returns
- `Dict{String, Any}`: Dicionário com metadados do arquivo contendo:
  - `solvers`: Lista de solvers disponíveis
  - `problems`: Lista de problemas disponíveis
  - `deltas`: Lista de deltas disponíveis
  - `run_ids`: Lista de run_ids disponíveis
  - `total_results`: Número total de resultados

# Note
Esta função abre o arquivo e navega pela estrutura hierárquica para extrair
informações básicas sobre o conteúdo. A estrutura é: solver/problem/delta/run_id
"""
function get_file_metadata(filepath::String)
    metadata = Dict{String, Any}()
    
    jldopen(filepath, "r") do file
        # Obter lista de solvers disponíveis
        available_solvers = collect(keys(file))
        metadata["solvers"] = available_solvers
        
        # Obter lista de problemas, deltas e run_ids
        problems = Set{String}()
        deltas = Set{Float64}()
        run_ids = Set{Int}()
        total_results = 0
        
        for solver in available_solvers
            solver_group = file[solver]
            for problem in keys(solver_group)
                push!(problems, problem)
                
                # Navegar pela estrutura: solver/problem/delta/run_id
                problem_group = solver_group[problem]
                for delta_key in keys(problem_group)
                    if startswith(delta_key, "delta_")
                        # Extrair valor do delta
                        delta_str = replace(delta_key, "delta_" => "")
                        delta_val = parse(Float64, replace(delta_str, "-" => "."))
                        push!(deltas, delta_val)
                        
                        # Obter run_ids deste delta
                        delta_group = problem_group[delta_key]
                        for run_key in keys(delta_group)
                            if startswith(run_key, "run_")
                                run_id = parse(Int, replace(run_key, "run_" => ""))
                                push!(run_ids, run_id)
                                total_results += 1
                            end
                        end
                    end
                end
            end
        end
        
        metadata["problems"] = sort(collect(problems))
        metadata["deltas"] = sort(collect(deltas))
        metadata["run_ids"] = sort(collect(run_ids))
        metadata["total_results"] = total_results
    end
    
    return metadata
end

"""
    list_solvers_for_problem(filepath::String, problem_name::Symbol)

Lista todos os solvers disponíveis para um problema específico em um arquivo JLD2.

# Arguments
- `filepath::String`: Caminho completo para o arquivo JLD2
- `problem_name::Symbol`: Nome do problema para verificar

# Returns
- `Vector{String}`: Lista de solvers que têm dados para o problema

# Note
Esta função navega pela estrutura do arquivo JLD2 e verifica cada solver.
A estrutura é: solver/problem/run_id
"""
function list_solvers_for_problem(filepath::String, problem_name::Symbol)
    solvers = String[]
    jldopen(filepath, "r") do file
        for solver_name in keys(file)
            if haskey(file[solver_name], string(problem_name))
                push!(solvers, solver_name)
            end
        end
    end
    return solvers
end

"""
    is_biobjective_problem(problem_name::Symbol)

Verifica se um problema é biobjetivo (tem exatamente 2 objetivos).

# Arguments
- `problem_name::Symbol`: Nome do problema a ser verificado

# Returns
- `Bool`: `true` se o problema é biobjetivo, `false` caso contrário

# Note
Esta função tenta instanciar o problema usando MOProblems e verifica o número
de objetivos. Retorna `false` se houver erro na instanciação.
"""
function is_biobjective_problem(problem_name::Symbol)
    try
        problem_constructor = getfield(MOProblems, problem_name)
        problem_instance = problem_constructor()
        return problem_instance.nobj == 2
    catch e
        println("Erro ao verificar problema $problem_name: $e")
        return false
    end
end

"""
    list_biobjective_problems(filepath::String)

Lista todos os problemas biobjetivos disponíveis em um arquivo JLD2.

# Arguments
- `filepath::String`: Caminho completo para o arquivo JLD2

# Returns
- `Vector{Symbol}`: Lista de problemas biobjetivos encontrados

# Note
Esta função navega pela estrutura do arquivo JLD2 e verifica cada problema
encontrado para determinar se é biobjetivo. A estrutura é: solver/problem/run_id
"""
function list_biobjective_problems(filepath::String)
    println("\nProcurando problemas biobjetivos no arquivo: $(basename(filepath))")
    
    biobjective_problems = Symbol[]
    
    jldopen(filepath, "r") do file
        available_solvers = collect(keys(file))
        
        for solver in available_solvers
            solver_group = file[solver]
            for problem_name in keys(solver_group)
                problem_sym = Symbol(problem_name)
                
                # Verificar se já não adicionamos este problema
                if !(problem_sym in biobjective_problems)
                    if is_biobjective_problem(problem_sym)
                        push!(biobjective_problems, problem_sym)
                    end
                end
            end
        end
    end
    
    if isempty(biobjective_problems)
        println("Nenhum problema biobjetivo encontrado no arquivo.")
    else
        println("Problemas biobjetivos encontrados: $biobjective_problems")
    end
    
    return biobjective_problems
end

"""
    filter_solvers(available_solvers::Vector{String}, target_solvers::Vector{String})

Filtra uma lista de solvers disponíveis para incluir apenas os solvers desejados.

# Arguments
- `available_solvers::Vector{String}`: Lista de solvers disponíveis no arquivo
- `target_solvers::Vector{String}`: Lista de solvers que se deseja analisar

# Returns
- `Vector{String}`: Lista filtrada de solvers para análise

# Note
Esta função é útil para garantir que apenas solvers específicos sejam analisados,
mesmo que o arquivo contenha dados de outros solvers.
"""
function filter_solvers(available_solvers::Vector{String}, target_solvers::Vector{String})
    solvers_to_analyze = filter(solver -> solver in target_solvers, available_solvers)
    
    if isempty(solvers_to_analyze)
        println("Nenhum dos solvers desejados encontrado no arquivo.")
        println("Solvers disponíveis: $available_solvers")
        println("Solvers desejados: $target_solvers")
    else
        println("Solvers para análise: $solvers_to_analyze")
    end
    
    return solvers_to_analyze
end

# ========================================================================================
# FUNÇÕES DE EXTRAÇÃO DE DADOS ESPECÍFICOS
# ========================================================================================

"""
    extract_performance_data(filepath::String, metric::String, target_solvers::Vector{String})

Extrai dados de performance de um arquivo JLD2 para criar uma matriz de performance.

# Arguments
- `filepath::String`: Caminho completo para o arquivo JLD2
- `metric::String`: Nome da métrica a ser extraída (e.g., "iter", "total_time")
- `target_solvers::Vector{String}`: Lista de solvers para incluir na análise

# Returns
- `Tuple{Matrix{Float64}, Vector{Tuple{String, Float64, Int}}}`: 
  - Matriz de performance (instâncias × solvers)
  - Lista de informações das instâncias (problema, delta, run_id)

# Note
Esta função cria uma matriz onde cada linha representa uma instância (problema, delta, run_id)
e cada coluna representa um solver. Valores NaN indicam execuções falhadas ou dados ausentes.
A estrutura do arquivo esperada é: `solver/problem/delta/run_id`.
"""
function extract_performance_data(filepath::String, metric::String, target_solvers::Vector{String})
    println("\nExtraindo dados de performance do arquivo: $(basename(filepath))")
    println("Métrica: $metric")

    jldopen(filepath, "r") do file
        available_solvers = collect(keys(file))
        solvers_to_analyze = filter_solvers(available_solvers, target_solvers)
        
        if isempty(solvers_to_analyze)
            println("Nenhum dos solvers desejados foi encontrado no arquivo.")
            return Matrix{Float64}(undef, 0, 0), []
        end

        # Descobrir todas as instâncias únicas (problema, delta, run_id)
        instance_info = Set{Tuple{String, Float64, Int}}()
        for solver in solvers_to_analyze
            if !haskey(file, solver); continue; end
            solver_group = file[solver]
            for problem in keys(solver_group)
                problem_group = solver_group[problem]
                for delta_key in keys(problem_group)
                    if !startswith(delta_key, "delta_"); continue; end
                    delta_str = replace(delta_key, "delta_" => "")
                    delta_val = parse(Float64, replace(delta_str, "-" => "."))
                    
                    delta_group = problem_group[delta_key]
                    for run_key in keys(delta_group)
                        if !startswith(run_key, "run_"); continue; end
                        run_id = parse(Int, replace(run_key, "run_" => ""))
                        push!(instance_info, (problem, delta_val, run_id))
                    end
                end
            end
        end

        sorted_instance_info = sort(collect(instance_info), by = x -> (x[1], x[2], x[3]))
        
        if isempty(sorted_instance_info)
            println("Nenhuma instância de resultado encontrada no arquivo.")
            return Matrix{Float64}(undef, 0, 0), []
        end

        println("Total de instâncias encontradas: $(length(sorted_instance_info))")

        # Criar matriz de performance (instâncias × solvers)
        perf_matrix = fill(NaN, length(sorted_instance_info), length(solvers_to_analyze))
        
        # Preencher a matriz
        for (instance_idx, (problem, delta, run_id)) in enumerate(sorted_instance_info)
            for (solver_idx, solver) in enumerate(solvers_to_analyze)
                delta_str = replace(string(delta), "." => "-")
                delta_key = "delta_$(delta_str)"
                run_key = "run_$(run_id)"
                
                path_exists = haskey(file, solver) &&
                              haskey(file[solver], problem) &&
                              haskey(file[solver][problem], delta_key) &&
                              haskey(file[solver][problem][delta_key], run_key)

                if path_exists
                    result = file[solver][problem][delta_key][run_key]
                    
                    if result.success && hasfield(typeof(result), Symbol(metric))
                        perf_matrix[instance_idx, solver_idx] = getfield(result, Symbol(metric))
                    end
                end
            end
        end
        
        return perf_matrix, sorted_instance_info
    end
end