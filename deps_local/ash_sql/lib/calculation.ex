# SPDX-FileCopyrightText: 2024 ash_sql contributors <https://github.com/ash-project/ash_sql/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshSql.Calculation do
  @moduledoc false

  require Ecto.Query

  @next_calculation_names Enum.reduce(0..999, %{}, fn i, acc ->
                            Map.put(acc, :"calculation_#{i}", :"calculation_#{i + 1}")
                          end)

  def add_calculations(query, calculations, resource, source_binding, select? \\ false)
  def add_calculations(query, [], _, _, _select?), do: {:ok, query}

  def add_calculations(query, calculations, resource, source_binding, select?) do
    start_time = System.monotonic_time(:microsecond)
    IO.puts("    [TRACE #{start_time}] >>> add_calculations START (#{length(calculations)} calculations)")

    {:ok, query} =
      AshSql.Join.join_all_relationships(
        query,
        %Ash.Filter{
          resource: resource,
          expression: Enum.map(calculations, &elem(&1, 1))
        },
        left_only?: true
      )

    after_join = System.monotonic_time(:microsecond)
    IO.puts("    [TRACE] [#{after_join - start_time}μs] join_all_relationships done")

    aggregates =
      calculations
      |> Enum.flat_map(fn {calculation, expression} ->
        expression
        |> Ash.Filter.used_aggregates([])
        |> Enum.map(&Map.put(&1, :context, calculation.context))
      end)
      |> Enum.uniq()

    {query, calculations} =
      Enum.reduce(
        calculations,
        {query, []},
        fn {calculation, expression}, {query, calculations} ->
          if is_atom(calculation.name) do
            {query, [{calculation, expression} | calculations]}
          else
            {query, name} = use_calculation_name(query, calculation.name)

            {query, [{%{calculation | name: name}, expression} | calculations]}
          end
        end
      )

    before_aggregates = System.monotonic_time(:microsecond)
    IO.puts("    [TRACE] [#{before_aggregates - start_time}μs] calling add_aggregates (#{length(aggregates)} aggregates)...")

    case AshSql.Aggregate.add_aggregates(
           query,
           aggregates,
           query.__ash_bindings__.resource,
           false,
           source_binding
         ) do
      {:ok, query} ->
        after_aggregates = System.monotonic_time(:microsecond)
        IO.puts("    [TRACE] [#{after_aggregates - start_time}μs] add_aggregates done (#{after_aggregates - before_aggregates}μs)")

        combinations? = query.__ash_bindings__.context[:data_layer][:combination_query?]

        if select? || combinations? do
          query =
            if query.select do
              query
            else
              Ecto.Query.select_merge(query, %{})
            end

          before_reduce = System.monotonic_time(:microsecond)
          IO.puts("    [TRACE] [#{before_reduce - start_time}μs] starting Enum.reduce over #{length(calculations)} calculations...")

          {dynamics, query} =
            Enum.reduce(calculations, {[], query}, fn {calculation, expression}, {list, query} ->
              expression =
                Ash.Actions.Read.add_calc_context_to_filter(
                  expression,
                  calculation.context.actor,
                  calculation.context.authorize?,
                  calculation.context.tenant,
                  calculation.context.tracer,
                  query.__ash_bindings__[:domain],
                  query.__ash_bindings__[:resource],
                  parent_stack: query.__ash_bindings__[:parent_resources] || []
                )

              expression =
                if calculation.context.type do
                  case expression do
                    %Ash.Query.Function.Type{arguments: [expression | _]} ->
                      expression

                    %Ash.Query.Call{name: :type, args: [expression | _]} ->
                      expression

                    _ ->
                      expression
                  end
                else
                  expression
                end

              expression =
                if is_nil(calculation.context.type) ||
                     map_type?(calculation.context.type, calculation.context.constraints || []) do
                  expression
                else
                  {:ok, expression} =
                    Ash.Query.Function.Type.new([
                      expression,
                      calculation.context.type,
                      calculation.context.constraints || []
                    ])

                  expression
                end

              before_dynamic_expr = System.monotonic_time(:microsecond)

              {expression, acc} =
                AshSql.Expr.dynamic_expr(
                  query,
                  expression,
                  Map.put(query.__ash_bindings__, :location, :select),
                  false,
                  {calculation.type, Map.get(calculation, :constraints, [])}
                )

              after_dynamic_expr = System.monotonic_time(:microsecond)
              IO.puts("    [TRACE]   - dynamic_expr for calc #{inspect(calculation.name)}: #{after_dynamic_expr - before_dynamic_expr}μs")

              load =
                if combinations? do
                  calculation.name
                else
                  calculation.load
                end

              {[{load, calculation.name, expression} | list],
               AshSql.Expr.merge_accumulator(query, acc)}
            end)

          after_reduce = System.monotonic_time(:microsecond)
          IO.puts("    [TRACE] [#{after_reduce - start_time}μs] Enum.reduce done (#{after_reduce - before_reduce}μs total)")

          result = {:ok, add_calculation_selects(query, dynamics)}

          end_time = System.monotonic_time(:microsecond)
          IO.puts("    [TRACE #{end_time}] <<< add_calculations END (total: #{end_time - start_time}μs)")

          result
        else
          {:ok, query}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  def next_calculation_name(i) do
    @next_calculation_names[i] ||
      raise Ash.Error.Framework.AssumptionFailed,
        message: """
        All 1000 static names for calculations have been used in a single query.
        Congratulations, this means that you have gone so wildly beyond our imagination
        of how much can fit into a single quer. Please file an issue and we will raise the limit.
        """
  end

  @doc false
  def map_type?({:array, type}, constraints) do
    map_type?(type, constraints[:items] || [])
  end

  def map_type?(type, constraints) when type in [:map, Ash.Type.Map] do
    !Keyword.has_key?(constraints, :fields)
  end

  def map_type?(type, constraints) do
    if Ash.Type.NewType.new_type?(type) do
      constraints = Ash.Type.NewType.constraints(type, constraints)
      type = Ash.Type.NewType.subtype_of(type)
      map_type?(type, constraints)
    else
      false
    end
  end

  defp use_calculation_name(query, aggregate_name) do
    {%{
       query
       | __ash_bindings__: %{
           query.__ash_bindings__
           | current_calculation_name:
               next_calculation_name(query.__ash_bindings__.current_calculation_name),
             calculation_names:
               Map.put(
                 query.__ash_bindings__.calculation_names,
                 aggregate_name,
                 query.__ash_bindings__.current_calculation_name
               )
         }
     }, query.__ash_bindings__.current_calculation_name}
  end

  defp add_calculation_selects(query, dynamics) do
    {in_calculations, in_body} =
      Enum.split_with(dynamics, fn {load, _name, _dynamic} -> is_nil(load) end)

    calcs =
      in_body
      |> Map.new(fn {load, _, dynamic} ->
        {load, dynamic}
      end)

    calcs =
      if Enum.empty?(in_calculations) do
        calcs
      else
        Map.put(
          calcs,
          :calculations,
          Map.new(in_calculations, fn {_, name, dynamic} ->
            {name, dynamic}
          end)
        )
      end

    Ecto.Query.select_merge(query, ^calcs)
  end
end
