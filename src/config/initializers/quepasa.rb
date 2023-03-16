Rails.application.config.before_configuration do
    icon = File.read("public/assets/images/icons/quepasa.svg")
    doc = File.open("public/assets/images/icons.svg") { |f| Nokogiri::XML(f) }
    if !doc.at_css('#icon-quepasa')
        doc.at('svg').add_child(icon)
        Rails.logger.info "Quepasa icon added to icon set."
    #else # dbug porpouses
    #    Rails.logger.info "Quepasa icon already in icon set."
    end
    #File.write("public/assets/images/icons.svg", doc.to_xml)
end

Rails.application.config.after_initialize do
    Ticket::Article.include(Ticket::Article::EnqueueCommunicateQuepasaJob)
    Rails.logger.info "Quepasa enqueue communicate jobs."
end