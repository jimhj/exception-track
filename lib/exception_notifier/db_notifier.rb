# frozen_string_literal: true

module ExceptionNotifier
  class DbNotifier < ExceptionNotifier::BaseNotifier
    def initialize(opts = {})
      super(opts)
    end

    def call(exception, opts = {})
      return unless ExceptionTrack.config.enabled_env?(Rails.env)

      # send the notification
      title = exception.message || "None"
      messages = []

      ActiveSupport::Notifications.instrument("track.exception_track", title: title) do
        messages << headers_for_env(opts[:env])
        messages << ""
        messages << "--------------------------------------------------"
        messages << ""
        messages << exception.inspect
        unless exception.backtrace.blank?
          messages << "\n"
          messages << exception.backtrace
        end

        Rails.logger.silence do
          ExceptionTrack::Log.create(title: title[0, 200], body: messages.join("\n"))
        end
      end
    rescue => e
      errs = []
      errs << "-- [ExceptionTrack] create error ---------------------------"
      errs << e.message.indent(2)
      errs << ""
      errs << "-- Exception detail ----------------------------------------"
      errs << title.indent(2)
      errs << ""
      errs << messages.join("\n").indent(2)
      Rails.logger.error errs.join("\n")
    end

    # Log Request headers from Rack env
    def headers_for_env(env)
      return "" if env.blank?

      parameters = filter_parameters(env)

      headers = []
      headers << "Method:      #{env["REQUEST_METHOD"]}"
      headers << "URL:         #{env["REQUEST_URI"]}"
      headers << "Parameters:\n#{pretty_hash(parameters.except(:controller, :action), 13)}" if env["REQUEST_METHOD"].downcase != "get"
      headers << "Controller:  #{parameters["controller"]}##{parameters["action"]}"
      headers << "RequestId:   #{env["action_dispatch.request_id"]}"
      headers << "User-Agent:  #{env["HTTP_USER_AGENT"]}"
      headers << "Remote IP:   #{env["REMOTE_ADDR"] == '127.0.0.1' ? env['HTTP_X_REAL_IP'] : env["REMOTE_ADDR"]}"
      headers << "Language:    #{env["HTTP_ACCEPT_LANGUAGE"]}"
      headers << "Server:      #{Socket.gethostname}"
      headers << "Process:     #{$PROCESS_ID}"

      headers.join("\n")
    end

    def filter_parameters(env)
      parameters = env["action_dispatch.request.parameters"] || {}
      parameter_filter = ActiveSupport::ParameterFilter.new(env["action_dispatch.parameter_filter"] || [])
      parameter_filter.filter(parameters)
    rescue => e
      Rails.logger.error "filter_parameters error: #{e.inspect}"
      parameters
    end

    def pretty_hash(params, indent = 0)
      json = JSON.pretty_generate(params)
      json.indent(indent)
    end
  end
end
