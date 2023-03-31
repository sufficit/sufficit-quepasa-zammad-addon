require 'json'
require 'net/http'
require 'net/https'
require 'uri'

# @description Controls the send and received messages from quepasa servers api
class QuepasaApi
  attr_reader :api_token, :api_base_url

  def initialize(api_token, api_base_url = nil)
    @api_token = api_token
    @api_base_url = if !api_base_url.blank?
      api_base_url
    else
      'http://api.quepasa.org:31000/v2'
    end
  end

  def getMe()
    ret = getJSON()
    ret
  end

  # Vai na API do QuePasa e atualiza o endereГ§o de webhook para agilizar as entregas de msgs
  def setWebhook(urlWebHook)        
    payload = { url: urlWebHook, forwardinternal: true, trackid: 'zammad' }
    ret = postJSON('/webhook', payload.to_json)
    ret
  end

  # Envia para QuePasa
  # QuePasa espera por (recipient, message, attachments?(opcional))
  def sendMessage(chat_id, message)
    Rails.logger.info { "[QUEPASA][API] Sending message to: #{chat_id} :: #{message}" } 

    payload = { recipient: chat_id, message: message }
    ret = postJSON('/sendtext', payload.to_json)
    ret
  end

  def sendDocument(chat_id, document)
    Rails.logger.info { "[QUEPASA][API] Sending document to: #{chat_id} " }  
    Rails.logger.info { "[QUEPASA][API] #{ document[:filename] }" }

    payload = { recipient: chat_id, attachment: document }
    ret = postJSON('/senddocument', payload.to_json)
    ret
  end
  
  # Vai na API do QuePasa e faz o download do anexo especГ­fico
  # Individualmente
  def getAttachment(msg_id)
    Rails.logger.info { "[QUEPASA][API] Downloading attachment: #{msg_id}" }

    payload = { url: msg_id }
    ret = postJSON('/attachment', payload.to_json)
    ret
  end

  ###
  ### Ainda nГЈo verifiquei adiante
  ###

  def parse_hash(hash)
    ret = {}
    hash.map do |k, v|
      ret[k] = CGI.encode(v.to_s.gsub('\\\'', '\''))
    end
    ret
  end

  def get(api='', params={})
    path = '/' + api
    if api.empty?
      path = ''
    end
    ret = getJSON(path)
    ret
  end

  # checked !
  # payload => json already converted post payload
  # endpoint => "/webhook"
  def postJSON(endpoint, payload)
    urlQuery = URI(@api_base_url + '/bot/' + @api_token + endpoint)
    Rails.logger.info { "[QUEPASA][API] post at: #{urlQuery} with: #{payload}" } 

    req = Net::HTTP::Post.new(urlQuery)
    req.body = payload
    req['Content-Type'] = 'application/json'
    resp = Net::HTTP.start(urlQuery.hostname, urlQuery.port) do |http|
        http.request(req)
    end
 
    ret = resp.body 
    Rails.logger.info { "[QUEPASA][API] posted response: #{ret}" } 
    ret
  end

  # checked !
  # endpoint => "/webhook" + query => "/webhook?id=uiuiui"
  def getJSON(endpoint = '')
    urlQuery = URI(@api_base_url + '/bot/' + @api_token + endpoint)
    resp = Net::HTTP.get_response(urlQuery)
    ret = JSON.parse(resp.body)
    ret
  end

  # backwards compatibility
  # following to postJSON
  def post(api, params = {})
    json = JSON.generate(params)
    path = '/' + api
    if api.empty?
      path = ''
    end
    ret = postJSON(path, json)
    ret
  end

  def fetch_self
    get('')
  end


  def fetch(last_seen_ts = nil)
    if last_seen_ts.nil?
      params = {}
    else
      params = {"timestamp"=>URI::encode(last_seen_ts.to_s)}
    end
    results = get('receive', params)
    if results['messages'].nil?
      Rails.logger.error { 'quepasa fetch failed' }
      Rails.logger.debug { results.inspect }
      return []
    end

    messages = results['messages']
    messages
  end
  
end
