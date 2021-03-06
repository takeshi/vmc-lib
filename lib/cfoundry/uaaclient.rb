require "cfoundry/baseclient"
require 'uaa'

module CFoundry
  class UAAClient < BaseClient
    attr_accessor :target, :client_id, :token, :trace

    def initialize(target = "https://uaa.cloudfoundry.com", client_id = "vmc")
      @target = target
      @client_id = client_id
      CF::UAA::Misc.symbolize_keys = true
    end

    def prompts
      wrap_uaa_errors do
        CF::UAA::Misc.server(target)[:prompts]
      end
    end

    def authorize(username, password)
      wrap_uaa_errors do
        begin
          creds = { :username => username, :password => password }
          token_issuer.implicit_grant_with_creds(creds)
        rescue CF::UAA::BadResponse => e
          status_code = e.message[/\d+/] || 400
          raise CFoundry::Denied.new("Authorization failed", status_code)
        end
      end
    end

    def users
      wrap_uaa_errors do
        scim.query(:user)
      end
    end

    def change_password(guid, new, old)
      wrap_uaa_errors do
        scim.change_password(guid, new, old)
      end
    end

    def password_score(password)
      wrap_uaa_errors do
        response = CF::UAA::Misc.password_strength(target, password)

        required_score = response[:requiredScore] || 0
        case (response[:score] || 0)
          when 10 then
            :strong
          when required_score..9 then
            :good
          else
            :weak
        end
      end
    end

    def add_user(email, password)
      wrap_uaa_errors do
        scim.add(
          :user,
          {:userName => email,
            :emails => [{:value => email}],
            :password => password,
            :name => {:givenName => email, :familyName => email}
          }
        )
      end
    end

    private

    def token_issuer
      @token_issuer ||= CF::UAA::TokenIssuer.new(target, client_id, nil, :symbolize_keys => true)
      @token_issuer.logger.level = @trace ? 0 : 1
      @token_issuer
    end

    def scim
      auth_header = token && token.auth_header
      scim = CF::UAA::Scim.new(target, auth_header)
      scim.logger.level = @trace ? 0 : 1
      scim
    end

    def wrap_uaa_errors
      yield
    rescue CF::UAA::BadResponse
      raise CFoundry::BadResponse
    rescue CF::UAA::NotFound
      raise CFoundry::NotFound
    rescue CF::UAA::InvalidToken
      raise CFoundry::Denied
    rescue CF::UAA::TargetError => e
      raise CFoundry::UAAError.new(e.info["error_description"], e.info["error"])
    end
  end
end
