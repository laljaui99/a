require "gh"
require "travis/notifications/notifier"

module Travis
  module Notifications
    module Notifiers
      # Adds a comment with a build notification to the pull-request the request
      # belongs to.
      class GitHubStatus < Notifier
        STATES = {
          'created'  => 'pending',
          'queued'   => 'pending',
          'started'  => 'pending',
          'passed'   => 'success',
          'failed'   => 'failure',
          'errored'  => 'error',
          'canceled' => 'error',
        }

        DESCRIPTIONS = {
          'pending' => 'The Travis CI build is in progress',
          'success' => 'The Travis CI build passed',
          'failure' => 'The Travis CI build failed',
          'error'   => 'The Travis CI build could not complete due to an error',
        }

        def url
          "/repos/#{repository[:slug]}/statuses/#{sha}"
        end

        private

          def process
            info("Update commit status on #{url} to #{state}")
            authenticated do
              GH.post(url, :state => state, :description => description, :target_url => target_url)
            end
          rescue GH::Error => e
            error "Could not update the PR status on #{GH.api_host + url} (#{e.message})."
          end

          def target_url
            "#{Travis.config.http_host}/#{repository[:slug]}/builds/#{build[:id]}"
          end

          def sha
            pull_request? ? request[:head_commit] : commit[:sha]
          end

          def state
            STATES[build[:state]]
          end

          def description
            DESCRIPTIONS[state]
          end

          def authenticated(&block)
            GH.with(http_options, &block)
          end

          def http_options
            super.merge(token: params[:token])
          end
      end
    end
  end
end

