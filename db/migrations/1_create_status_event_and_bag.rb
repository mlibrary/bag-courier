Sequel.migration do
  change do
    create_table(:bag) do
      primary_key :id
      String :identifier, null: false, unique: true
      Integer :group_part, null: false
    end

    create_table(:status) do
      primary_key :id
      String :name, null: false, unique: true
    end

    create_table(:status_event) do
      primary_key :id
      foreign_key :status_id, :status, on_delete: :cascade
      foreign_key :bag_id, :bag, on_delete: :cascade
      Time :timestamp, null: false
      String :note, text: true
    end
  end
end
