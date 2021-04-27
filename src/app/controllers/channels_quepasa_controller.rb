class ChannelsQuepasaController < ApplicationController
  prepend_before_action -> { authentication_check(permission: 'admin.channel_quepasa') }, except: [:webhook]
  skip_before_action :verify_csrf_token, only: [:webhook]

  def index
    assets = {}
    channel_ids = []
    Channel.where(area: 'Quepasa::Account').order(:id).each do |channel|
      assets = channel.assets(assets)
      channel_ids.push channel.id
    end
    render json: {
      assets:      assets,
      channel_ids: channel_ids
    }
  end

  def add
    begin
      channel = Quepasa.create_or_update_channel(params[:api_url], params[:api_token], params)
    rescue => e
      raise Exceptions::UnprocessableEntity, e.message
    end
    render json: channel
  end

  def update
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Account')
    begin
      channel = Quepasa.create_or_update_channel(params[:api_url], params[:api_token], params, channel)
    rescue => e
      raise Exceptions::UnprocessableEntity, e.message
    end
    render json: channel
  end

  def enable
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Account')
    channel.active = true
    channel.save!
    render json: {}
  end

  def disable
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Account')
    channel.active = false
    channel.save!
    render json: {}
  end

  def destroy
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Account')
    channel.destroy
    render json: {}
  end

  # SUFFICIT webhook para receber as msgs de forma instantânea
  def webhook
    raise Exceptions::UnprocessableEntity, 'bot id is missing' if params['id'].blank?

    channel = Quepasa.bot_by_bot_id(params['id'])
    raise Exceptions::UnprocessableEntity, 'bot not found' if !channel

    if channel.options[:callback_token] != params['callback_token'] 
      raise Exceptions::UnprocessableEntity, 'invalid callback token'
    end

    if params['message'].nil?
      raise Exceptions::UnprocessableEntity, 'null or empty message'
    end

    quepasa = Quepasa.new(channel.options[:api_url], channel.options[:api_token])
    begin
      message = Quepasa.JsonMsgToObject(params['message'])
      quepasa.to_group(message, channel.group_id, channel)      
    rescue Exceptions::UnprocessableEntity => e
      Rails.logger.error e.message
    end

    render json: {}, status: :ok
  end  
end
