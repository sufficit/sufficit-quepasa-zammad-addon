require 'quepasa_api'

class Quepasa

  attr_reader :client
  
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

  def self.GetChannelFromId(bot_id)
    Channel.where(area: 'Quepasa::Bot').each do |channel|
      next if !channel.options
      next if !channel.options[:bot]
      next if !channel.options[:bot][:id]
      return channel if channel.options[:bot][:id].to_s == bot_id.to_s
    end
    nil
  end

  def self.GetChatIdByCustomer(customerId)
    Rails.logger.info { "[QUEPASA]: get chat id by customer: #{customerId}" }    

    user = User.find(customerId)
    raise RuntimeError, "user not found for id #{customerId}" if user.nil?

    Rails.logger.info { user.inspect }
    return user.quepasa || user.phone || user.login
  end

  def self.timestamp_to_date(timestamp_str)
    Time.at(timestamp_str.to_i).utc.to_datetime
  end

  def initialize(params)
    Rails.logger.info { '[QUEPASA] initialized' }
    Rails.logger.info { params.inspect }

    @client = QuepasaApi.new(params[:api_token], params[:api_base_url])
  end
  
  def CreateOrUpdateChannel(params, channel = nil)

    # verify api_token
    bot = client.fetch_self()

    if !channel && bot_duplicate?(bot['id'])
      raise Exceptions::UnprocessableEntity, __('This bot already exists.')
    end

    if params[:group_id].blank?
      raise Exceptions::UnprocessableEntity, __("The required parameter 'group_id' is missing.")
    end

    group = Group.find_by(id: params[:group_id])
    if !group
      raise Exceptions::UnprocessableEntity, __("The required parameter 'group_id' is invalid.")
    end

    # generate random callback token
    callback_token = if Rails.env.test?
      'callback_token'
    else
      SecureRandom.urlsafe_base64(10)
    end

    # set webhook / callback url for this bot @ telegram
    callback_url = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/api/v1/channels_quepasa_webhook/#{callback_token}?bid=#{bot['id']}"
    client.setWebhook(callback_url)

    if !channel
      channel = Quepasa.GetChannelFromId(bot['id'])
      if !channel
        channel = Channel.new
      end
    end
    channel.area = 'Quepasa::Bot'
    channel.options = {
      adapter:   'quepasa',
      bot:       {
        id:     bot['id'],
        number: bot['number'],
      },
      callback_token: callback_token,
      callback_url:   callback_url,
      api_token:    params[:api_token],
      api_base_url: params[:api_base_url],
      welcome:        params[:welcome],
      goodbye:        params[:goodbye],
    }
    channel.group_id = group.id
    channel.active = true
    channel.save!
    channel
  end

  def fetch_messages(group_id, channel, last_seen_ts)
    older_import = 0
    older_import_max = 40
    new_last_seen_date = Quepasa.timestamp_to_date(last_seen_ts)
    new_last_seen_ts = last_seen_ts
    self_source_id = self.number_to_whatsapp_user(channel.options['bot']['number'])
    count = 0
    @client.fetch(last_seen_ts).each do |message_raw|
      Rails.logger.debug { "quepasa processing message self_source_id=#{self_source_id} and source=#{message_raw['source']}" }
      Rails.logger.debug { message_raw.inspect }
      next if message_raw['source'] == self_source_id
      count += 1
      timestamp = message_raw['timestamp']
      created_at = Quepasa.timestamp_to_date(timestamp)
      message = {
        from: {
          number:     self.whatsapp_user_to_number(message_raw['source']),
          name:       message_raw['name'],
        },
        to: {
          number:     channel.options['bot']['number']
        },
        timestamp:  timestamp,
        created_at: created_at,
        id:         message_raw['id'],
        message:    {
          body:       message_raw['body'],
        }
      }

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

  # Usa a API para encaminhar uma mensagem, passando pelo sistema de tradução
  def message(destination, message, language = 'en')
    return if Rails.env.test?
    Rails.logger.info { '[QUEPASA] sending message ...' }
    Rails.logger.info { message.inspect }

    locale = Locale.find_by(alias: language)
    if !locale
      locale = Locale.where('locale LIKE :prefix', prefix: "#{language}%").first
    end

    if locale
      message = Translation.translate(locale[:locale], message)
    end

    client.sendMessage(destination, message)
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
    Rails.logger.info { '[QUEPASA] creating user from message ...' }
    Rails.logger.info { params.inspect }

    # do message_user lookup
    message_user = user(params)

    auth = Authorization.find_by(uid: message_user[:id], provider: 'quepasa')

    # create or update user
    chat_id = message_user[:username] || message_user[:id]
    user_data = {
      login:     chat_id,
      firstname: message_user[:first_name],
      lastname:  message_user[:last_name],
      quepasa: chat_id
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
      username: chat_id,
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
    Rails.logger.info { '[QUEPASA] validating message' }
    Rails.logger.info { message.inspect }

    # caso seja nula ou inválida
    return false if message.nil?

    # caso tenho sido eu mesmo quem enviou a msg, não precisa processar pois o artigo já foi criado
    return false if ActiveModel::Type::Boolean.new.cast(message[:fromme])

    # ignorando msgs de status do whatsapp
    return false if message[:chat][:id] == 'status@broadcast'

    return true
  end

  # Porta de entrada das msgs
  ## params = mensagem vinda da api ou do webhook diretamente
  ## group_id => para qual grupo do zammad devem ir as mensagens
  ## channel => canal/bot do quepasa que deve processar a msg
  def to_group(message, group_id, channel)
    Rails.logger.info { '[QUEPASA] to group' }

    # Retorna por aqui caso a mensagem não seja válida
    return if !Quepasa.MessageValidate(message)

    Rails.logger.info { '[QUEPASA] finding article' }
    # Retorna por aqui caso a msg já tenha sido processada em algum artigo
    return if Ticket::Article.find_by(message_id: message[:id])

    # define o ticket como nulo para comerçarmos o processo
    ticket = nil

    # cria um transação para garantir que todo o processo seja coerente no final
    # se não conhece database transactions, pare por aqui e vai estudar
    Transaction.execute(reset_user_id: true) do
      wagroup = to_wagroup(message)   # cria um usuario caso a msg venha de algum grupo
      wauser  = to_wauser(message)    # cria outro usuario caso seja uma msg direta ou para o participante do grupo

      ticket_user = wauser if wagroup.nil?
      ticket = to_ticket(message, ticket_user, group_id, channel)
      to_article(message, wauser, ticket, channel)
    end

    ticket
  end

  def to_wagroup(message)
    Rails.logger.info { 'QUEPASA: to user from group message ...' }

    # Somente se for uma msg de grupo
    if message[:chat][:id].end_with?("@g.us")

      # definindo o que utilizar como endpoint de usuario
      endPointID = message[:chat][:id]
      endPointTitle = message[:chat][:title]
      endPointPhone = message[:chat][:phone]

      # create or update users
      auth = Authorization.find_by(uid: endPointID, provider: 'quepasa')
      user = if auth
              User.find(auth.user_id)
            else
              User.where(quepasa: endPointID).order(:updated_at).first
            end
      unless user
        Rails.logger.info { "[QUEPASA] create user from group message ... #{endPointID}" }
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
    Rails.logger.info { '[QUEPASA] to user from message ...' }
    Rails.logger.info { message.inspect }

    # definindo o que utilizar como endpoint de usuario
    if !(message[:participant].nil?)
      endPointID = message[:participant][:id]
      endPointTitle = message[:participant][:title]
      endPointPhone = message[:participant][:phone]
    else
      endPointID = message[:chat][:id]
      endPointTitle = message[:chat][:title]
      endPointPhone = message[:chat][:phone]
    end

    # create or update users
    auth = Authorization.find_by(uid: endPointID, provider: 'quepasa')
    user = if auth
             User.find(auth.user_id)
           else
             User.where(quepasa: endPointID).order(:updated_at).first
           end
    unless user
      Rails.logger.info { "[QUEPASA] create user from message ... #{endPointID}" }

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

    Rails.logger.info { '[QUEPASA] get or create ticket from message ...' }
    Rails.logger.info { message.inspect }
    Rails.logger.info { user.inspect }
    Rails.logger.info { channel.inspect }

    # prepare title
    title = '-'
    unless message[:text].nil?
      title = message[:text]
    end
    if title.length > 60
      title = "#{title[0, 60]}..."
    end
       
    # find ticket or create one
    state_ids        = Ticket::State.where(name: %w[closed merged removed]).pluck(:id)
    possible_tickets = Ticket.where(customer_id: user.id).where.not(state_id: state_ids)
    ticket           = possible_tickets.find_each.find { |possible_ticket| possible_ticket.preferences[:channel_id] == channel.id }

    if ticket
      Rails.logger.info { "[QUEPASA] append to ticket(#{ticket.id}) from message ..." }

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

    Rails.logger.info { "QUEPASA: creating new ticket from message ..." }
    ticket = Ticket.new(
      group_id:    group_id,
      title:       title,
      state_id:    Ticket::State.find_by(default_create: true).id,
      priority_id: Ticket::Priority.find_by(default_create: true).id,
      customer_id: user.id,
      preferences: {
        # Usado para encontrar esse elemento ao responder um ticket
        channel_id: channel.id
      }
    )
    ticket.save!
    ticket
  end

  def to_article(message, user, ticket, channel)

    Rails.logger.info { 'QUEPASA: create article from message ...' }
    Rails.logger.info { message.inspect }
    Rails.logger.info { user.inspect }
    Rails.logger.info { ticket.inspect }
    Rails.logger.info { channel.inspect }

    UserInfo.current_user_id = user.id

    article_sender_id = Ticket::Article::Sender.find_by(name: 'Customer').id
    if user.permissions?('ticket.agent')
      article_sender_id = Ticket::Article::Sender.find_by(name: 'Agent').id
    end

    #recovering type id from database
    article_type_id = Ticket::Article::Type.find_by(name: 'quepasa personal-message').id

    article = Ticket::Article.new(
      ticket_id:    ticket.id,
      type_id:      article_type_id,
      sender_id:    article_sender_id,
      from:         "#{user[:firstname]}#{user[:lastname]}",
      to:           "#{channel[:options][:bot][:phone]} - #{channel[:options][:bot][:name]}",
      message_id:   message[:id],
      internal:     false,
      created_at:   message[:timestamp].to_datetime
    )

    if !message[:text]
      message[:text] = ''
      #raise Exceptions::UnprocessableEntity, 'invalid quepasa message'
    end

    Rails.logger.info { 'QUEPASA: processando msg de texto simples ... ' }
    article.content_type = 'text/plain'
    article.body = message[:text]
    article.save!

    # Processando msg com anexos
    attachment = message[:attachment]
    if !attachment.nil? && !attachment.empty?
      Rails.logger.info { 'QUEPASA: processing attachment ... ' }
      Rails.logger.info { attachment.inspect }

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
        fileName = "#{message[:id]}#{extension}"
      end

      begin
        # Tentando extrair dados binarios (conteudo do anexo)
        document = get_file(message[:id], message[:chat][:id], attachment, 'pt-br')

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
          article.body = "(( error on downloading attachment )) :: #{e.message[0..50].gsub(/\s\w+\s*$/,'...')}"
          article.save!
        end
    end

    return article
  end

  def get_file(messageId, destination, attachment, language)

    # quepasa bot files are limited up to 20MB
    if !validate_file_size(attachment['filelength'])
      message_text = 'file is to big. (maximum 20mb)'
      message(destination, "sorry, we could not handle your message. #{message_text}", language)
      raise Exceptions::UnprocessableEntity, message_text
    end

    begin
      Rails.logger.info { "QUEPASA: getting file ... " }
      result = client.getAttachment(messageId)
    rescue => e
      Rails.logger.error { "QUEPASA: error on download attach: #{e}" }
      message(destination, "sorry, we could not handle your message. system unknown error", language)
      raise Exceptions::UnprocessableEntity, e.message
    end

    if !validate_download(result)
      message_text = 'unable to get you file from bot.'
      message(destination, "sorry, we could not handle your message. #{message_text}", language)
      raise Exceptions::UnprocessableEntity, message_text
    end

    result
  end

  def validate_file_size(length)
    Rails.logger.info { "QUEPASA: validating file size, length: #{length}" }
    return false if length >= 20.megabytes

    true
  end

  def validate_download(result)
    Rails.logger.info { "QUEPASA: validating download ..." }
    return false if result.nil?

    true
  end

end
