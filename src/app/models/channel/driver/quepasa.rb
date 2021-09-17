# Copyright (C) 2012-2015 Zammad Foundation, http://zammad-foundation.org/

class Channel::Driver::Quepasa

  =begin
  
    instance = Channel::Driver::Quepasa.new
    instance.send(
      {
        adapter: 'quepasa',
        auth: {
          api_key: api_key
        },
      },
      quepasa_attributes,
      notification
    )
  
  =end
  
    def send(options, article, _notification = false)
  
      # return if we run import mode
      return if Setting.get('import_mode')
  
      options = check_external_credential(options)
  
      @client = Quepasa.new(options[:auth][:api_key])
      @client.from_article(article)
  
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
  