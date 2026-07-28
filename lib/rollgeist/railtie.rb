# frozen_string_literal: true

module Rollgeist
  class Railtie < Rails::Railtie
    initializer "rollgeist.executor" do |application|
      ExecutionState.install!(application.executor)
    end

    config.to_prepare do
      Rollgeist.install_global_id_patch!
    end
  end
end
