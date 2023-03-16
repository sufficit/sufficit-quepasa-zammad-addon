class CommunicateQuepasaJob < ApplicationJob

  retry_on StandardError, attempts: 4, wait: lambda { |executions|
    executions * 5.seconds
  }

  def perform(article_id)
    Rails.logger.info { "[QUEPASA][COMMUNICATE]: perform: #{article_id}" }
    article = Ticket::Article.find(article_id)

    # set retry count
    article.preferences['delivery_retry'] ||= 0
    article.preferences['delivery_retry'] += 1

    ticket = Ticket.lookup(id: article.ticket_id)
    log_error(article, "[QUEPASA][COMMUNICATE] Can't find ticket.preferences for Ticket.find(#{article.ticket_id})", true) if !ticket.preferences

    channel = Channel.lookup(id: ticket.preferences['channel_id'])
    log_error(article, "[QUEPASA][COMMUNICATE] No such channel with id: #{ticket.preferences['channel_id']}", true) if !channel
    log_error(article, "[QUEPASA][COMMUNICATE] Channel.find(#{channel.id}) has not quepasa api token!", true) if channel.options[:api_token].blank?

    begin
      api = QuepasaApi.new(channel.options[:api_token], channel.options[:api_base_url])

      # ajustando o corpo da msg para texto simples caso ainda não seja
      if article.content_type != 'text/plain'

        Rails.logger.info { "[QUEPASA][COMMUNICATE] adjust content type #{article.content_type} :: #{article.body}" }

        # tenta atualizar primeiro, depois troca o formato se a atualização foi bem sucedida
        article.body = article.body.html2text
        article.content_type = 'text/plain'
      end

      messageToSend = article.body

      ### Prepend user name to quepasa
      user = User.find_by(id: article.created_by_id)
      if user
        Rails.logger.info { '[QUEPASA][COMMUNICATE] prepending user title' }
        prependText = "\*#{user.firstname} #{user.lastname}\*: "
        messageToSend = "#{prependText}#{messageToSend}"
      end

      ### finding quepasa chat id
      chat_id = Quepasa.GetChatIdByCustomer(ticket.customer_id)
      result = api.sendMessage(chat_id, messageToSend)
      me = api.getMe()
      article.attachments.each do |attach|
        document = {
          'length'   => attach.size.to_i,
          'filename' => attach.filename,
          'mime'     => attach.preferences['Content-Type'] || attach.preferences['Mime-Type'] || 'application/octet-stream',
          'base64'   => Base64.encode64(attach.content).delete("\n"),
        }
        api.sendDocument(chat_id, document)
      end
    rescue => e
      log_error(article, e.message)
      return
    end

    Rails.logger.info { "[QUEPASA][COMMUNICATE] result info: #{result}" }

    # only private, group messages. channel messages do not have from key
    if result
      article.preferences['quepasa'] = {
        # V3
        source:     result['result']['source'],
        recipient:  result['result']['recipient'],
        messageId:  result['result']['messageId'],

        # V2
        chat_id:    result['chat']['id'],
        message_id: result['message_id']
      }
    end

    # set delivery status
    article.preferences['delivery_status_message'] = nil
    article.preferences['delivery_status'] = 'success'
    article.preferences['delivery_status_date'] = Time.now.utc
    article.message_id = result['result']['messageId']

    article.save!

    Rails.logger.info { "[QUEPASA][COMMUNICATE] sended quepasa message to: '#{article.to}' (from #{article.from})" }
    article
  end

  def log_error(local_record, message, critical = false)
    local_record.preferences['delivery_status'] = 'fail'
    local_record.preferences['delivery_status_message'] = message.encode!('UTF-8', 'UTF-8', invalid: :replace, replace: '?')
    local_record.preferences['delivery_status_date'] = Time.now.utc
    local_record.save
    Rails.logger.error message

    ### Teste de tradução de mensagem de erro para o quepasa
    if local_record.preferences['delivery_retry'] > 3 || critical

      prependMessage = "Unable to send Quepasa message"
      language_code = Setting.get('locale_default') || 'en'
      locale = Locale.find_by(alias: language_code)
      if !locale
        locale = Locale.where('locale LIKE :prefix', prefix: "#{language_code}%").first
      end

      if locale
        prependMessage = Translation.translate(locale[:locale], prependMessage)
      end

      Ticket::Article.create(
        ticket_id:     local_record.ticket_id,
        content_type:  'text/plain',
        body:          "#{prependMessage}: #{message}",
        internal:      true,
        sender:        Ticket::Article::Sender.find_by(name: 'System'),
        type:          Ticket::Article::Type.find_by(name: 'note'),
        preferences:   {
          delivery_article_id_related: local_record.id,
          delivery_message:            true,
        },
        updated_by_id: 1,
        created_by_id: 1,
      )
    end

    raise message
  end
end