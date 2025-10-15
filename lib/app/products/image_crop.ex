defmodule App.Products.ImageCrop do
  use Ash.Resource,
    domain: App.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "image_crops"
    repo App.Repo

    references do
      reference :image do
        on_delete :delete
      end
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :x_start, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :y_start, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :x_end, :integer do
      allow_nil? false
      default 0
      public? true
    end

    attribute :y_end, :integer do
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
    belongs_to :image, App.Products.Image do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_crop_per_image, [:image_id], eager_check_with: App.Products
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    # Allow reading image crops when accessed through images
    policy action_type(:read) do
      authorize_if accessing_from(App.Products.Image, :image_crop)
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end
end
