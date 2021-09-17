class CommunicateQuepasaJob < ApplicationJob

  retry_on StandardError, attempts: 4, wait: lambda { |executions|
    executions * 120.seconds
  }

  def perform(article_id)
    article = Ticket::Article.find(article_id)

    # set retry count
    article.preferences['delivery_retry'] ||= 0
    article.preferences['delivery_retry'] += 1

    ticket = Ticket.lookup(id: article.ticket_id)
    log_error(article, "Can't find ticket.preferences for Ticket.find(#{article.ticket_id})") if !ticket.preferences
    log_error(article, "Can't find ticket.preferences['quepasa'] for Ticket.find(#{article.ticket_id})") if !ticket.preferences['quepasa']
    log_error(article, "Can't find ticket.preferences['quepasa']['chat_id'] for Ticket.find(#{article.ticket_id})") if !ticket.preferences['quepasa']['chat_id']
    if ticket.preferences['quepasa'] && ticket.preferences['quepasa']['bid']
      channel = Quepasa.bot_by_bot_id(ticket.preferences['quepasa']['bid'])
    end
    if !channel
      channel = Channel.lookup(id: ticket.preferences['channel_id'])
    end
    log_error(article, "No such channel for bot #{ticket.preferences['bid']} or channel id #{ticket.preferences['channel_id']}") if !channel
    #log_error(article, "Channel.find(#{channel.id}) isn't a quepasa channel!") if channel.options[:adapter] !~ /\Aquepasa/i
    log_error(article, "Channel.find(#{channel.id}) has not quepasa api token!") if channel.options[:api_token].blank?

    begin
      api = QuepasaAPI.new(channel.options[:api_token])
      chat_id = ticket.preferences[:quepasa][:chat_id]
      result = api.sendMessage(chat_id, article.body)
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

    Rails.logger.info { "result info: #{result}" }

    # only private, group messages. channel messages do not have from key
    if result
      article.preferences['quepasa'] = {
        date:       result['date'],
        from_id:    result['from']['id'],
        chat_id:    result['chat']['id'],
        message_id: result['message_id']
      }

      #article.from = "@#{me['username']}"
      #article.to = "#{result['chat']['title']} Channel"   
    end

    # set delivery status
    article.preferences['delivery_status_message'] = nil
    article.preferences['delivery_status'] = 'success'
    article.preferences['delivery_status_date'] = Time.zone.now

    article.message_id = "quepasa.#{result['message_id']}.#{result['chat']['id']}"

    article.save!

    Rails.logger.info "Send quepasa message to: '#{article.to}' (from #{article.from})"

    article
  end

  def log_error(local_record, message)
    local_record.preferences['delivery_status'] = 'fail'
    local_record.preferences['delivery_status_message'] = message.encode!('UTF-8', 'UTF-8', invalid: :replace, replace: '?')
    local_record.preferences['delivery_status_date'] = Time.zone.now
    local_record.save
    Rails.logger.error message

    if local_record.preferences['delivery_retry'] > 3
      Ticket::Article.create(
        ticket_id:     local_record.ticket_id,
        content_type:  'text/plain',
        body:          "Unable to send quepasa message: #{message}",
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
