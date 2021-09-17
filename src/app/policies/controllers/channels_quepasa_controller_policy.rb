class Controllers::ChannelsQuepasaControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin.channel_quepasa')
end
