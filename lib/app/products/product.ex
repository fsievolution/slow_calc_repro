defmodule App.Products.Product do
  use Ash.Resource,
    domain: App.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "products"
    repo App.Repo
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:published, :unpublished, :draft]
      default :draft
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
    has_many :images, App.Products.Image do
      public? true
    end

    # has_one from_many? - Gets first image sorted by sort_order
    has_one :default_image, App.Products.Image do
      public? true
      from_many? true
      sort sort_order: :asc, id: :asc
    end
  end

  policies do
    bypass actor_attribute_equals(:is_admin, true) do
      authorize_if always()
    end

    # Allow anonymous users to read published products
    policy action_type(:read) do
      authorize_if expr(status == :published)
    end
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  calculations do
    calculate :default_image_url, :string do
      public? true
      description "Returns the default image URL with environment and crop parameters"

      calculation expr(default_image.full_url)
    end
  end
end
