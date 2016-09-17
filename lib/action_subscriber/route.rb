module ActionSubscriber
  class Route
    attr_reader :acknowledgements,
                :action,
                :durable,
                :exchange,
                :prefetch,
                :queue,
                :routing_key,
                :subscriber,
                :threadpool,
                :middleware

    def initialize(attributes)
      @acknowledgements = attributes.fetch(:acknowledgements)
      @action = attributes.fetch(:action)
      @durable = attributes.fetch(:durable)
      @exchange = attributes.fetch(:exchange).to_s
      @prefetch = attributes.fetch(:prefetch) { ::ActionSubscriber.config.prefetch }
      @queue = attributes.fetch(:queue)
      @routing_key = attributes.fetch(:routing_key)
      @subscriber = attributes.fetch(:subscriber)
      @threadpool = attributes.fetch(:threadpool) { ::ActionSubscriber::Threadpool.pool(:default) }
      @middleware = attributes.fetch(:middleware) { ::ActionSubscriber.config.middleware.forked }
    end

    def acknowledgements?
      @acknowledgements
    end

    def queue_subscription_options
      { :manual_ack => acknowledgements? }
    end

    delegate :use, :to => :middleware
    delegate :insert, :to => :middleware
    delegate :insert_after, :to => :middleware
    delegate :insert_before, :to => :middleware
  end
end
