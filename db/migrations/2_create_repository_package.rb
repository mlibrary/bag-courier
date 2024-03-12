Sequel.migration do
  change do
    create_table(:repository) do
      primary_key :id
      String :name, null: false, unique: true
    end

    create_table(:repository_package) do
      primary_key :id
      String :identifier, null: false, unique: true
      foreign_key :repository_id, :repository, on_delete: :cascade
      Time :updated_at, null: false
    end

    alter_table(:bag) do
      add_foreign_key :repository_package_id, :repository_package, foreign_key_constraint_name: :bag_repository_package_id_fkey
    end
  end
end
