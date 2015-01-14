module ActionSubscriber
  class SubscriptionSet
    if ::RUBY_PLATFORM == "java"
      include ::ActionSubscriber::Subscriber::MarchHare
    else
      include ::ActionSubscriber::Subscriber::Bunny
    end

    attr_reader :connection, :routes

    def initialize(routes)
      @connection = ActionSubscriber::RabbitConnection.new_connection
      @routes = routes
    end

    def start
      routes.each do |route|
        channel = setup_channel(route)
        queue = setup_queue(route, channel)
        subscribe_to(route, queue)
      end
    end

    def stop
      connection.close
    end

  private

    def pool
      @pool ||= ::Lifeguard::InfiniteThreadpool.new(
        :pool_size => ::ActionSubscriber.config.threadpool_size
      )
    end

    def setup_queue(route, channel)
      exchange = channel.topic(route.exchange)
      queue = channel.queue(route.queue)
      queue.bind(exchange, :routing_key => route.routing_key)
      queue
    end
  end
end
