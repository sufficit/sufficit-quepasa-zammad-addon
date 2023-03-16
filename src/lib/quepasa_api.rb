require 'json'
require 'net/http'
require 'net/https'
require 'uri'

# @description Controls the send and received messages from quepasa servers api
class QuepasaApi

  ENDPOINTS = %w[
    getUpdates setWebhook deleteWebhook getWebhookInfo getMe sendMessage
    forwardMessage sendPhoto sendAudio sendDocument sendVideo sendVoice
    sendVideoNote sendMediaGroup sendLocation editMessageLiveLocation
    stopMessageLiveLocation sendVenue sendContact sendChatAction
    getUserProfilePhotos getFile kickChatMember unbanChatMember
    restrictChatMember promoteChatMember leaveChat getChat
    getChatAdministrators exportChatInviteLink setChatPhoto deleteChatPhoto
    setChatTitle setChatDescription pinChatMessage unpinChatMessage
    getChatMembersCount getChatMember setChatStickerSet deleteChatStickerSet
    answerCallbackQuery editMessageText editMessageCaption
    editMessageReplyMarkup deleteMessage sendSticker getStickerSet
    uploadStickerFile createNewStickerSet addStickerToSet
    setStickerPositionInSet deleteStickerFromSet answerInlineQuery
    sendInvoice answerShippingQuery answerPreCheckoutQuery
    sendGame setGameScore getGameHighScores setPassportDataErrors
    editMessageMedia sendAnimation sendPoll stopPoll setChatPermissions
    setChatAdministratorCustomTitle sendDice getMyCommands setMyCommands
    setStickerSetThumb logOut close copyMessage createChatInviteLink
    editChatInviteLink revokeChatInviteLink
  ].freeze

  attr_reader :token, :url

  def initialize(token, url: 'http://api.quepasa.org:31000/v2')
    @token = token
    @url = url
  end

  def getMe()
    ret = getJSON()
    ret
  end

  # Vai na API do QuePasa e atualiza o endereГ§o de webhook para agilizar as entregas de msgs
  def setWebhook(urlWebHook)        
    payload = { url: urlWebHook }
    ret = postJSON('/webhook', payload.to_json)
    ret
  end

  # Envia para QuePasa
  # QuePasa espera por (recipient, message, attachments?(opcional))
  def sendMessage(chat_id, message)
    Rails.logger.info { "[QUEPASA] Sending message to: #{chat_id} :: #{message}" } 

    payload = { recipient: chat_id, message: message }
    ret = postJSON('/sendtext', payload.to_json)
    ret
  end

  def sendDocument(chat_id, document)
    Rails.logger.info { "[QUEPASA] Sending document to: #{chat_id} " }  
    Rails.logger.info { "[QUEPASA] #{ document[:filename] }" }

    payload = { recipient: chat_id, attachment: document }
    ret = postJSON('/senddocument', payload.to_json)
    ret
  end
  
  # Vai na API do QuePasa e faz o download do anexo especГ­fico
  # Individualmente
  def getAttachment(payload)
    Rails.logger.info { "[QUEPASA] Downloading attachment :: #{payload[:mime]}" } 

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
    urlQuery = URI(@url + '/bot/' + @token + endpoint)
    Rails.logger.info { "[QUEPASA] post at: #{urlQuery} with: #{payload}" } 

    req = Net::HTTP::Post.new(urlQuery)
    req.body = payload
    req['Content-Type'] = 'application/json'
    resp = Net::HTTP.start(urlQuery.hostname, urlQuery.port) do |http|
        http.request(req)
    end
 
    ret = resp.body 
    Rails.logger.info { "[QUEPASA] posted response: #{ret}" } 
    ret
  end

  # checked !
  # endpoint => "/webhook" + query => "/webhook?id=uiuiui"
  def getJSON(endpoint = '')
    urlQuery = URI(@url + '/bot/' + @token + endpoint)
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


  def fetch(last_seen_ts=nil)
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
