class QuepasaArticleType < ActiveRecord::Migration[6.0]
  def up

    Ticket::Article::Type.create_if_not_exists(
      name:          'quepasa personal-message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )

  end 

  def down
    a = Ticket::Article::Type.find_by(name: "quepasa personal-message")
    if !a.nil?
      a.destroy
    end
  end
end
