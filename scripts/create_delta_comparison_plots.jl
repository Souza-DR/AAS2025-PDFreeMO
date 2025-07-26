using DrWatson
@quickactivate "AAS2025-DFreeMO"
using JLD2
using Plots
using MOProblems

# Incluir o módulo para ter acesso às funções de análise
include(srcdir("AAS2025DFreeMO.jl"))
using .AAS2025DFreeMO

# ========================================================================================
# FUNÇÕES AUXILIARES
# ========================================================================================

# Função list_jld2_files agora importada do módulo AAS2025DFreeMO

# Função extract_problem_data agora importada do módulo AAS2025DFreeMO

# Funções is_biobjective_problem e list_biobjective_problems agora importadas do módulo AAS2025DFreeMO

"""
Cria e salva o plot comparativo de deltas para um problema e um solver específicos.
"""
function create_and_save_delta_plot(filepath::String, problem_name::Symbol, solver_name::String)
    println("\n=== Criando plot para: problema=$problem_name, solver=$solver_name ===")
    
    # Extrair dados do arquivo usando a função do módulo
    deltas, final_points_dict = AAS2025DFreeMO.extract_problem_data(filepath, problem_name, solver_name)
    
    # Verificar se temos dados
    if isempty(deltas)
        println("Nenhum delta encontrado para o problema $problem_name com o solver $solver_name")
        return nothing
    end
    
    # Caso 1: Apenas um delta - criar plot simples
    if length(deltas) == 1
        delta = deltas[1]
        final_points = final_points_dict[delta]
        
        println("Apenas um delta encontrado ($delta). Criando plot simples...")
        output_file = AAS2025DFreeMO.save_single_delta_plot(problem_name, solver_name, delta, final_points, filepath)
        return output_file
    end
    
    # Caso 2: Múltiplos deltas - criar plot comparativo
    println("Múltiplos deltas encontrados. Criando plot comparativo...")
    
    # Verificar se temos pontos para cada delta
    for delta in deltas
        if isempty(final_points_dict[delta])
            println("Aviso: Nenhum ponto encontrado para delta = $delta")
        end
    end
    
    # Criar o plot comparativo
    p = AAS2025DFreeMO.create_delta_comparison_plot(problem_name, solver_name, deltas, final_points_dict)
    
    # Salvar o plot
    output_dir = datadir("plots")
    mkpath(output_dir)
    
    filename_base = replace(basename(filepath), ".jld2" => "")
    output_file = joinpath(output_dir, "delta_comparison_$(problem_name)_$(solver_name)_$(filename_base).png")
    savefig(p, output_file)
    println("Plot comparativo salvo em: $output_file")
    
    return p
end

# ========================================================================================
# FUNÇÃO PRINCIPAL
# ========================================================================================

function main()
    println("=== Gerador de Plots Comparativos de Deltas ===")
    println("Usando dados JLD2 do repositório AAS2025-DFreeMO")
    
    # Listar arquivos disponíveis
    jld2_files = list_jld2_files()
    
    if isempty(jld2_files)
        return
    end
    
    # Escolher arquivo
    if length(jld2_files) == 1
        selected_file = jld2_files[1]
        println("\nUsando arquivo: $selected_file")
    else
        println("\nEscolha um arquivo para analisar:")
        for (i, file) in enumerate(jld2_files)
            println("$i. $file")
        end
        
        print("Digite o número do arquivo: ")
        choice = parse(Int, readline())
        
        if 1 <= choice <= length(jld2_files)
            selected_file = jld2_files[choice]
        else
            println("Escolha inválida.")
            return
        end
    end
    
    # Obter caminho completo do arquivo
    filepath = datadir("sims", selected_file)
    
    # Listar problemas biobjetivos disponíveis
    biobjective_problems = AAS2025DFreeMO.list_biobjective_problems(filepath)
    
    if isempty(biobjective_problems)
        println("Nenhum problema biobjetivo encontrado para análise.")
        return
    end
    
    # Escolher problema
    if length(biobjective_problems) == 1
        selected_problem = biobjective_problems[1]
        println("\nUsando problema: $selected_problem")
    else
        println("\nEscolha um problema para analisar:")
        for (i, problem) in enumerate(biobjective_problems)
            println("$i. $problem")
        end
        
        print("Digite o número do problema: ")
        problem_choice = parse(Int, readline())
        
        if 1 <= problem_choice <= length(biobjective_problems)
            selected_problem = biobjective_problems[problem_choice]
        else
            println("Escolha inválida.")
            return
        end
    end
    
    # Listar solvers para o problema selecionado
    available_solvers = AAS2025DFreeMO.list_solvers_for_problem(filepath, selected_problem)
    
    if isempty(available_solvers)
        println("Nenhum solver encontrado para o problema '$selected_problem'.")
        return
    end
    
    println("\nSolvers encontrados para '$selected_problem': $(join(available_solvers, ", "))")
    
    # Criar um plot para cada solver
    for solver in available_solvers
        create_and_save_delta_plot(filepath, selected_problem, solver)
    end
    
    println("\nAnálise concluída!")
end

# Executar se o script for chamado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 