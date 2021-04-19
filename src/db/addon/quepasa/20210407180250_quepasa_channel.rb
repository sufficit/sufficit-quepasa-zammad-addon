class QuepasaChannel < ActiveRecord::Migration[5.2]
  def self.up
    p = Permission.find_by(name: "admin.channel_quepasa")
    if p.nil?
      Permission.create_if_not_exists(
        name: "admin.channel_quepasa",
        note: "Manage %s",
        preferences: {
          translations: ["Channel - Quepasa"],
        },
      )
    end

    t = Ticket::Article::Type.find_by(name: "quepasa personal-message")
    if t.nil?
      Ticket::Article::Type.create(
        name: "quepasa personal-message",
        communication: true,
        updated_by_id: 1,
        created_by_id: 1,
      )
    end
  end

  def self.down
    a = Permission.find_by(name: "admin.channel_quepasa")
    if !a.nil?
      a.destroy
    end

    a = Ticket::Article::Type.find_by(name: "quepasa personal-message")
    if !a.nil?
      a.destroy
    end
  end
end
