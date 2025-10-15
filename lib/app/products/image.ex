defmodule App.Products.Image do
  use Ash.Resource,
    domain: App.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "images"
    repo App.Repo
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :path, :string do
      allow_nil? false
      public? true
    end

    attribute :stored_env, :string do
      allow_nil? false
      default "prod"
      public? true
    end

    attribute :sort_order, :integer do
      allow_nil? false
      default 0
      public? true
    end

    create_timestamp :inserted_at do
      public? true
    end

    update_timestamp :updated_at do
      public? true
    end
  end

  relationships do
    belongs_to :product, App.Products.Product do
      allow_nil? false
      public? true
    end

    has_one :image_crop, App.Products.ImageCrop do
      public? true
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    # Allow reading images when accessed through products
    policy action_type(:read) do
      authorize_if accessing_from(App.Products.Product, :images)
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  calculations do
    calculate :full_url, :string do
      public? true

      calculation expr(
                    cond do
                      # Production with prod image: path only, or path + crops
                      lazy({Application, :get_env, [:app, :running_env]}) == "prod" and
                          stored_env == "prod" ->
                        if is_nil(image_crop) do
                          path
                        else
                          path <>
                            "?crop.x_start=" <>
                            fragment("?::text", image_crop.x_start) <>
                            "&crop.y_start=" <>
                            fragment("?::text", image_crop.y_start) <>
                            "&crop.x_end=" <>
                            fragment("?::text", image_crop.x_end) <>
                            "&crop.y_end=" <> fragment("?::text", image_crop.y_end)
                        end

                      # Any other case: include env param, optionally + crops
                      true ->
                        if is_nil(image_crop) do
                          path <> "?env=" <> stored_env
                        else
                          path <>
                            "?env=" <>
                            stored_env <>
                            "&crop.x_start=" <>
                            fragment("?::text", image_crop.x_start) <>
                            "&crop.y_start=" <>
                            fragment("?::text", image_crop.y_start) <>
                            "&crop.x_end=" <>
                            fragment("?::text", image_crop.x_end) <>
                            "&crop.y_end=" <>
                            fragment("?::text", image_crop.y_end)
                        end
                    end
                  )
    end
  end
end
