class TicketCreateTypesSettingQuepasa < ActiveRecord::Migration[6.0]
  def redo
    settingDefault = Setting.find_by name: 'ui_ticket_create_default_type'
    settingDefault.options = {
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
    }
    settingDefault.state = 'quepasa-out'
    settingDefault.save!

    settingAvailable = Setting.find_by name: 'ui_ticket_create_available_types'
    settingAvailable.options = {
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
    }
    settingAvailable.state = %w[quepasa-out phone-in phone-out email-out]
    settingAvailable.save!
  end

  def up
    
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    settingDefault = Setting.find_by name: 'ui_ticket_create_default_type'
    settingDefault.options = {
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
    }
    settingDefault.state = 'quepasa-out'
    settingDefault.save!

    settingAvailable = Setting.find_by name: 'ui_ticket_create_available_types'
    settingAvailable.options = {
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
    }
    settingAvailable.state = %w[quepasa-out phone-in phone-out email-out]
    settingAvailable.save!
    
  end
end