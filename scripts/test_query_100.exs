require Ash.Query

IO.puts("=== Testing with 100 products ===")
IO.puts("Testing default_image_url calculation performance...\n")

{time, {:ok, products}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.load([:default_image_url])
  |> Ash.Query.limit(100)
  |> Ash.read(authorize?: false)
end)

IO.puts("✓ Loaded #{length(products)} products in #{Float.round(time / 1000, 2)}ms\n")
IO.puts("First 3 results:")
for product <- Enum.take(products, 3) do
  IO.puts("  - #{product.name}: #{product.default_image_url}")
end
