-- Insert 2000 products
DO $$
DECLARE
  product_id uuid;
  image_id uuid;
  i integer;
BEGIN
  FOR i IN 1..2000 LOOP
    -- Insert product
    INSERT INTO products (name, status)
    VALUES ('Product ' || i, 'published')
    RETURNING id INTO product_id;

    -- Insert image for this product
    INSERT INTO images (product_id, path, stored_env, sort_order)
    VALUES (
      product_id,
      '/images/product-' || i || '.jpg',
      'dev',
      (i % 5)  -- Varying sort orders from 0-4
    )
    RETURNING id INTO image_id;

    -- Insert image crop for this image
    INSERT INTO image_crops (image_id, x_start, y_start, x_end, y_end)
    VALUES (
      image_id,
      (i % 50) * 10,           -- x_start: 0, 10, 20, ... 490
      (i % 30) * 10,           -- y_start: 0, 10, 20, ... 290
      (i % 50) * 10 + 300,     -- x_end: 300, 310, 320, ... 790
      (i % 30) * 10 + 300      -- y_end: 300, 310, 320, ... 590
    );

    -- Print progress every 100 products
    IF i % 100 = 0 THEN
      RAISE NOTICE 'Inserted % products', i;
    END IF;
  END LOOP;
END $$;

-- Verify the data
SELECT
  (SELECT COUNT(*) FROM products) as product_count,
  (SELECT COUNT(*) FROM images) as image_count,
  (SELECT COUNT(*) FROM image_crops) as crop_count;
