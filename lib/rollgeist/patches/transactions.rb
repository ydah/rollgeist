# frozen_string_literal: true

module Rollgeist
  module Patches
    module Transactions
      def committed!(*args, **kwargs)
        result = super
        Rollgeist.clear_record_state!(self)
        result
      end

      def rolledback!(*args, **kwargs)
        snapshot = Rollgeist.rollback_snapshot(self)
        result = super

        if snapshot
          Rollgeist.attach_mark!(self, snapshot)
        else
          Rollgeist.clear_transaction_write_state!(self)
        end

        result
      end
    end
  end
end
