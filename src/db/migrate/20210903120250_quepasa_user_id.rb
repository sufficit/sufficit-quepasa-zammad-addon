class TicketCreateTypesSettingQuepasa < ActiveRecord::Migration[5.1]
  def up
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    Setting.set('ui_ticket_create_default_type', {
      title:       'Default type for a new ticket',
      name:        'ui_ticket_create_default_type',
      area:        'UI::TicketCreate',
      description: 'Select default ticket type',
      options:     {
        form: [
          {
            display:  '',
            null:     false,
            multiple: false,
            name:     'ui_ticket_create_default_type',
            tag:      'select',
            options:  {
              'phone-in'      => '1. Phone inbound',
              'phone-out'     => '2. Phone outbound',
              'email-out'     => '3. Email outbound',
              'quepasa-out'   => '4. QuePasa outbound',
            },
          },
        ],
      },
      state:       'quepasa-out',
      preferences: {
        permission: ['admin.ui']
      },
      frontend:    true
    }
  )

    Setting.set('ui_ticket_create_available_types', {
      title:       'Available types for a new ticket',
      name:        'ui_ticket_create_available_types',
      area:        'UI::TicketCreate',
      description: 'Set available ticket types',
      options:     {
        form: [
          {
            display:  '',
            null:     false,
            multiple: true,
            name:     'ui_ticket_create_available_types',
            tag:      'select',
            options:  {
              'phone-in'      => '1. Phone inbound',
              'phone-out'     => '2. Phone outbound',
              'email-out'     => '3. Email outbound',
              'quepasa-out'   => '4. QuePasa outbound',
            },
          },
        ],
      },
      state:       %w[quepasa-out phone-in phone-out email-out],
      preferences: {
        permission: ['admin.ui']
      },
      frontend:    true
    })
  end
end