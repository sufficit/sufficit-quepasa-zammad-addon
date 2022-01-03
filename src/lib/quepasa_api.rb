require 'json'
require 'net/http'
require 'net/https'
require 'uri'
require 'rest-client'

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
    urlQuery = @url + '/bot/' + @token

    #Rails.logger.debug { urlQuery }
    resp = RestClient.get(urlQuery, { accept: :json })
    ret = JSON.parse(resp.body)
    ret
  end

  # Vai na API do QuePasa e atualiza o endereço de webhook para agilizar as entregas de msgs
  def setWebhook(urlWebHook)    
    Rails.logger.info { "SUFF: Atualizando WebHook ... #{urlWebHook}" } 
    payload = { url: urlWebHook }
    urlQuery = @url + '/bot/' + @token + '/webhook'
    ret = RestClient.post(urlQuery, payload.to_json, { :content_type => :json, accept: :json })
    ret
  end

  # Envia para QuePasa
  # QuePasa espera por (recipient, message, attachments?(opcional))
  def sendMessage(chat_id, message)
    Rails.logger.info { "QUEPASA: Sending message to: #{chat_id} :: #{message}" } 

    payload = { recipient: chat_id, message: message }
    urlQuery = @url + '/bot/' + @token + '/sendtext'
    ret = RestClient.post(urlQuery, payload.to_json, { :content_type => :json, accept: :json })
    ret = JSON.parse(ret)
    ret
  end

  def sendDocument(chat_id, document)
    Rails.logger.info { "QUEPASA: Sending document to: #{chat_id} " }  
    Rails.logger.info { "QUEPASA: #{ document[:filename] }" }

    payload = { recipient: chat_id, attachment: document }
    urlQuery = @url + '/bot/' + @token + '/senddocument'
    ret = RestClient.post(urlQuery, payload.to_json, { :content_type => :json, accept: :json })
    ret
  end
  
  # Vai na API do QuePasa e faz o download do anexo específico
  # Individualmente
  def getAttachment(payload)
    Rails.logger.info { "QUEPASA: Downloading attachment :: #{payload[:mime]}" } 

    urlQuery = @url + '/bot/' + @token + '/attachment'
    ret = RestClient.post(urlQuery, payload.to_json, { :content_type => :json, accept: :json })
    ret
  end

  ###
  ### Ainda não verifiquei adiante
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
    url = @api + '/bot/' + @token + path

    #Rails.logger.debug { url }
    #Rails.logger.debug {"params #{params.inspect}"}
    resp = RestClient.get(url, { accept: :json, :params => params })
    ret = JSON.parse(resp.body)
    ret
  end

  def post(api, params = {})
    json = JSON.generate(params)
    path = '/' + api
    if api.empty?
      path = ''
    end
    url = @api + '/bot/' + @token + path
    ret = JSON.parse(RestClient.post(url, json, { :content_type => :json, accept: :json }).body)
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
