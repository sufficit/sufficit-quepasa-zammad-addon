# Copyright (C) 2012-2015 Zammad Foundation, http://zammad-foundation.org/

class Quepasa

  attr_accessor :client

=begin

check token and return bot attributes of token

  bot = Quepasa.check_token('token')

=end

  def self.check_token(token)
    api = QuepasaApi.new(token)
    begin
      bot = api.getMe()
    rescue
      raise Exceptions::UnprocessableEntity, 'invalid api token'
    end
    bot
  end

=begin

set webhook for bot

  success = Quepasa.set_webhook('token', callback_url)

returns

  true|false

=end

  def self.set_webhook(token, callback_url)
    ### Removed for testing 
    ### Removed for testing
    ### Removed for testing
    
    #if callback_url.match?(%r{^http://}i)
    #  raise Exceptions::UnprocessableEntity, 'webhook url need to start with https://, you use http://'
    #end

    api = QuepasaApi.new(token)
    begin
      api.setWebhook(callback_url)
    rescue
      raise Exceptions::UnprocessableEntity, 'Unable to set webhook at Quepasa, seems to be a invalid url.'
    end
    true
  end

=begin

create or update channel, store bot attributes and verify token

  channel = Quepasa.create_or_update_channel('token', params)

returns

  channel # instance of Channel

