Sequel.migration do
  change do
    create_table(:system) do
      primary_key :id
      String :name, null: false, unique: true
    end

    create_table(:digital_object) do
      primary_key :id
      String :identifier, null: false, unique: true
      foreign_key :system_id, :system, on_delete: :cascade
      Time :updated_at, null: false
    end

    alter_table(:bag) do
      add_foreign_key :digital_object_id, :digital_object, foreign_key_constraint_name: :bag_digital_object_id_fkey
    end
  end
end
