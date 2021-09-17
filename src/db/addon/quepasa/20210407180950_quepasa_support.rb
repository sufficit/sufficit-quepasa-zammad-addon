class QuepasaSupport < ActiveRecord::Migration[5.2]
  def self.up

    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    Permission.create_if_not_exists(
      name:        'admin.channel_quepasa',
      note:        'Manage %s',
      preferences: {
        translations: ['Channel - Quepasa']
      },
    )

    Ticket::Article::Type.create_if_not_exists(
      name:          'quepasa personal-message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )

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
