# Encaminha de volta as mensagens para o whatsapp
class Observer::Ticket::Article::CommunicateWhatsapp < ActiveRecord::Observer
  observe 'ticket::_article'

  def after_create(record)

    # return if we run import mode
    return true if Setting.get('import_mode')

    # if sender is customer, do not communicate
    return true if !record.sender_id

    sender = Ticket::Article::Sender.lookup(id: record.sender_id)
    return true if sender.nil?
    return true if sender.name == 'Customer'

    # only apply on quepasa messages
    return true if !record.type_id

    type = Ticket::Article::Type.lookup(id: record.type_id)
    return true if type.name !~ /\Aquepasa/i

    ticket = Ticket.lookup(id: record.ticket_id)
    
    # Confere se o ticket foi criado por um agente
    # e preenche as informações basicas
    if !ticket.preferences['channel_id']
      channel = Channel.where(area: 'Quepasa::Account').first()
      customer = User.find(ticket['customer_id']) 

      ticket.preferences = {
        # Usado para encontrar esse elemento ao responder um ticket
        # Usado somente se não encontrar pelo quepasa:bot
        channel_id: channel.id,
        
        # Salva informações do contato para ser usado ao responder qualquer artigo dentro deste ticket
        quepasa:  {
          bot:  channel.options[:bot][:id], # Qual Whatsapp utilizar para resposta
          replyto: customer['whatsapp'] # Destino no whatsapp
        }
      }
      ticket.save!
    end

    Delayed::Job.enqueue(Observer::Ticket::Article::CommunicateWhatsapp::BackgroundJob.new(record.id))
  end

end
