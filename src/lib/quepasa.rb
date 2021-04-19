require 'quepasa_api'

class Quepasa

  attr_accessor :client

=begin

check token and return bot attributes of token

  bot = Quepasa.check_token('token')

=end

  def self.check_token(api_url, token)
    api = QuepasaApi.new(api_url, token)
    api.fetch_self()
  end

=begin

create or update channel, store bot attributes and verify token

  channel = Quepasa.create_or_update_channel('token', params)

returns

  channel # instance of Channel

=end

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
      api_token: token,
      api_url:   api_url,
      welcome:   params[:welcome],
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

  def fetch_messages(group_id, channel, last_seen_ts)

    older_import = 0
    older_import_max = 40
    new_last_seen_date = Quepasa.timestamp_to_date(last_seen_ts)
    new_last_seen_ts = last_seen_ts
    self_source_id = self.number_to_whatsapp_user(channel.options['bot']['number'])
    count = 0
    @api.fetch(last_seen_ts).each do |message_raw|
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
        replyto: message_raw['replyto'],
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

=begin

  client.send_message(chat_id, 'some message')

=end

  def send_message(recipient, message)
    return if Rails.env.test?

    @api.send_message(recipient, message)
  end

  def to_user(message)
    Rails.logger.debug { 'Create user from message...' }
    Rails.logger.debug { message.inspect }

    from_number = message[:from][:number]
    from_name = message[:from][:name]

    # create or update user
    auth = Authorization.find_by(uid: from_number, provider: 'quepasa')

    user = if auth
             User.find(auth.user_id)
           else
             User.where(mobile: from_number).order(:updated_at).first
           end
    unless user
      user = User.create!(
        firstname: from_name,
        login:  from_number,
        mobile:    from_number,
        note:      "WhatsApp UniqueID: #{message[:replyto]}",
        active:    true,
        role_ids:  Role.signup_role_ids
      )
    end

    # create or update authorization
    auth_data = {
      uid:      from_number,
      username: from_number,
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
    unless message[:message][:body].nil?
      title = message[:message][:body]
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
        channel_id: channel.id,
        quepasa:  {
          bot_id:  channel.options[:bot][:id],
          chat_id: message[:from][:number]
        }
      }
    )
    ticket.save!
    ticket
  end

  def to_article(message, user, ticket, channel)

    Rails.logger.debug { 'Create article from message...' }
    Rails.logger.debug { message.inspect }
    Rails.logger.debug { user.inspect }
    Rails.logger.debug { ticket.inspect }

    UserInfo.current_user_id = user.id

    article = Ticket::Article.new(
      from:         message[:from][:number],
      to:           channel[:options][:bot][:number],
      body:         message[:message][:body],
      content_type: 'text/plain',
      message_id:   message[:id],
      ticket_id:    ticket.id,
      type_id:      Ticket::Article::Type.find_by(name: 'quepasa personal-message').id,
      sender_id:    Ticket::Article::Sender.find_by(name: 'Customer').id,
      internal:     false,
      preferences:  {
        quepasa: {
          timestamp:  message[:timestamp],
          message_id: message[:id],
          from:       message[:from][:number],
        }
      }
    )

    # TODO: attachments
    # TODO voice
    # TODO emojis
    #
    if message[:message][:body]
      Rails.logger.debug { article.inspect }
      article.save!
      return article
    end
    raise 'invalid action'
  end

  def to_group(message, group_id, channel)
    # begin import
    Rails.logger.debug { 'quepasa import message' }

    # TODO: handle messages in group chats

    return if Ticket::Article.find_by(message_id: message[:id])

    ticket = nil
    # use transaction
    Transaction.execute(reset_user_id: true) do
      user = to_user(message)
      ticket = to_ticket(message, user, group_id, channel)
      to_article(message, user, ticket, channel)
    end

    ticket
  end

  def number_to_whatsapp_user(number)
    suffix = "@s.whatsapp.net"
    whatsapp_user = number
    unless number.include?(suffix)
      whatsapp_user = "#{number}#{suffix}"
    end
    if whatsapp_user.start_with?("+")
      whatsapp_user = whatsapp_user[1..-1]
    end
    whatsapp_user
  end

  def whatsapp_user_to_number(whatsapp_user)
    i = whatsapp_user.index("@") - 1
    whatsapp_user[0..i]
  end

  def from_article(article)
    r = @api.send_message(number_to_whatsapp_user(article[:to]), article[:body])
    if r['result'].present? and r['result']['source'].present?
      r['result']['source'] = self.whatsapp_user_to_number(r['result']['source'])
      r['result']['recipient'] = self.whatsapp_user_to_number(r['result']['recipient'])
    end
    r
  end

  def download_file(file_id)
    # TODO: attachments
  end

end
