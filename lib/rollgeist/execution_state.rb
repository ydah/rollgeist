# frozen_string_literal: true

require "thread"

module Rollgeist
  module ExecutionState
    COUNTER_KEY = :__rollgeist_execution_counter
    FALLBACK_WINDOW_SECONDS = 60
    Counter = Struct.new(:reported, :suppressed, :started_at, keyword_init: true)
    Decision = Struct.new(:allowed, :suppressed_to_flush, keyword_init: true)

    class << self
      def install!(executor = ActiveSupport::Executor)
        @installed_executors ||= {}
        return if @installed_executors[executor.object_id]

        executor.to_run { Rollgeist::ExecutionState.start! }
        executor.to_complete { Rollgeist::ExecutionState.complete! }
        @installed_executors[executor.object_id] = true
      end

      def start!
        ActiveSupport::IsolatedExecutionState[COUNTER_KEY] = new_counter
      end

      def complete!
        counter = ActiveSupport::IsolatedExecutionState[COUNTER_KEY]
        ActiveSupport::IsolatedExecutionState[COUNTER_KEY] = nil
        Notifier.report_suppressed(counter.suppressed) if counter&.suppressed.to_i.positive?
      end

      def claim(limit)
        counter = ActiveSupport::IsolatedExecutionState[COUNTER_KEY]
        return claim_from(counter, limit) if counter

        fallback_claim(limit)
      end

      def reset!
        ActiveSupport::IsolatedExecutionState[COUNTER_KEY] = nil
        fallback_mutex.synchronize { @fallback_counter = new_counter }
      end

      private

      def claim_from(counter, limit)
        if counter.reported < limit
          counter.reported += 1
          Decision.new(allowed: true)
        else
          counter.suppressed += 1
          Decision.new(allowed: false)
        end
      end

      def fallback_claim(limit)
        fallback_mutex.synchronize do
          now = monotonic_time
          counter = fallback_counter
          suppressed_to_flush = nil

          if now - counter.started_at >= FALLBACK_WINDOW_SECONDS
            suppressed_to_flush = counter.suppressed if counter.suppressed.positive?
            counter = @fallback_counter = new_counter(now)
          end

          decision = claim_from(counter, limit)
          decision.suppressed_to_flush = suppressed_to_flush
          decision
        end
      end

      def fallback_counter
        @fallback_counter ||= new_counter
      end

      def fallback_mutex
        @fallback_mutex ||= Mutex.new
      end

      def new_counter(started_at = monotonic_time)
        Counter.new(reported: 0, suppressed: 0, started_at: started_at)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
