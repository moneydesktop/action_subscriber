module ActionSubscriber
  class Route
    attr_reader :acknowledgements,
                :action,
                :durable, 
                :exchange,
                :exchange_durable,
                :prefetch,
                :queue,
                :routing_key,
                :subscriber,
                :threadpool

    def initialize(attributes)
      @acknowledgements = attributes.fetch(:acknowledgements)
      @action = attributes.fetch(:action)
      @durable = attributes.fetch(:durable)
      @exchange = attributes.fetch(:exchange).to_s
      @exchange_durable = attributes.fetch(:exchange_durable)
      @prefetch = attributes.fetch(:prefetch) { ::ActionSubscriber.config.prefetch }
      @queue = attributes.fetch(:queue)
      @routing_key = attributes.fetch(:routing_key)
      @subscriber = attributes.fetch(:subscriber)
      @threadpool = attributes.fetch(:threadpool) { ::ActionSubscriber::Threadpool.pool(:default) }
    end

    def acknowledgements?
      @acknowledgements
    end

    def queue_subscription_options
      { :manual_ack => acknowledgements? }
    end
  end
end
