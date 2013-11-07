require "travis/notifications/util/template"
require "multi_json"
require "travis/notifications/notifier"

module Travis
  module Notifications
    module Notifiers
      # Publishes a build notification to campfire rooms as defined in the
      # configuration (`.travis.yml`).
      #
      # Campfire credentials are encrypted using the repository's ssl key.
      class Campfire < Notifier
        DEFAULT_TEMPLATE = [
          "[travis-ci] %{repository}#%{build_number} (%{branch} - %{commit} : %{author}): the build has %{result}",
          "[travis-ci] Change view: %{compare_url}",
          "[travis-ci] Build details: %{build_url}"
        ]

        def targets
          params[:targets]
        end

        def message
          @message ||= template.map { |line| Util::Template.new(line, payload).interpolate }
        end

        private

          def process
            targets.each { |target| send_message(target, message) }
          end

          def send_message(target, lines)
            url, token = parse(target)
            http.basic_auth(token, 'X')
            lines.each { |line| send_line(url, line) }
          rescue => e
            Travis.logger.info("Error connecting to Campfire service for #{target}: #{e.message}")
          end

          def send_line(url, line)
            http.post(url) do |r|
              r.body = MultiJson.encode({ message: { body: line } })
              r.headers['Content-Type'] = 'application/json'
            end
          end

          def template
            Array(config.fetch(:template, DEFAULT_TEMPLATE))
          end

          def parse(target)
            target =~ /([\w-]+):([\w-]+)@(\d+)/
            ["https://#{$1}.campfirenow.com/room/#{$3}/speak.json", $2]
          end

          def config
            Hash(build[:config][:notifications][:campfire])
          rescue
            {}
          end
      end
    end
  end
end
