class QuepasaPermissions < ActiveRecord::Migration[6.0]
  def up

    Permission.create_if_not_exists(
      name:        'admin.channel_quepasa',
      note:        __('Manage %s'),
      preferences: {
        translations: [__('Channel - Quepasa')]
      },
    )

  end 

  def down
    a = Permission.find_by(name: "admin.channel_quepasa")
    if !a.nil?
      a.destroy
    end
  end
end
