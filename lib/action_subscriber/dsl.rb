module ActionSubscriber
  module DSL
    def at_least_once!
      @_acknowledge_messages = true
      @_at_least_once = true
    end

    def at_least_once?
      !!@_at_least_once
    end

    def at_most_once!(ack_every_n_messages = 1)
      @_acknowledge_messages = true
      @_at_most_once = true
      @_ack_every_n_messages = ack_every_n_messages
    end

    def at_most_once?
      !!@_at_most_once
    end

    def acknowledge_messages?
      !!@_acknowledge_messages
    end

    def around_filter(filter_method)
      around_filters << filter_method unless around_filters.include?(filter_method)
      around_filters
    end

    def around_filters
      @_around_filters ||= []
    end

    # Explicitly set the name of the exchange
    #
    def exchange_names(*names)
      @_exchange_names ||= []
      @_exchange_names += names.flatten.map(&:to_s)

      if @_exchange_names.empty?
        return [ ::ActionSubscriber.config.default_exchange ]
      else
        return @_exchange_names.compact.uniq
      end
    end
    alias_method :exchange, :exchange_names

    def manual_acknowledgement!
      @_acknowledge_messages = true
      @_manual_acknowedgement = true
    end

    def manual_acknowledgement?
      !!@_manual_acknowedgement
    end

    def ack_every_n_messages
      @_ack_every_n_messages || 1
    end

    def no_acknowledgement!
      @_acknowledge_messages = false
    end

    # Explicitly set the name of a queue for the given method route
    #
    # Ex.
    #   queue_for :created, "derp.derp"
    #   queue_for :updated, "foo.bar"
    #
    def queue_for(method, queue_name)
      @_queue_names ||= {}
      @_queue_names[method] = queue_name
    end

    def queue_names
      @_queue_names ||= {}
    end

    def remote_application_name(name = nil)
      @_remote_application_name = name if name
      @_remote_application_name
    end
    alias_method :publisher, :remote_application_name

    # Explicitly set the whole routing key to use for a given method route.
    #
    def routing_key_for(method, routing_key_name)
      @_routing_key_names ||= {}
      @_routing_key_names[method] = routing_key_name
    end

    def routing_key_names
      @_routing_key_names ||= {}
    end

    def _run_action_with_filters(env, action)
      subscriber_instance = self.new(env)
      final_block = Proc.new { subscriber_instance.public_send(action) }

      first_proc = around_filters.reverse.reduce(final_block) do |block, filter|
        Proc.new { subscriber_instance.send(filter, &block) }
      end
      first_proc.call
    end

    def _run_action_at_most_once_with_filters(env, action)
      processed_acknowledgement = false
      rejected_message = false
      processed_acknowledgement = env.acknowledge

      _run_action_with_filters(env, action)
    ensure
      rejected_message = env.reject if !processed_acknowledgement

      if !rejected_message && !processed_acknowledgement
        $stdout << <<-UNREJECTABLE
          CANNOT ACKNOWLEDGE OR REJECT THE MESSAGE

          This is a exceptional state for ActionSubscriber to enter and puts the current
          Process in the position of "I can't get new work from RabbitMQ, but also
          can't acknowledge or reject the work that I currently have" ... While rare
          this state can happen.

          Instead of continuing to try to process the message ActionSubscriber is
          sending a Kill signal to the current running process to gracefully shutdown
          so that the RabbitMQ server will purge any outstanding acknowledgements. If
          you are running a process monitoring tool (like Upstart) the Subscriber
          process will be restarted and be able to take on new work.

          ** Running a process monitoring tool like Upstart is recommended for this reason **
        UNREJECTABLE

        Process.kill(:TERM, Process.pid)
      end
    end

    def _run_action_at_most_once_multiple_with_filters(env, action)
      processed_acknowledgement = false
      rejected_message = false
      if env.delivery_tag % ack_every_n_messages == 0 # tags are monotonically increasing integers
        processed_acknowledgement = env.acknowledge(true)
      else
        processed_acknowledgement = true # we are not acknowledging on this message and will wait for the offset to acknowledge
      end

      _run_action_with_filters(env, action)
    ensure
      rejected_message = env.reject if !processed_acknowledgement

      if !rejected_message && !processed_acknowledgement
        $stdout << <<-UNREJECTABLE
          CANNOT ACKNOWLEDGE OR REJECT THE MESSAGE

          This is a exceptional state for ActionSubscriber to enter and puts the current
          Process in the position of "I can't get new work from RabbitMQ, but also
          can't acknowledge or reject the work that I currently have" ... While rare
          this state can happen.

          Instead of continuing to try to process the message ActionSubscriber is
          sending a Kill signal to the current running process to gracefully shutdown
          so that the RabbitMQ server will purge any outstanding acknowledgements. If
          you are running a process monitoring tool (like Upstart) the Subscriber
          process will be restarted and be able to take on new work.

          ** Running a process monitoring tool like Upstart is recommended for this reason **
        UNREJECTABLE

        Process.kill(:TERM, Process.pid)
      end
    end

    def _run_action_at_least_once_with_filters(env, action)
      processed_acknowledgement = false
      rejected_message = false

      _run_action_with_filters(env, action)

      processed_acknowledgement = env.acknowledge
    rescue
      ::ActionSubscriber::MessageRetry.redeliver_message_with_backoff(env)
      processed_acknowledgement = env.acknowledge

      raise
    ensure
      rejected_message = env.reject if !processed_acknowledgement

      if !rejected_message && !processed_acknowledgement
        $stdout << <<-UNREJECTABLE
          CANNOT ACKNOWLEDGE OR REJECT THE MESSAGE

          This is a exceptional state for ActionSubscriber to enter and puts the current
          Process in the position of "I can't get new work from RabbitMQ, but also
          can't acknowledge or reject the work that I currently have" ... While rare
          this state can happen.

          Instead of continuing to try to process the message ActionSubscriber is
          sending a Kill signal to the current running process to gracefully shutdown
          so that the RabbitMQ server will purge any outstanding acknowledgements. If
          you are running a process monitoring tool (like Upstart) the Subscriber
          process will be restarted and be able to take on new work.

          ** Running a process monitoring tool like Upstart is recommended for this reason **
        UNREJECTABLE

        Process.kill(:TERM, Process.pid)
      end
    end

    def run_action_with_filters(env, action)
      case
      when at_least_once?
        _run_action_at_least_once_with_filters(env, action)
      when at_most_once? && ack_every_n_messages <= 1 # Acknowledging every single message
        _run_action_at_most_once_with_filters(env, action)
      when at_most_once? && ack_every_n_messages > 1 # Acknowledging messages in offset groups (every 10 messages or whatever the offset is)
        _run_action_at_most_once_multiple_with_filters(env, action)
      else
        _run_action_with_filters(env, action)
      end
    end
  end
end
