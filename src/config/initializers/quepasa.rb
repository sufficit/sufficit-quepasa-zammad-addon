Rails.application.config.before_configuration do
  icon = File.read("public/assets/images/icons/quepasa.svg")
  doc = File.open("public/assets/images/icons.svg") { |f| Nokogiri::XML(f) }
  if !doc.at_css('#icon-quepasa')
    doc.at('svg').add_child(icon)
    Rails.logger.debug "quepasa icon added to icon set"
  else
    Rails.logger.debug "quepasa icon already in icon set"
  end
  File.write("public/assets/images/icons.svg", doc.to_xml)
end

Rails.application.config.after_initialize do
  Ticket::Article.add_observer Observer::Ticket::Article::CommunicateQuepasa.instance
end
