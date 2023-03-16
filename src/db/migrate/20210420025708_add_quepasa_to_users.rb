class AddQuepasaToUsers < ActiveRecord::Migration[6.0]
  def up    
    #Incluindo campo para o ID do QuePasa
    if !User.attribute_names.include? "quepasa"      
      add_column :users, :quepasa, :string
    end
  end

  def down
    if User.attribute_names.include? "quepasa"
      remove_column :users, :quepasa
    end
  end
end
