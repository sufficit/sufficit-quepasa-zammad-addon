class Channel::Driver::Quepasa

=begin

  Channel::Driver::Quepasa.fetchable?

returns

  true|false

=end
  def fetchable?(_channel)
    return true if Rails.env.test?

    # only fetch once in 30 minutes
    # return true if !channel.preferences
    # return true if !channel.preferences[:last_fetch]
    # return false if channel.preferences[:last_fetch] > Time.zone.now - 20.minutes

    true
  end

=begin

fetch messages from quepasa

  options = {}

  instance = Channel::Driver::Quepasa.new
  result = instance.fetch(options, channel)

returns

  {
    result: 'ok',
  }

=end
  def fetch(options, channel)
    options = check_external_credential(options)
    @quepasa = ::Quepasa.new(channel.options[:api_url], channel.options[:api_token])
    last_seen_ts = channel.preferences[:last_seen_ts] or Time.now.getutc.to_i

    Rails.logger.info { "quepasa fetch started with last_seen_ts: #{last_seen_ts}" }
    new_last_seen_ts = @quepasa.fetch_messages(channel.group_id, channel, last_seen_ts)
    channel.preferences[:last_seen_ts] = new_last_seen_ts
    Rails.logger.info { "quepasa fetch completed, with new last_seen_ts #{new_last_seen_ts}" }
    {
      result: 'ok',
      notice: '',
    }
  end

  def disconnect; end

=begin

  instance = Channel::Driver::Quepasa.new
  instance.send(
    {
      adapter: 'quepasa',
      auth: {
        api_key:       api_key
      },
    },
    quepasa_attributes,
    notification
  )

=end

  def send(options, article, _notification = false)
    Rails.logger.info { "SUFF: channel/driver/quepasa/send: #{article} :: #{options}" }

    # return if we run import mode
    Rails.logger.debug { "quepasa send started importmode? #{Setting.get('import_mode')}" }
    return if Setting.get('import_mode')

    options = check_external_credential(options)

    Rails.logger.debug { options.inspect }
    @quepasa = ::Quepasa.new(options[:api_url], options[:api_token])
    @quepasa.from_article(article)
  end

=begin

  Channel::Driver::Quepasa.streamable?

returns

  true|false

=end

  def self.streamable?
    false
  end

  private

  def check_external_credential(options)
    if options[:auth] && options[:auth][:external_credential_id]
      external_credential = ExternalCredential.find_by(id: options[:auth][:external_credential_id])
      raise "No such ExternalCredential.find(#{options[:auth][:external_credential_id]})" if !external_credential

      options[:auth][:api_key] = external_credential.credentials['api_key']
    end
    options
  end

end