=end

  def self.create_or_update_channel(token, params, channel = nil)

    # verify token
    bot = Quepasa.check_token(token)

    if !channel && Quepasa.bot_duplicate?(bot['id'])
      raise Exceptions::UnprocessableEntity, 'Bot already exists!'
    end

    if params[:group_id].blank?
      raise Exceptions::UnprocessableEntity, 'Group needed!'
    end

    group = Group.find_by(id: params[:group_id])
    if !group
      raise Exceptions::UnprocessableEntity, 'Group invalid!'
    end

    # generate random callback token
    callback_token = if Rails.env.test?
                       'callback_token'
                     else
                       SecureRandom.urlsafe_base64(10)
                     end

    # set webhook / callback url for this bot @ quepasa
    callback_url = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/api/v1/channels_quepasa_webhook/#{callback_token}?bid=#{bot['id']}"
    Quepasa.set_webhook(token, callback_url)

    if !channel
      channel = Quepasa.bot_by_bot_id(bot['id'])
      if !channel
        channel = Channel.new
      end
    end
    channel.area = 'Quepasa::Bot'
    channel.options = {
      bot:            {
        id:         bot['id'],
        username:   bot['username'],
        first_name: bot['first_name'],
        last_name:  bot['last_name'],
      },
      callback_token: callback_token,
      callback_url:   callback_url,
      api_token:      token,
      welcome:        params[:welcome],
      goodbye:        params[:goodbye],
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
    Channel.where(area: 'Quepasa::Bot').each do |channel|
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

  ### Tentar localizar no Zammad o Bot referente ao ID passado em parametro
  def self.bot_by_bot_id(bot_id)
    Channel.where(area: 'Quepasa::Bot').each do |channel|
      next if !channel.options
      next if !channel.options[:bot]
      next if !channel.options[:bot][:id]
      return channel if channel.options[:bot][:id].to_s == bot_id.to_s
    end
    nil
  end

=begin

generate message_id for message

  message_id = Quepasa.message_id(message)

returns

  message_id # 123456@quepasa

=end

  ### Não UTILIZADO ao copiar do telegram ..! ! !!
  def self.message_id(params)
    message_id = nil
    %i[message edited_message].each do |key|
      next if !params[key]
      next if !params[key][:message_id]

      message_id = params[key][:message_id]
      break
    end
    if message_id
      %i[message edited_message].each do |key|
        next if !params[key]
        next if !params[key][:chat]
        next if !params[key][:chat][:id]

        message_id = "#{message_id}.#{params[key][:chat][:id]}"
      end
    end
    if !message_id
      message_id = params[:update_id]
    end
    "#{message_id}@quepasa"
  end

=begin

  client = Quepasa.new('token')

=end

  def initialize(token)
    @token = token
    @api = QuepasaApi.new(token)
  end

=begin

  client.message(chat_id, 'some message', language_code)

=end

  # Usa a API para encaminhar uma mensagem, passando pelo sistema de tradução
  def message(chat_id, message, language_code = 'en')
    return if Rails.env.test?

    locale = Locale.find_by(alias: language_code)
    if !locale
      locale = Locale.where('locale LIKE :prefix', prefix: "#{language_code}%").first
    end

    if locale
      message = Translation.translate(locale[:locale], message)
    end

    @api.sendMessage(chat_id, message)
  end

  def user(params)
    {
      id:         params[:message][:from][:id],
      username:   params[:message][:from][:username],
      first_name: params[:message][:from][:first_name],
      last_name:  params[:message][:from][:last_name]
    }
  end

  def to_user(params)
    Rails.logger.debug { 'Create user from message...' }
    Rails.logger.debug { params.inspect }

    # do message_user lookup
    message_user = user(params)

    auth = Authorization.find_by(uid: message_user[:id], provider: 'quepasa')

    # create or update user
    login = message_user[:username] || message_user[:id]
    user_data = {
      login:     login,
      firstname: message_user[:first_name],
      lastname:  message_user[:last_name],
    }
    if auth
      user = User.find(auth.user_id)
      user.update!(user_data)
    else
      if message_user[:username]
        user_data[:note] = "Quepasa @#{message_user[:username]}"
      end
      user_data[:active]   = true
      user_data[:role_ids] = Role.signup_role_ids
      user                 = User.create(user_data)
    end

    # create or update authorization
    auth_data = {
      uid:      message_user[:id],
      username: login,
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

  # --------------------------------
  # ---- SUFFICIT

  ## Metodo de entrada exclusivo para o processamento das mensagens recebidas
  def self.MessageValidate(message)
    Rails.logger.debug { 'validating message' }
    Rails.logger.debug message

    # caso seja nula ou inválida
    return false if message.nil?

    # caso tenho sido eu mesmo quem enviou a msg, não precisa processar pois o artigo já foi criado
    return false if ActiveModel::Type::Boolean.new.cast(message[:fromme])    

    # ignorando msgs de status do whatsapp
    return false if message[:replyto][:id] == 'status@broadcast'
    
    return true
  end
  
  # Porta de entrada das msgs
  ## params = mensagem vinda da api ou do webhook diretamente
  ## group_id => para qual grupo do zammad devem ir as mensagens
  ## channel => canal/bot do quepasa que deve processar a msg
  def to_group(message, group_id, channel)
    # begin import
    Rails.logger.debug { 'import message' }
    
    # Retorna por aqui caso a mensagem não seja válida
    return if !Quepasa.MessageValidate(message)

    # Retorna por aqui caso a msg já tenha sido processada em algum artigo
    return if Ticket::Article.find_by(message_id: message[:message_id])

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

  def to_wagroup(message)
    Rails.logger.debug { 'Create user/quepasa group from group message...' }

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
              User.where(quepasa: endPointID).order(:updated_at).first
            end
      unless user
        Rails.logger.info { "SUFF: Create user from group message... #{endPointID}" }
        user = User.create!(
          login:  endPointID,
          quepasa: endPointID,
          active:    true,
          role_ids:  Role.signup_role_ids
        )
      end

      # atualizando nome de usuario se possível
      suffixName = "(GROUP)"
      
      # atualiza o primeiro nome do usuário com a definição mais atual vinda do quepasa
      # somente realiza a mudança se o último nome estiver em branco ou caso ainda tenha a tag (QUEPASA)
      # removendo ou modificando manualmente este sufixo, faz com que o titulo para de ser atualizado automáticamente
      if user.lastname.empty? || user.lastname == suffixName
        user.firstname = endPointTitle || endPointPhone || user.firstname || "unknown"
        user.lastname = suffixName
        user.save!
      end

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
             User.where(quepasa: endPointID).order(:updated_at).first
           end
    unless user
      Rails.logger.info { "SUFF: Create user from message... #{endPointID}" }

      user = User.create!(
        phone: endPointPhone,
        login:  endPointID,
        quepasa: endPointID,
        active:    true,
        role_ids:  Role.signup_role_ids
      )
    end
    
    # atualizando nome de usuario se possível
    suffixName = "(CONTACT)"
    
    # atualiza o primeiro nome do usuário com a definição mais atual vinda do quepasa
    # somente realiza a mudança se o último nome estiver em branco ou caso ainda tenha a tag (CONTACT)
    # removendo ou modificando manualmente este sufixo, faz com que o titulo para de ser atualizado automáticamente
    if user.lastname.empty? || user.lastname == suffixName
      user.firstname = endPointTitle || endPointPhone || user.firstname || "unknown"
      user.lastname = suffixName
      user.save!
    end

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

    Rails.logger.debug { "Create ticket from message..." }
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
    bot_id = message['bid']
    ticket = Ticket.where(customer_id: user.id).where.not(state_id: state_ids).where("preferences LIKE :bid", {:bid => "%bid: #{bot_id}%"}).order(:updated_at).first
    if ticket
      Rails.logger.info { "SUFF: Append to ticket(#{ticket.id}) from message... #{bot_id}" }

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

    Rails.logger.info { "SUFF: Creating new ticket from message... #{bot_id}" }
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
          bid:     bot_id, # Qual Quepasa utilizar para resposta
          chat_id: message[:chat][:id] # Destino no quepasa
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

    article_sender_id = Ticket::Article::Sender.find_by(name: 'Customer').id
    if user.permissions?('ticket.agent')
      article_sender_id = Ticket::Article::Sender.find_by(name: 'Agent').id
    end

    # capturando timestamp correto do envio ou recebimento da msg pelo quepasa
    # é preciso que seja em formato datetime, não int ou string
    receveid_at = DateTime.strptime(message[:timestamp].to_s,'%s')

    article = Ticket::Article.new(
      ticket_id:    ticket.id,
      type_id:      Ticket::Article::Type.find_by(name: 'quepasa personal-message').id,
      sender_id:    article_sender_id,
      from:         "#{user[:firstname]}#{user[:lastname]}",
      to:           "#{channel[:options][:bot][:phone]} - #{channel[:options][:bot][:name]}",
      message_id:   message[:message_id],
      internal:     false,
      created_at:   receveid_at,
      preferences:  {
        quepasa: {
          timestamp:  message[:timestamp], # Duplicado, marcado para remoção, obsoleto
          message_id: message[:message_id], # Duplicado, marcado para remoção, obsoleto
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

      # Tentando extrair o nome do arquivo
      fileName = attachment['filename']
      if fileName.nil? || fileName.empty?
        extension = Rack::Mime::MIME_TYPES.invert[singleMime]
        fileName = "#{message[:message_id]}#{extension}"
      end

      begin
        # Tentando extrair dados binarios (conteudo do anexo)
        document = get_file(message[:replyto][:id], attachment, 'pt-br')      

        Store.add(
          object:      'Ticket::Article',
          o_id:        article.id,
          data:        document,
          filename:    fileName,
          preferences: {
            'Mime-Type' => singleMime,
          },
        )

        rescue => e
          article.body = "(( Erro ao tentar baixar anexo )) :: #{e.message[0..50].gsub(/\s\w+\s*$/,'...')}"
          article.save!
        end
    end
    
    return article    
  end

  def get_file(destination, attachment, language)
    Rails.logger.info "QUEPASA: Geting file : #{attachment}"
    
    # quepasa bot files are limited up to 20MB
    if !validate_file_size(attachment['length'])
      message_text = 'File is to big. (Maximum 20mb)'
      message(destination, "Sorry, we could not handle your message. #{message_text}", language)
      raise Exceptions::UnprocessableEntity, message_text
    end

    begin
      result = @api.getAttachment(attachment)     
    rescue => e 
      message(destination, "Sorry, we could not handle your message. System unknown error", language)
      raise Exceptions::UnprocessableEntity, e.message
    end

    if !validate_download(result)
      message_text = 'Unable to get you file from bot.'
      message(destination, "Sorry, we could not handle your message. #{message_text}", language)
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
    Rails.logger.info "QUEPASA: Validating download ..."
    return false if result.nil?

    true
  end



  # ---- SUFFICIT
  # --------------------------------  

end
