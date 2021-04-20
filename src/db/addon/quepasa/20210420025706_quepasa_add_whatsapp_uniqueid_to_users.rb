class QuepasaAddWhatsappUniqueidToUsers < ActiveRecord::Migration[5.2]
  def change    
    #Incluindo campo para o ID do WhatsApp
    add_column :users, :whatsapp_uniqueid, :string
  end
end
