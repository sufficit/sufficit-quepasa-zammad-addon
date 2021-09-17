class AddQuepasaToUsers < ActiveRecord::Migration[5.2]
  def change    
    #Incluindo campo para o ID do QuePasa
    add_column :users, :quepasa, :string
  end
end
