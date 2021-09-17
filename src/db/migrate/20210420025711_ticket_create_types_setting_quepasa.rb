class QuepasaUserId < ActiveRecord::Migration[4.2]
  def up

    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    ObjectManager::Attribute.add(
      force:       true,
      object:      'User',
      name:        'quepasa',
      display:     'Quepasa ID',
      data_type:   'input',
      data_option: {
        type:       'text',
        maxlength:  150,
        null:       true,
        item_class: 'formGroup--halfSize',
      },
      editable:    true,
      active:      true,
      screens:     {
        edit:            {
          '-all-' => {
            null: true,
          },
        },
        view:            {
          '-all-' => {
            shown: true,
          },
        },
      },
      to_create:   false,
      to_migrate:  false,
      to_delete:   false,
      position:    200,
      updated_by_id: 1,
      created_by_id: 1,
    )

  end
end
