# Copyright (C) 2012-2016 Zammad Foundation, http://zammad-foundation.org/

# Schedules a backgrond communication job for new quepasa articles.
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

    sender = Ticket::Article::Sender.lookup(id: sender_id)
    return true if sender.nil?
    return true if sender.name == 'Customer'

    # only apply on quepasa messages
    return true if !type_id

    type = Ticket::Article::Type.lookup(id: type_id)
    return true if !type.name.match?(%r{\Aquepasa}i)

    # only communicate messages without message id
    # ensure that the message is an outbound message and its not a duplicated message
    return true if !message_id.nil?

    CommunicateQuepasaJob.perform_later(id)
  end

end
