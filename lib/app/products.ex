defmodule App.Products do
  use Ash.Domain

  resources do
    resource App.Products.Product
    resource App.Products.Image
    resource App.Products.ImageCrop
  end
end
