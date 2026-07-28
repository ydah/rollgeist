# frozen_string_literal: true

module Rollgeist
  module Patches
    module GlobalId
      def to_global_id(...)
        if defined?(@__rollgeist_mark)
          Rollgeist::Notifier.notify(self, :global_id)
        end

        super
      end
    end
  end
end
