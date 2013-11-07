require "travis/notifications/util/template"
require "travis/notifications/notifier"

module Travis
  module Notifications
    module Notifires
      # Publishes a build notification to hipchat rooms as defined in the
      # configuration (`.travis.yml`).
      #
      # Hipchat credentials can be encrypted using the repository's ssl key.
      class Hipchat < Notifier
        DEFAULT_TEMPLATE = [
          "%{repository}#%{build_number} (%{branch} - %{commit} : %{author}): the build has %{result}",
          "Change view: %{compare_url}",
          "Build details: %{build_url}"
        ]

        def targets
          params[:targets]
        end

        def message
          @messages ||= template.map { |line| Util::Template.new(line, payload).interpolate }
        end

        private

          def process
            targets.each { |target| send_lines(target, message) }
          end

          def send_lines(target, lines)
            url, room_id = parse(target)
            lines.each { |line| send_line(url, room_id, line) }
          end

          def template
            template = config[:template] rescue nil
            Array(template || DEFAULT_TEMPLATE)
          end

          def send_line(url, room_id, line)
            http.post(url) do |r|
              r.body = { room_id: room_id, message: line, color: color, from: 'Travis CI', message_format: message_format }
            end
          end

          def parse(target)
            target =~ /^([\w]+)@([\S ]+)$/
            ["https://api.hipchat.com/v1/rooms/message?format=json&auth_token=#{$1}", $2]
          end

          def color
            {
              "passed" => "green",
              "failed" => "red",
              "errored" => "gray",
              "canceled" => "gray",
            }.fetch(build[:state], "yellow")
          end

          def message_format
            (config[:format] rescue nil) || 'text'
          end

          def config
            build[:config][:notifications][:hipchat] rescue {}
          end
      end
    end
  end
end

