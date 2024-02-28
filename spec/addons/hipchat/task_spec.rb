require 'spec_helper'
require 'rack'
require 'securerandom'
require 'open-uri'

describe Travis::Addons::Hipchat::Task do
  include Travis::Testing::Stubs

  let(:subject) { Travis::Addons::Hipchat::Task }
  let(:http)    { Faraday::Adapter::Test::Stubs.new }
  let(:client)  { Faraday.new { |f| f.request :url_encoded; f.adapter :test, http } }
  let(:payload) { Marshal.load(Marshal.dump(TASK_PAYLOAD)) }
  let(:room_1_token) { SecureRandom.hex 15}
  let(:room_2_token) { SecureRandom.hex 15}
  let(:room_3_token_v2) { SecureRandom.hex 20}
  let(:io) { StringIO.new }

  before do
    Travis.logger = Logger.new(io)
    subject.any_instance.stubs(:http).returns(client)
  end

  def run(targets)
    subject.new(payload, targets: targets).run
  end

  context "with default hipchat server" do
    it "skips sending notifications to #{Travis::Addons::Hipchat::HttpHelper::HIPCHAT_DEFAULT_HOST}" do
      Travis.logger.expects(:info).with {|str| str =~ /skipping hipchat notification/i}
      client.expects(:post).never
      run(['targets'])
      http.verify_stubbed_calls
    end
  end

  context "with private server" do
    let(:room1) { 'room_1' }
    let(:room2) { 'room_2' }
    let(:private_server) { 'hipchat.example.com' }

    it "sends hipchat notifications to the given targets" do
      targets = ["#{room_1_token}@#{private_server}/room_1", "#{room_2_token}@#{private_server}/room_2", "#{room_3_token_v2}@#{private_server}/[foo]"]
      message = [
        'svenfuchs/minimal#2 (master - 62aae5f : Sven Fuchs): the build has passed',
        'Change view: https://github.com/svenfuchs/minimal/compare/master...develop',
        'Build details: https://travis-ci.org/svenfuchs/minimal/builds/1?utm_source=hipchat&utm_medium=notification'
      ]

      expect_hipchat('room_1', room_1_token, message, {}, private_server)
      expect_hipchat('room_2', room_2_token, message, {}, private_server)
      expect_hipchat_v2('[foo]', room_3_token_v2, message, {}, private_server)

      run(targets)
      http.verify_stubbed_calls
    end

    it 'using a custom template' do
      targets  = ["#{room_1_token}@#{private_server}/room_1"]
      template = ['%{repository}', '%{commit}']
      messages = ['svenfuchs/minimal', '62aae5f']

      payload['build']['config']['notifications'] = { hipchat: { template: template } }
      expect_hipchat('room_1', room_1_token, messages, {}, private_server)

      run(targets)
      http.verify_stubbed_calls
    end

    it 'sends the notify option for v2 if included' do
      targets = ["#{room_1_token}@#{private_server}/room_1", "#{room_3_token_v2}@#{private_server}/[foo]"]
      message = [
        'svenfuchs/minimal#2 (master - 62aae5f : Sven Fuchs): the build has passed',
        'Change view: https://github.com/svenfuchs/minimal/compare/master...develop',
        'Build details: https://travis-ci.org/svenfuchs/minimal/builds/1?utm_source=hipchat&utm_medium=notification'
      ]

      payload['build']['config']['notifications'] = { hipchat: { notify: true } }
      expect_hipchat('room_1', room_1_token, message, {}, private_server)
      expect_hipchat_v2('[foo]', room_3_token_v2, message, { 'notify' => true }, private_server)

      run(targets)
      http.verify_stubbed_calls
    end

    it "sends HTML notifications if requested" do
      targets = ["#{room_1_token}@#{private_server}/room_1"]
      template = ['<a href="%{build_url}">Details</a>']
      messages = ['<a href="https://travis-ci.org/svenfuchs/minimal/builds/1?utm_source=hipchat&utm_medium=notification">Details</a>']

      payload['build']['config']['notifications'] = { hipchat: { template: template, format: 'html' } }
      expect_hipchat('room_1', room_1_token, messages, {'message_format' => 'html'}, private_server)

      run(targets)
      http.verify_stubbed_calls
    end

    it 'works with a list as HipChat configuration' do
      targets  = ["#{room_1_token}@#{private_server}/room_1"]
      template = ['%{repository}', '%{commit}']
      messages = [
        'svenfuchs/minimal#2 (master - 62aae5f : Sven Fuchs): the build has passed',
        'Change view: https://github.com/svenfuchs/minimal/compare/master...develop',
        'Build details: https://travis-ci.org/svenfuchs/minimal/builds/1?utm_source=hipchat&utm_medium=notification'
      ]

      payload['build']['config']['notifications'] = { hipchat: [] }
      expect_hipchat('room_1', room_1_token, messages, {}, private_server)

      run(targets)
      http.verify_stubbed_calls
    end

    it "sends red messages for errored builds" do
      targets = ["#{room_1_token}@#{private_server}/room_1"]
      messages = [
        "svenfuchs/minimal#2 (master - 62aae5f : Sven Fuchs): the build has errored",
        "Change view: https://github.com/svenfuchs/minimal/compare/master...develop",
        "Build details: https://travis-ci.org/svenfuchs/minimal/builds/1?utm_source=hipchat&utm_medium=notification"
      ]

      payload["build"]["state"] = "errored"
      expect_hipchat("room_1", room_1_token, messages, {"color" => "red"}, private_server)

      run(targets)
      http.verify_stubbed_calls
    end

    describe "handling errors" do
      it "ignores an empty targets list" do
        expect {
          run(["#{SecureRandom.hex 50}@room_1"])
        }.to_not raise_error
      end
    end
  end

  def expect_hipchat(room_id, token, lines, extra_body={}, server='api.hipchat.com')
    Array(lines).each do |line|
      body = { 'room_id' => room_id, 'from' => 'Travis CI', 'message' => line, 'color' => 'green', 'message_format' => 'text' }.merge(extra_body)
      http.post("v1/rooms/message?format=json&auth_token=#{token}") do |env|
        expect(env[:url].host).to eq(server)
        expect(Rack::Utils.parse_query(env[:body])).to eq(body)
        [200, {"Content-Type" => "application/json"}, "{}"]
      end
    end
  end

  def expect_hipchat_v2(room_id, token, lines, extra_body={}, server='api.hipchat.com')
    Array(lines).each do |line|
      body = { 'message' => line, 'color' => 'green', 'message_format' => 'text', 'notify' => false }.merge(extra_body).to_json
      http.post("https://#{server}/v2/room/#{URI::Parser.new.escape(room_id, Travis::Addons::Hipchat::HttpHelper::UNSAFE_URL_CHARS)}/notification?auth_token=#{token}") do |env|
        expect(env[:request_headers]['Content-Type']).to eq('application/json')
        expect(env[:body]).to eq(body)
        [200, {"Content-Type" => "application/json"}, "{}"]
      end
    end
  end

end
