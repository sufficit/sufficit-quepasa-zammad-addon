require 'json'
require 'net/http'
require 'net/https'
require 'uri'
require 'rest-client'

class QuepasaApi
  def initialize(api_url, token)
    @token = token
    @last_update = 0
    @api = api_url
  end

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

  def send_message(recipient, text, options = {})
    payload = { recipient: recipient.to_s, message: text }.merge(parse_hash(options))
    results = post('send', payload)
    results
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
