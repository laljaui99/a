module Travis
  module Addons
    module GithubStatus

      # Adds a comment with a build notification to the pull-request the request
      # belongs to.
      class Task < Travis::Task
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

        ERROR_REASONS = {
          401 => :incorrect_auth,
          403 => :incorrect_auth_or_suspended_acct_or_rate_limited,
          404 => :repo_not_found_or_incorrect_auth,
          422 => :maximum_number_of_statuses,
        }

        def url
          "/repos/#{repository[:slug]}/statuses/#{sha}"
        end

        private

          def process(timeout)
            message = "type=github_status build=#{build[:id]} repo=#{repository[:slug]} state=#{state} commit=#{sha} tokens_count=#{tokens.size} installation_id=#{installation_id}"

            if !installation_id.nil? && process_via_github_app
              info("#{message} processed_with=github_apps")
              return
            end

            tokens.each do |username, token|
              if process_with_token(username, token)
                info("#{message} processed_with=user_token")
                return
              else
                error("type=github_status build=#{build[:id]} repo=#{repository[:slug]} error=not_updated commit=#{sha} username=#{username} url=#{GH.api_host + url} processed_with=user_token")
              end
            end
          end

          def tokens
            params.fetch(:tokens) { { '<legacy format>' => params[:token] } }
          end

          def process_with_token(username, token)
            resp = Travis::RemoteVCS::Repository.create_comment(repository[:github_id], token, status_payload)
            return true if resp.success?

            if [401, 403, 404, 422].include?(resp.status)
              error("type=github_status build=#{build[:id]} repo=#{repository[:slug]} state=#{state} commit=#{sha} username=#{username} response_status=#{e.info[:response_status]} reason=#{ERROR_REASONS.fetch(Integer(e.info[:response_status]))} processed_with=user_token body=#{e.info[:response_body]}")
              false
            else
              message = "type=github_status build=#{build[:id]} repo=#{repository[:slug]} error=not_updated commit=#{sha} url=#{GH.api_host + url} response_status=#{e.info[:response_status]} message=#{e.message} processed_with=user_token body=#{e.info[:response_body]}"
              error(message)
              raise message
            end
          end

          def process_with_token(username, token)
            authenticated(token) do
              GH.post(url, status_payload)
            end
          rescue GH::Error(:response_status => 401),
                 GH::Error(:response_status => 403),
                 GH::Error(:response_status => 404),
                 GH::Error(:response_status => 422) => e
            error("type=github_status build=#{build[:id]} repo=#{repository[:slug]} state=#{state} commit=#{sha} username=#{username} response_status=#{e.info[:response_status]} reason=#{ERROR_REASONS.fetch(Integer(e.info[:response_status]))} processed_with=user_token body=#{e.info[:response_body]}")
            nil
          rescue GH::Error => e
            message = "type=github_status build=#{build[:id]} repo=#{repository[:slug]} error=not_updated commit=#{sha} url=#{GH.api_host + url} response_status=#{e.info[:response_status]} message=#{e.message} processed_with=user_token body=#{e.info[:response_body]}"
            error(message)
            raise message
          end

          def process_via_github_app
            Travis::RemoteVCS::Repository.create_comment(token, status_payload.to_json)
            response = github_apps.post_with_app(url, status_payload.to_json)

            if response.success?
              info("type=github_status repo=#{repository[:slug]} response_status=#{response.status} processed_with=github_apps")
              return true
            end

            status_int = Integer(response.status)
            case status_int
            when 401, 403, 404, 422
              error("type=github_status build=#{build[:id]} repo=#{repository[:slug]} state=#{state} commit=#{sha} installation_id=#{installation_id} response_status=#{status_int} reason=#{ERROR_REASONS.fetch(status_int)} processed_with=github_apps body=#{response.body}")
              return nil
            else
              message = "type=github_status build=#{build[:id]} repo=#{repository[:slug]} error=not_updated commit=#{sha} url=#{GH.api_host + url} response_status=#{status_int} processed_with=github_apps body=#{response.body}"
              error(message)
              raise message
            end
          end

          def target_url
            with_utm("#{Travis.config.http_host}/#{repository[:slug]}/builds/#{build[:id]}", :github_status)
          end

          def status_payload
            {
              state: state,
              description: description,
              target_url: target_url,
              context: context
            }
          end

          def check_api_media_type
            'application/vnd.github.antiope-preview+json'
          end

          def github_apps
            @github_apps ||= Travis::GithubApps.new(
              installation_id,
              apps_id: Travis.config.github_apps.id,
              private_pem: Travis.config.github_apps.private_pem,
              redis: Travis.config.redis.to_h,
              accept_header: check_api_media_type,
              debug: debug?
            )
          end

          def installation_id
            params.fetch(:installation, nil)
          end

          def debug?
            Travis.config.github_apps.debug
          end

          def sha
            pull_request? ? request[:head_commit] : commit[:sha]
          end

          def context
            build_type = pull_request? ? "pr" : "push"
            "continuous-integration/travis-ci/#{build_type}"
          end

          def state
            STATES[build[:state]]
          end

          def description
            DESCRIPTIONS[state]
          end

          def authenticated(token, &block)
            GH.with(http_options(token), &block)
          end

          def http_options(token)
            super().merge(token: token, headers: headers, ssl: (Travis.config.github.ssl || {}).to_hash.compact)
          end

          def headers
            {
              "Accept" => "application/vnd.github.v3+json"
            }
          end
      end
    end
  end
end
