class QuepasaReply
  @action: (actions, ticket, article, ui) ->
    return actions if ui.permissionCheck('ticket.customer')

    if article.sender.name is 'Customer' && article.type.name is 'quepasa personal-message'
      actions.push {
        name: 'reply'
        type: 'quepasaPersonalMessageReply'
        icon: 'reply'
        href: '#'
      }

    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    return true if type isnt 'quepasaPersonalMessageReply'

    ui.scrollToCompose()

    # get reference article
    type = App.TicketArticleType.find(article.type_id)

    articleNew = {
      to:          ''
      cc:          ''
      body:        ''
      in_reply_to: ''
    }

    if article.message_id
      articleNew.in_reply_to = article.message_id

    # get current body
    articleNew.body = ui.el.closest('.ticketZoom').find('.article-add [data-name="body"]').html().trim() || ''

    App.Event.trigger('ui::ticket::setArticleType', {
      ticket: ticket
      type: type
      article: articleNew
      position: 'end'
    })

    true

  @articleTypes: (articleTypes, ticket, ui) ->
    return articleTypes if !ui.permissionCheck('ticket.agent')

    return articleTypes if !ticket || !ticket.create_article_type_id

    articleTypeCreate = App.TicketArticleType.find(ticket.create_article_type_id).name

    return articleTypes if articleTypeCreate isnt 'quepasa personal-message'
    articleTypes.push {
      name:              'quepasa personal-message'
      icon:              'quepasa'
      attributes:        []
      internal:          false,
      features:          []
      maxTextLength:     10000
      warningTextLength: 5000
    }
    articleTypes

  @setArticleTypePost: (type, ticket, ui) ->
    return if type isnt 'quepasa personal-message'
    rawHTML = ui.$('[data-name=body]').html()
    cleanHTML = App.Utils.htmlRemoveRichtext(rawHTML)
    if cleanHTML && cleanHTML.html() != rawHTML
      ui.$('[data-name=body]').html(cleanHTML)

  @params: (type, params, ui) ->
    if type is 'quepasa personal-message'
      App.Utils.htmlRemoveRichtext(ui.$('[data-name=body]'), false)
      params.content_type = 'text/plain'
      params.body = App.Utils.html2text(params.body, true)

    params

App.Config.set('300-QuepasaReply', QuepasaReply, 'TicketZoomArticleAction')
