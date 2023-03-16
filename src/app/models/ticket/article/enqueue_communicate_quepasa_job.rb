# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

# Schedules a background communication job for new quepasa articles.
module Ticket::Article::EnqueueCommunicateQuepasaJob
  extend ActiveSupport::Concern

  included do
    after_create :ticket_article_enqueue_communicate_quepasa_job
  end

  private

  def ticket_article_enqueue_communicate_quepasa_job

    # return if we run import mode
    return true if Setting.get('import_mode')

    # if sender is customer, do not communicate
    return true if !sender_id

    Rails.logger.info { "QUEPASA ENQUEUE: sender: #{sender_id}" }
    sender = Ticket::Article::Sender.lookup(id: sender_id)
    return true if sender.nil?
    return true if sender.name == 'Customer'

    # only apply on quepasa messages
    return true if !type_id

    Rails.logger.info { "QUEPASA ENQUEUE: type: #{type_id}" }
    type = Ticket::Article::Type.lookup(id: type_id)
    return true if !type.name.match?(%r{\Aquepasa}i)

    # only communicate messages without message id
    # ensure that the message is an outbound message and its not a duplicated message
    return true if !message_id.nil?

    ### starting a ticket by quepasa
    ### starting a ticket by quepasa
    ### starting a ticket by quepasa

    Rails.logger.info { "QUEPASA ENQUEUE: ticket: #{ticket_id}" }

    # Confere se o ticket foi criado por um agente
    # e preenche as informações basicas
    if !ticket.preferences['channel_id']
      Rails.logger.info { 'QUEPASA ENQUEUE: starting a ticket by quepasa' }

      ###
      ### setting the first quepasa channel as default outbound sender
      channel = Channel.where(area: 'Quepasa::Bot').first()

      ticket.preferences = {
        # Usado para encontrar esse elemento ao responder um ticket
        # Usado somente se não encontrar pelo quepasa:bot
        channel_id: channel.id
      }
      ticket.save!
      Rails.logger.info { ticket.inspect }
    end

    ### starting a ticket by quepasa
    ### starting a ticket by quepasa
    ### starting a ticket by quepasa

    CommunicateQuepasaJob.perform_later(id)
  end

end
