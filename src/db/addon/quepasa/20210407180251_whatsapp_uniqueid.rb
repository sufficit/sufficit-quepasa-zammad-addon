class QuepasaChannel < ActiveRecord::Migration[5.2]
  def self.up
    #Incluindo campo para o ID do WhatsApp
    change_table :users do |t|
      add_column :whatsapp_uniqueid, :string
    end
  end

  def self.down
    #Removendo campo para o ID do WhatsApp
    change_table :users do |t|
      remove_column :whatsapp_uniqueid, :string
    end
  end
end
