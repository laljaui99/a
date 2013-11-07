require "faraday"
require "digest/sha2"
require "travis/notifications/notifier"

module Travis
  module Notifications
    module Notifiers
      # Sends build notifications to webhooks as defined in the configuration
      # (`.travis.yml`).
      class Webhook < Notifier
        def targets
          params[:targets]
        end

        private

          def process
            Array(targets).each { |target| send_webhook(target) }
          end

          def send_webhook(target)
            response = http.post(target) do |req|
              req.body = { payload: payload.except(:params).to_json }
              uri = URI(target)
              if uri.user && uri.password
                req.headers['Authorization'] =
                  Faraday::Request::BasicAuthentication.header(
                    URI.unescape(uri.user), URI.unescape(uri.password)
                  )
              else
                req.headers['Authorization'] = authorization
              end
            end
            response.success? ? log_success(response) : log_error(response)
          end

          def authorization
            Digest::SHA2.hexdigest(repository.values_at(:owner_name, :name).join('/') + params[:token].to_s)
          end

          def log_success(response)
            info "Successfully notified #{response.env[:url].to_s}."
          end

          def log_error(response)
            error "Could not notify #{response.env[:url].to_s}. Status: #{response.status} (#{response.body.inspect})"
          end
      end
    end
  end
end

