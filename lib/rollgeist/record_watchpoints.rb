# frozen_string_literal: true

module Rollgeist
  module RecordWatchpoints
    INSTALLED_IVAR = :@__rollgeist_watchpoints
    SERIALIZATION_BIT = 1
    GLOBAL_ID_BIT = 2

    SERIALIZATION_ALIAS = :__rollgeist_original_serializable_hash
    SERIALIZATION_STATE = :@__rollgeist_serialization_visibility
    GLOBAL_ID_ALIAS = :__rollgeist_original_to_global_id
    GLOBAL_ID_STATE = :@__rollgeist_global_id_visibility
    INHERITED = :inherited

    class << self
      def install!(record)
        return if record.instance_variable_defined?(INSTALLED_IVAR)

        mask = install_serialization(record)
        mask |= install_global_id(record)
        record.instance_variable_set(INSTALLED_IVAR, mask)
      rescue StandardError
        uninstall_mask(record, mask.to_i)
        raise
      end

      def uninstall!(record)
        return unless record.instance_variable_defined?(INSTALLED_IVAR)

        mask = record.instance_variable_get(INSTALLED_IVAR)
        uninstall_mask(record, mask)
        record.remove_instance_variable(INSTALLED_IVAR)
      end

      private

      def install_serialization(record)
        return 0 unless record.respond_to?(:serializable_hash, true)

        install_method(
          record,
          :serializable_hash,
          SERIALIZATION_ALIAS,
          SERIALIZATION_STATE,
          :serialization
        )
        SERIALIZATION_BIT
      end

      def install_global_id(record)
        return 0 unless record.respond_to?(:to_global_id, true)

        install_method(
          record,
          :to_global_id,
          GLOBAL_ID_ALIAS,
          GLOBAL_ID_STATE,
          :global_id
        )
        GLOBAL_ID_BIT
      end

      def install_method(record, method_name, alias_name, state_ivar, watchpoint)
        singleton_class = record.singleton_class
        ensure_alias_available!(singleton_class, alias_name)
        original_visibility = own_visibility(singleton_class, method_name)
        inherited_visibility = visibility(singleton_class, method_name)

        preserve_original(singleton_class, method_name, alias_name) if original_visibility
        singleton_class.instance_variable_set(state_ivar, original_visibility || INHERITED)
        define_watchpoint(singleton_class, method_name, alias_name, state_ivar, watchpoint)
        singleton_class.send(inherited_visibility, method_name)
      end

      def define_watchpoint(singleton_class, method_name, alias_name, state_ivar, watchpoint)
        singleton_class.define_method(method_name) do |*args, **kwargs, &block|
          Rollgeist::Notifier.notify(self, watchpoint) if defined?(@__rollgeist_mark)
          state = self.singleton_class.instance_variable_get(state_ivar)

          if state == INHERITED
            kwargs.empty? ? super(*args, &block) : super(*args, **kwargs, &block)
          elsif kwargs.empty?
            __send__(alias_name, *args, &block)
          else
            __send__(alias_name, *args, **kwargs, &block)
          end
        end
      end

      def preserve_original(singleton_class, method_name, alias_name)
        singleton_class.alias_method(alias_name, method_name)
        singleton_class.send(:private, alias_name)
      end

      def uninstall_mask(record, mask)
        singleton_class = record.singleton_class
        uninstall_method(
          singleton_class,
          :to_global_id,
          GLOBAL_ID_ALIAS,
          GLOBAL_ID_STATE
        ) if (mask & GLOBAL_ID_BIT).positive?
        uninstall_method(
          singleton_class,
          :serializable_hash,
          SERIALIZATION_ALIAS,
          SERIALIZATION_STATE
        ) if (mask & SERIALIZATION_BIT).positive?
      end

      def uninstall_method(singleton_class, method_name, alias_name, state_ivar)
        original_visibility = singleton_class.instance_variable_get(state_ivar)
        singleton_class.remove_method(method_name)

        unless original_visibility == INHERITED
          singleton_class.alias_method(method_name, alias_name)
          singleton_class.send(original_visibility, method_name)
          singleton_class.remove_method(alias_name)
        end

        singleton_class.remove_instance_variable(state_ivar)
      end

      def ensure_alias_available!(singleton_class, alias_name)
        return unless own_visibility(singleton_class, alias_name)

        raise Error, "record already defines reserved method #{alias_name}"
      end

      def own_visibility(singleton_class, method_name)
        return :public if singleton_class.public_instance_methods(false).include?(method_name)
        return :protected if singleton_class.protected_instance_methods(false).include?(method_name)
        return :private if singleton_class.private_instance_methods(false).include?(method_name)
      end

      def visibility(singleton_class, method_name)
        return :public if singleton_class.public_method_defined?(method_name)
        return :protected if singleton_class.protected_method_defined?(method_name)
        return :private if singleton_class.private_method_defined?(method_name)

        raise Error, "record does not define #{method_name}"
      end
    end
  end
end
