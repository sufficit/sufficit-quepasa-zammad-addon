class AddQuepasaToUsers < ActiveRecord::Migration[5.2]
  def self.up    
    #Incluindo campo para o ID do QuePasa
    add_column :users, :quepasa, :string
  end

  def self.down
    remove_column :users, :quepasa
  end
end
