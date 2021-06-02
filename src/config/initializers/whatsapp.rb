Rails.application.config.before_configuration do
  icon = File.read("app/assets/images/icons/whatsapp-icon.svg")
  doc = File.open("public/assets/images/icons.svg") { |f| Nokogiri::XML(f) }
  if !doc.at_css('#icon-whatsapp')
    doc.at('svg').add_child(icon)
    Rails.logger.debug "whatsapp icon added to icon set"
  else
    Rails.logger.debug "whatsapp icon already in icon set"
  end
  File.write("public/assets/images/icons.svg", doc.to_xml)
end

Rails.application.config.after_initialize do
  Ticket::Article.add_observer Observer::Ticket::Article::CommunicateWhatsapp.instance
end
