# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

class ChannelsQuepasaController < ApplicationController
  prepend_before_action -> { authentication_check && authorize! }, except: [:webhook]
  skip_before_action :verify_csrf_token, only: [:webhook]

  def index
    assets = {}
    channel_ids = []
    Channel.where(area: 'Quepasa::Bot').order(:id).each do |channel|
      assets = channel.assets(assets)
      channel_ids.push channel.id
    end
    render json: {
      assets:      assets,
      channel_ids: channel_ids
    }
  end

  def add
    quepasa = Quepasa.new(params)
    begin
      channel = quepasa.CreateOrUpdateChannel(params)
    rescue => e
      raise Exceptions::UnprocessableEntity, e.message
    end
    render json: channel
  end

  def update
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Bot')
    quepasa = Quepasa.new(channel.options)
    begin
      channel = quepasa.CreateOrUpdateChannel(params, channel)
    rescue => e
      raise Exceptions::UnprocessableEntity, e.message
    end
    render json: channel
  end

  def enable
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Bot')
    channel.active = true
    channel.save!
    render json: {}
  end

  def disable
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Bot')
    channel.active = false
    channel.save!
    render json: {}
  end

  def destroy
    channel = Channel.find_by(id: params[:id], area: 'Quepasa::Bot')
    channel.destroy
    render json: {}
  end

  def webhook
    Rails.logger.info { '[QUEPASA] from webhook' }
    Rails.logger.info { params.inspect }
    raise Exceptions::UnprocessableEntity, 'bot id is missing' if params['bid'].blank?

    channel = Quepasa.GetChannelFromId(params['bid'])
    raise Exceptions::UnprocessableEntity, 'bot not found' if !channel
    Rails.logger.info { channel.inspect }

    if channel.options[:callback_token] != params['callback_token']
      raise Exceptions::UnprocessableEntity, 'invalid callback token'
    end

    quepasa = Quepasa.new(channel.options)
    begin
      quepasa.to_group(params, channel.group_id, channel)
    rescue Exceptions::UnprocessableEntity => e
      Rails.logger.error e.message
    end

    render json: {}, status: :ok
  end

end
