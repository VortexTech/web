class OrganizationMailer < ActionMailer::Base
    default :from       => %{"#{ORG::NAME}" <#{ORG::EMAIL}>}
    default :reply_to   => %{"#{ORG::NAME}" <#{ORG::EMAIL}>}

    # If we don't define a Message-ID header, ActionMailer generates one for us.
    # The Message-ID generated by ActionMailer uses the machine hostname as the domain.
    # This causes problems with Gmail marking our messages as spam, so, we define a proper id.
    default :message_id => lambda {|_| "<#{Digest::SHA2.hexdigest(Time.now.to_f.to_s)}@#{ORG::DOMAIN}>" }

end
