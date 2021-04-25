require "bundler/setup"
require "slack-notifier"
require "k8s-client"
require "concurrent"
require 'logger'
require 'yaml'
require 'mail'

require_relative "k8s_client"

Mail.defaults do
  delivery_method :smtp, address: ENV["EMAIL_SMTP_HOST"], port: ENV["EMAIL_SMTP_PORT"], user_name: ENV["EMAIL_SMTP_USERNAME"], password: ENV["EMAIL_SMTP_PASSWORD"]
end

class Controller
  TIMEOUT = 3600*24*365

  def initialize
    @velero_namespace = ENV.fetch("VELERO_NAMESPACE", "velero")

    @slack = Slack::Notifier.new ENV["SLACK_WEBHOOK"] do
      defaults channel: ENV["SLACK_CHANNEL"], username: ENV.fetch("SLACK_USERNAME", "Velero")
    end

    @k8s_client = Kubernetes::Client.new
    @logger = Logger.new(STDOUT)
  end

  def start
    $stdout.sync = true

    t1 = Thread.new do
      watch_resources :backups
    end

    t2 = Thread.new do
      watch_resources :restores
    end

    t1.join
    t2.join
  end

  private

  attr_reader :velero_namespace, :slack, :k8s_client, :logger

  def notify(event)
    phase = event.resource.status.phase

    return if phase.empty? || phase == "Deleting"

    # msg = "#{event.resource.kind} #{phase} #{event.resource.metadata.name}"
    msg = "#{event.resource.kind} #{phase}"

    logger.info msg

    if ENV.fetch("ENABLE_SLACK_NOTIFICATIONS", "false") =~ /true/i
      at = if phase =~ /failed/i
             [:here]
           else
             []
           end

      attachment = {
        fallback: msg,
        text: msg,
        color: phase =~ /failed/i ? "danger" : "good"
      }

      begin
        slack.post at: at, attachments: [attachment]
      rescue => e
        logger.error "Something went wrong with the Slack notification: #{e.message}"
      end
    end

    if ENV.fetch("ENABLE_EMAIL_NOTIFICATIONS", "false") =~ /true/i
      begin
        mail = Mail.new do
          from    "#{ENV['EMAIL_FROM_SENDER_NAME']} <#{ENV["EMAIL_FROM_ADDRESS"]}>"
          to      ENV["EMAIL_TO_ADDRESS"]
          subject "#{ENV.fetch("EMAIL_SUBJECT_PREFIX", "[Velero]")} #{msg}"
          body    "Run `velero #{event.resource.kind.downcase} describe #{event.resource.metadata.name} --details` for more information."
        end

        mail.deliver!
      rescue => e
        logger.error "Something went wrong with the email notification: #{e.message}"
      end
    end
  end

  def watch_resources(resource_type)
    resource_version = k8s_client.api("velero.io/v1").resource(resource_type.to_s, namespace: velero_namespace).meta_list.metadata.resourceVersion

    begin
      logger.info "Watching #{resource_type}..."

      k8s_client.api("velero.io/v1").resource(resource_type.to_s, namespace: velero_namespace).watch(timeout: TIMEOUT, resourceVersion: resource_version) do |event|
        resource_version = event.resource.metadata.resourceVersion
        notify event
      end

    rescue EOFError, Excon::Error::Socket
      logger.info "Reconnecting to API..."
      retry
    end
  end
end
