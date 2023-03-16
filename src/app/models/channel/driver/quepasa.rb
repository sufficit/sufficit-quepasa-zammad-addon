# Copyright (C) 2012-2015 Zammad Foundation, http://zammad-foundation.org/

class Channel::Driver::Quepasa

  def send(options, article, notification = false)
    Rails.logger.info { "[QUEPASA][DRIVER] sending, notification: #{notification} " }
    Rails.logger.info { options.inspect }
    Rails.logger.info { article.inspect }

    # return if we run import mode
    return if Setting.get('import_mode')

    options = check_external_credential(options)

    quepasa = Quepasa.new(options)
    quepasa.from_article(article)

  end

  def fetch(adapter_options, params)
    Rails.logger.info { "[QUEPASA][DRIVER] fetch" }
    Rails.logger.info { adapter_options.inspect }
    Rails.logger.info { params.inspect }
  end

  def fetchable?(channel)
    return true if Rails.env.test?

    # only fetch once in 30 minutes
    return true if !channel.preferences
    return true if !channel.preferences[:last_fetch]
    return false if channel.preferences[:last_fetch] > 20.minutes.ago

    true
  end

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
