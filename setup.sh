#!/bin/bash
set -e

echo "=== Database Reset and Setup ==="
echo ""

echo "Step 1: Getting dependencies..."
mix deps.get

echo ""
echo "Step 2: Resetting database..."
mix ecto.reset

echo ""
echo "Step 3: Inserting sample data (2000 products)..."
psql -U postgres -d slowrepro_dev -f priv/insert_sample_data.sql | grep -E "(NOTICE|product_count|INSERT)"

echo ""
echo "Step 4: Running baseline performance test..."
mix run scripts/test_query.exs 2>&1 | grep -v "^\[debug\]"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To run the flamegraph trace, use:"
echo "  mix run scripts/trace.exs"
echo ""
echo "This will generate a .bggg file that you can visualize with:"
echo "  https://www.speedscope.app/"
