require 'quepasa_api'
require 'rack/mime'

class Quepasa

  attr_accessor :client

=begin

check token and return bot attributes of token

  bot = Quepasa.check_token('token')

=end

  def self.check_token(api_url, token)
    @api = QuepasaApi.new(api_url, token)
    @api.fetch_self()
  end

=begin

create or update channel, store bot attributes and verify token

  channel = Quepasa.create_or_update_channel('token', params)

returns

  channel # instance of Channel

=end

  # token = Bot ID Token
  # url = Enderaço já com segurança embutida para retorno das requisições
  def self.set_webhook(token, url)
    if url.match?(%r{^http://}i)
      raise Exceptions::UnprocessableEntity, 'webhook url need to start with https://, you use http://'
    end

    ### 
    ##  Nesse ponto avisa ao QuePasa para retornar nessa URL
    ###  
    #begin
      @api.setWebHook(url)
    #rescue
     # raise Exceptions::UnprocessableEntity, "Unable to set webhook at QuePasa, seems to be a invalid url :: #{url}"
    #end
    true
  end

  def self.create_or_update_channel(api_url, token, params, channel = nil)

    # verify token
    bot = Quepasa.check_token(api_url, token)

    if !channel
      if Quepasa.bot_duplicate?(bot['id'])
        raise 'Bot already exists!'
      end
    end

    if params[:group_id].blank?
      raise 'Group needed!'
    end

    group = Group.find_by(id: params[:group_id])
    if !group
      raise 'Group invalid!'
    end

    # generate random callback token
    callback_token = if Rails.env.test?
      'callback_token'
    else
      SecureRandom.urlsafe_base64(10)
    end

    # set webhook / callback url for this bot @ Quepasa
    callback_url = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/api/v1/channels_quepasa_webhook/#{callback_token}?id=#{bot['id']}"
    Quepasa.set_webhook(token, callback_url)

    if !channel
      channel = Quepasa.bot_by_bot_id(bot['id'])
      if !channel
        channel = Channel.new
      end
    end

    channel.area = 'Quepasa::Account'
    channel.options = {
      adapter:   'quepasa',
      bot:       {
        id:     bot['id'],
        number: bot['number'],
      },
      callback_token: callback_token,
      callback_url:   callback_url,
      api_token: token,
      api_url:   api_url,
      welcome:   params[:welcome],
      goodbye:   params[:goodbye]
    }
    channel.group_id = group.id
    channel.active = true
    channel.save!
    channel
  end

=begin

check if bot already exists as channel

  success = Quepasa.bot_duplicate?(bot_id)

returns

  channel # instance of Channel

=end

  def self.bot_duplicate?(bot_id, channel_id = nil)
    Channel.where(area: 'Quepasa::Account').each do |channel|
      next if !channel.options
      next if !channel.options[:bot]
      next if !channel.options[:bot][:id]
      next if channel.options[:bot][:id] != bot_id
      next if channel.id.to_s == channel_id.to_s

      return true
    end
    false
  end

=begin

get channel by bot_id

  channel = Quepasa.bot_by_bot_id(bot_id)

returns

  true|false

=end

  def self.bot_by_bot_id(bot_id)
    Channel.where(area: 'Quepasa::Account').each do |channel|
      next if !channel.options
      next if !channel.options[:bot]
      next if !channel.options[:bot][:id]
      return channel if channel.options[:bot][:id].to_s == bot_id.to_s
    end
    nil
  end

=begin

  date = Quepasa.timestamp_to_date('1543414973285')

returns

  2018-11-28T14:22:53.285Z

=end

  def self.timestamp_to_date(timestamp_str)
    Time.at(timestamp_str.to_i).utc.to_datetime
  end

=begin

  client = Quepasa.new('token')

=end

  def initialize(api_url, token)
    @token = token
    @api_url = api_url
    @api = QuepasaApi.new(api_url, token)
  end

=begin

Fetch AND import messages for the bot

  client.fetch_messages(group_id, channel)

returns the latest last_seen_ts

=end
  def self.JsonMsgToObject(message_raw)
    # caso tenho sido eu mesmo quem enviou a msg, não precisa processar pois o artigo já foi criado
    return if ActiveModel::Type::Boolean.new.cast(message_raw['fromme'])            
          
    timestamp = message_raw['timestamp']
    created_at = Quepasa.timestamp_to_date(timestamp)
    message = {
      id:         message_raw['id'],      # vindo direto do whatsapp
      timestamp:  timestamp,              # double unix timestamp
      created_at: created_at,             # no formato de data

      # whatsapp controlador das msgs (bot)
      controller: {
        id: message_raw['controller']['id'],
        title: message_raw['controller']['title'],
        phone: message_raw['controller']['phone']
      },  

      # endereço garantido que deve receber uma resposta
      replyto: {
        id: message_raw['replyto']['id'],
        title: message_raw['replyto']['title'],
        phone: message_raw['replyto']['phone']
      }, 

      # se a msg foi postado em algum grupo ? quem postou !
      participant: {
        id: message_raw['participant']['id'],
        title: message_raw['participant']['title'],
        phone: message_raw['participant']['phone']
      },
      
      attachment: message_raw['attachment'],
      text:  message_raw['text']
    }

    return message
  end

  def fetch_messages(group_id, channel, last_seen_ts)

    older_import = 0
    older_import_max = 40
    new_last_seen_date = Quepasa.timestamp_to_date(last_seen_ts)
    new_last_seen_ts = last_seen_ts
    self_source_id = channel.options['bot']['number']
    count = 0
    @api.fetch(last_seen_ts).each do |message_raw|
      Rails.logger.debug { message_raw.inspect }

      message = Quepasa.JsonMsgToObject(message_raw)
      next if message.nil?
      count += 1
      created_at = message[:created_at] 
      timestamp = message[:timestamp] 
      
      #Rails.logger.debug{"channel.created_at#{channel.created_at} > message[:created_at]#{message[:created_at]} "}
      if channel.created_at > message[:created_at] || older_import >= older_import_max
        older_import += 1
        Rails.logger.debug { "quepasa msg too old: #{message[:id]}/#{message[:created_at]}" }
        next
      end

      next if Ticket::Article.find_by(message_id: message[:id])

      to_group(message, group_id, channel)
      if new_last_seen_date < created_at
        new_last_seen_date = created_at
        new_last_seen_ts = timestamp
      end
    end

    Rails.logger.info "quepasa processed #{count} messages, skipped #{older_import} old messages"
    new_last_seen_ts
  end

=begin

  client.send_message(chat_id, 'some message')

=end

  # Sufficit padrão para envio de msg
  def SendMessage(recipient, message, attachments, language = 'pt-br')
    return if Rails.env.test?

    locale = Locale.find_by(alias: language)
    if !locale
      locale = Locale.where('locale LIKE :prefix', prefix: "#{language}%").first
    end

    if locale
      message = Translation.translate(locale[:locale], message)
    end

    @api.sendMessage(recipient, message, attachments)
  end

  def SendMessageFromArticle(message)
    return if Rails.env.test?
    
    r = @api.sendMessage(message[:to], message[:text], message[:attachment])
    if r['result'].present? and r['result']['source'].present?
      r['result']['source'] = r['result']['source']
      r['result']['recipient'] = r['result']['recipient']
    end
    r
  end

  def to_wagroup(message)
    Rails.logger.debug { 'Create user/whatsapp group from group message...' }

    # Somente se for uma msg de grupo
    if message[:replyto][:id].end_with?("@g.us")   

      # definindo o que utilizar como endpoint de usuario
      endPointID = message[:replyto][:id]
      endPointTitle = message[:replyto][:title]
      endPointPhone = message[:replyto][:phone]

      # create or update users  
      auth = Authorization.find_by(uid: endPointID, provider: 'quepasa')
      user = if auth
              User.find(auth.user_id)
            else
              User.where(whatsapp: endPointID).order(:updated_at).first
            end
      unless user
        Rails.logger.info { "SUFF: Create user from group message... #{endPointID}" }
        user = User.create!(
          login:  endPointID,
          whatsapp: endPointID,
          active:    true,
          role_ids:  Role.signup_role_ids
        )
      end

      # atualizando nome de usuario se possível
      user.firstname = endPointTitle || user.firstname || "unknown"
      user.lastname = " (WHATSAPP GROUP)"
      user.save!

      # create or update authorization
      auth_data = {
        uid:      endPointID,
        username: endPointID,
        user_id:  user.id,
        provider: 'quepasa'
      }
      if auth
        auth.update!(auth_data)
      else
        Authorization.create(auth_data)
      end

    end

    user
  end

  def to_wauser(message)        
    Rails.logger.debug { "Create user from message ..." }
    Rails.logger.debug { message.inspect }

    # definindo o que utilizar como endpoint de usuario
    if !(message[:participant][:id].to_s.empty?)
      endPointID = message[:participant][:id]
      endPointTitle = message[:participant][:title]
      endPointPhone = message[:participant][:phone]
    else
      endPointID = message[:replyto][:id]
      endPointTitle = message[:replyto][:title]
      endPointPhone = message[:replyto][:phone]
    end

    # create or update users  
    auth = Authorization.find_by(uid: endPointID, provider: 'quepasa')
    user = if auth
             User.find(auth.user_id)
           else
             User.where(whatsapp: endPointID).order(:updated_at).first
           end
    unless user
      Rails.logger.info { "SUFF: Create user from message... #{endPointID}" }

      user = User.create!(
        phone: endPointPhone,
        login:  endPointID,
        whatsapp: endPointID,
        active:    true,
        role_ids:  Role.signup_role_ids
      )
    end
    
    # atualizando nome de usuario se possível
    user.firstname = endPointTitle || endPointPhone || user.firstname || "unknown"
    user.lastname = " (WHATSAPP)"
    user.save!

    # create or update authorization
    auth_data = {
      uid:      endPointID,
      username: endPointID,
      user_id:  user.id,
      provider: 'quepasa'
    }
    if auth
      auth.update!(auth_data)
    else
      Authorization.create(auth_data)
    end

    user
  end

  def to_ticket(message, user, group_id, channel)
    UserInfo.current_user_id = user.id

    Rails.logger.debug { 'Create ticket from message...' }
    Rails.logger.debug { message.inspect }
    Rails.logger.debug { user.inspect }
    Rails.logger.debug { group_id.inspect }

    # prepare title
    title = '-'
    unless message[:text].nil?
      title = message[:text]
    end
    if title.length > 60
      title = "#{title[0, 60]}..."
    end

    # find ticket or create one
    state_ids = Ticket::State.where(name: %w[closed merged removed]).pluck(:id)
    ticket = Ticket.where(customer_id: user.id).where.not(state_id: state_ids).order(:updated_at).first
    if ticket

      # check if title need to be updated
      if ticket.title == '-'
        ticket.title = title
      end
      new_state = Ticket::State.find_by(default_create: true)
      if ticket.state_id != new_state.id
        ticket.state = Ticket::State.find_by(default_follow_up: true)
      end
      ticket.save!
      return ticket
    end

    ticket = Ticket.new(
      group_id:    group_id,
      title:       title,
      state_id:    Ticket::State.find_by(default_create: true).id,
      priority_id: Ticket::Priority.find_by(default_create: true).id,
      customer_id: user.id,
      preferences: {
        # Usado para encontrar esse elemento ao responder um ticket
        # Usado somente se não encontrar pelo quepasa:bot
        channel_id: channel.id,
        
        # Salva informações do contato para ser usado ao responder qualquer artigo dentro deste ticket
        quepasa:  {
          bot:  channel.options[:bot][:id], # Qual Whatsapp utilizar para resposta
          replyto: message[:replyto][:id] # Destino no whatsapp
        }
      }
    )
    ticket.save!
    ticket
  end

  def to_article(message, user, ticket, channel)

    #Rails.logger.info { 'SUFF: Segue a msg para depuração' }
    #Rails.logger.info { "SUFF: #{message}" }

    Rails.logger.debug { 'Create article from message...' }
    Rails.logger.debug { message.inspect }
    Rails.logger.debug { user.inspect }
    Rails.logger.debug { ticket.inspect }

    UserInfo.current_user_id = user.id

    article = Ticket::Article.new(
      ticket_id:    ticket.id,
      type_id:      Ticket::Article::Type.find_by(name: 'quepasa personal-message').id,
      sender_id:    Ticket::Article::Sender.find_by(name: 'Customer').id,
      from:         "#{user[:firstname]}#{user[:lastname]}",
      to:           "#{channel[:options][:bot][:number]} - #{channel[:options][:bot][:name]}",
      message_id:   message[:id],
      internal:     false,
      preferences:  {
        quepasa: {
          timestamp:  message[:timestamp],
          message_id: message[:id],
          from:       message[:replyto][:id],
        }
      }
    )

    if !message[:text]
      raise Exceptions::UnprocessableEntity, 'invalid quepasa message'
    end    

    Rails.logger.info { 'SUFF: Processando msg de texto simples ... ' } 
    article.content_type = 'text/plain'      
    article.body = message[:text]
    article.save!

    # Processando msg com anexos    
    attachment = message[:attachment]
    if !attachment.nil? && !attachment.empty?
      Rails.logger.info { 'SUFF: Processando attachment ... ' } 
      Store.remove(
        object: 'Ticket::Article',
        o_id:   article.id,
      )

      # Tentando extrair apenas o conteudo MIME, sem as observações que vêm depois do ;
      singleMime = attachment['mime']
      if singleMime.match(";")
        singleMime = singleMime.match(";").pre_match
      end

      document = get_file(message[:replyto][:id], attachment, 'pt-br')       
      extension = Rack::Mime::MIME_TYPES.invert[singleMime]
      Store.add(
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        document,
        filename:    "#{message[:id]}#{extension}",
        preferences: {
          'Mime-Type' => singleMime,
        },
      )
    end
    
    return article    
  end

  def to_group(message, group_id, channel)
    # begin import
    Rails.logger.debug { 'quepasa import message' }

    # Retorna por aqui caso a msg já tenha sido processada em algum artigo
    return if Ticket::Article.find_by(message_id: message[:id])

    # define o ticket como nulo para comerçarmos o processo
    ticket = nil

    # cria um transação para garantir que todo o processo seja coerente no final
    # se não conhece database transactions, pare por aqui e vai estudar
    Transaction.execute(reset_user_id: true) do
      wagroup = to_wagroup(message)   # cria um usuario caso a msg venha de algum grupo
      wauser  = to_wauser(message)    # cria outro usuario caso seja uma msg direta ou para o participante do grupo      
      
      wagroup = wauser if wagroup.nil?
      ticket = to_ticket(message, wagroup, group_id, channel)
      to_article(message, wauser, ticket, channel)
    end

    ticket
  end

  def get_file(request, attachment, language)
    Rails.logger.info "SUFF: Geting file : #{attachment}"
    
    # quepasa bot files are limited up to 20MB
    if !validate_file_size(attachment['length'])
      message_text = 'WhatsApp file is to big. (Maximum 20mb)'
      messageSendText(request, "Sorry, we could not handle your message. #{message_text}", language)
      raise Exceptions::UnprocessableEntity, message_text
    end

    result = @api.getAttachment(attachment) 

    if !validate_download(result)
      message_text = 'Unable to get you file from bot.'
      messageSendText(request, "Sorry, we could not handle your message. #{message_text}", language)
      raise Exceptions::UnprocessableEntity, message_text
    end

    result
  end

  def validate_file_size(length)
    Rails.logger.info "SUFF: Validating file size : #{length}"
    return false if length >= 20.megabytes

    true
  end

  def validate_download(result)
    return false if result.nil?

    true
  end
  
end