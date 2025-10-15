require Ash.Query

IO.puts("=== Simple single query test ===")
IO.puts("Testing default_image_url calculation performance...\n")

{time, {:ok, products}} = :timer.tc(fn ->
  App.Products.Product
  |> Ash.Query.filter(status == :published)
  |> Ash.Query.load([:default_image_url])
  |> Ash.Query.limit(10)
  |> Ash.read(authorize?: false)
end)

IO.puts("✓ Loaded #{length(products)} products in #{Float.round(time / 1000, 2)}ms\n")

IO.puts("Results:")
for product <- products do
  IO.puts("  - #{product.name}: #{product.default_image_url}")
end
