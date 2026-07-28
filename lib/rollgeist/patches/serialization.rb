# frozen_string_literal: true

module Rollgeist
  module Patches
    module Serialization
      def serializable_hash(options = nil)
        if defined?(@__rollgeist_mark)
          Rollgeist::Notifier.notify(self, :serialization)
        end

        super(options)
      end
    end
  end
end
