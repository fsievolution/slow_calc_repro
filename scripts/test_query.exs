require Ash.Query

IO.puts("Testing the has_one from_many? pattern with default_image_url calculation...")
IO.puts("")

# Warm up query (first run might be slower due to compilation/caching)
IO.puts("=== Warmup Query ===")
{warmup_time, _} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.load([:default_image_url])
  |> Ash.Query.limit(5)
  |> Ash.read(authorize?: false)
end)
IO.puts("Warmup time: #{warmup_time / 1000}ms")
IO.puts("")

# Test WITHOUT load for all sizes (baseline)
IO.puts("=== Queries WITHOUT load (baseline) ===")
{time_40_no_load, {:ok, products_no_load}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.limit(40)
  |> Ash.read(authorize?: false)
end)
IO.puts("  40 products: #{Float.round(time_40_no_load / 1000, 2)}ms")

{time_100_no_load, {:ok, _}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.limit(100)
  |> Ash.read(authorize?: false)
end)
IO.puts(" 100 products: #{Float.round(time_100_no_load / 1000, 2)}ms")

{time_500_no_load, {:ok, _}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.limit(500)
  |> Ash.read(authorize?: false)
end)
IO.puts(" 500 products: #{Float.round(time_500_no_load / 1000, 2)}ms")

{time_1000_no_load, {:ok, _}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.limit(1000)
  |> Ash.read(authorize?: false)
end)
IO.puts("1000 products: #{Float.round(time_1000_no_load / 1000, 2)}ms")
IO.puts("")

# Test with 40 products
IO.puts("=== Query with 40 products ===")
{time_40, {:ok, products}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.load([:default_image_url])
  |> Ash.Query.limit(40)
  |> Ash.read(authorize?: false)
end)
IO.puts("✓ Successfully loaded #{length(products)} products in #{time_40 / 1000}ms")
IO.puts("")

# Test with 100 products
IO.puts("=== Query with 100 products ===")
{time_100, {:ok, products_100}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.load([:default_image_url])
  |> Ash.Query.limit(100)
  |> Ash.read(authorize?: false)
end)
IO.puts("✓ Successfully loaded #{length(products_100)} products in #{time_100 / 1000}ms")
IO.puts("")

# Test with 500 products
IO.puts("=== Query with 500 products ===")
{time_500, {:ok, products_500}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.load([:default_image_url])
  |> Ash.Query.limit(500)
  |> Ash.read(authorize?: false)
end)
IO.puts("✓ Successfully loaded #{length(products_500)} products in #{time_500 / 1000}ms")
IO.puts("")

# Test with 1000 products
IO.puts("=== Query with 1000 products ===")
{time_1000, {:ok, products_1000}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.load([:default_image_url])
  |> Ash.Query.limit(1000)
  |> Ash.read(authorize?: false)
end)
IO.puts("✓ Successfully loaded #{length(products_1000)} products in #{time_1000 / 1000}ms")
IO.puts("")

# Show first 5 products
IO.puts("First 5 products with default_image_url:")
for product <- Enum.take(products, 5) do
  IO.puts("  - #{product.name}: #{product.default_image_url}")
end

IO.puts("")
IO.puts("=== Performance Summary ===")
IO.puts("WITHOUT load (baseline):")
IO.puts("  40 products:   #{Float.round(time_40_no_load / 1000, 2)}ms (#{Float.round(time_40_no_load / 1000 / 40, 2)}ms per product)")
IO.puts(" 100 products:   #{Float.round(time_100_no_load / 1000, 2)}ms (#{Float.round(time_100_no_load / 1000 / 100, 2)}ms per product)")
IO.puts(" 500 products:   #{Float.round(time_500_no_load / 1000, 2)}ms (#{Float.round(time_500_no_load / 1000 / 500, 2)}ms per product)")
IO.puts("1000 products:   #{Float.round(time_1000_no_load / 1000, 2)}ms (#{Float.round(time_1000_no_load / 1000 / 1000, 2)}ms per product)")
IO.puts("")
IO.puts("WITH load (default_image_url):")
IO.puts("  40 products:   #{Float.round(time_40 / 1000, 2)}ms (#{Float.round(time_40 / 1000 / 40, 2)}ms per product) - Overhead: +#{Float.round((time_40 - time_40_no_load) / 1000, 2)}ms")
IO.puts(" 100 products:   #{Float.round(time_100 / 1000, 2)}ms (#{Float.round(time_100 / 1000 / 100, 2)}ms per product) - Overhead: +#{Float.round((time_100 - time_100_no_load) / 1000, 2)}ms")
IO.puts(" 500 products:   #{Float.round(time_500 / 1000, 2)}ms (#{Float.round(time_500 / 1000 / 500, 2)}ms per product) - Overhead: +#{Float.round((time_500 - time_500_no_load) / 1000, 2)}ms")
IO.puts("1000 products:   #{Float.round(time_1000 / 1000, 2)}ms (#{Float.round(time_1000 / 1000 / 1000, 2)}ms per product) - Overhead: +#{Float.round((time_1000 - time_1000_no_load) / 1000, 2)}ms")
IO.puts("")
IO.puts("✓ Implementation complete!")
IO.puts("")
IO.puts("Pattern demonstrated:")
IO.puts("  1. has_one from_many? - selects first image by sort_order")
IO.puts("  2. Chained calculation - default_image_url -> default_image.full_url")
IO.puts("  3. Nested relationship - Image.full_url references ImageCrop")
IO.puts("  4. Conditional URL building - adds crop params if crop exists")
