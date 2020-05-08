Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match api_path + '/channels_quepasa',                         to: 'channels_quepasa#index',    via: :get
  match api_path + '/channels_quepasa',                         to: 'channels_quepasa#add',      via: :post
  match api_path + '/channels_quepasa/:id',                     to: 'channels_quepasa#update',   via: :put
  match api_path + '/channels_quepasa_disable',                 to: 'channels_quepasa#disable',  via: :post
  match api_path + '/channels_quepasa_enable',                  to: 'channels_quepasa#enable',   via: :post
  match api_path + '/channels_quepasa',                         to: 'channels_quepasa#destroy',  via: :delete

end
