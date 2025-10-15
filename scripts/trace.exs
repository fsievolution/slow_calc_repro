defmodule ProductQueryTracer do
  require Ash.Query
  require Logger

  def measure(label, fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000

    Logger.info("#{label}: #{Float.round(duration_ms, 2)}ms")
    IO.puts("#{label}: #{Float.round(duration_ms, 2)}ms")
    result
  end

  def do_the_thing do
    App.Products.Product
    |> Ash.Query.filter(status == :published)
    |> Ash.Query.load([:default_image_url])
    |> Ash.Query.limit(40)
    |> Ash.read(authorize?: false)
  end

  def run_with_measurements do
    IO.puts("=== Running query 4 times with measurements ===\n")

    results = for i <- 1..4 do
      measure("Query run #{i}", fn -> do_the_thing() end)
    end

    case List.last(results) do
      {:ok, products} ->
        Logger.info("Successfully loaded #{length(products)} products")
        IO.puts("\n✓ Successfully loaded #{length(products)} products")
      {:error, error} ->
        Logger.error("Query failed: #{inspect(error)}")
        IO.puts("\n✗ Error: #{inspect(error)}")
    end

    results
  end

  def run_with_trace do
    IO.puts("\n=== Starting eflambe trace ===\n")

    # Generate unique filename with timestamp
    timestamp = System.system_time(:second)
    output_file = "#{timestamp}-eflambe-output"

    Logger.info("Starting trace, output will be written to: #{output_file}.bggg")
    IO.puts("Trace output file: #{output_file}.bggg")

    # Start tracing - eflambe.apply/2 with function and args tuple
    result = :eflambe.apply(
      {fn ->
        Logger.info("Executing traced query...")
        result = do_the_thing()
        Logger.info("Traced query completed")
        result
      end, []},
      [
        return: :filename,
        output_format: :brendan_gregg,
        output_directory: "."
      ]
    )

    IO.puts("✓ Trace completed")
    IO.puts("Result: #{inspect(result)}")
    Logger.info("Trace completed: #{inspect(result)}")
  end
end

# Run measurements first
ProductQueryTracer.run_with_measurements()

# Then run with trace
ProductQueryTracer.run_with_trace()
