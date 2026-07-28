# frozen_string_literal: true

module Rollgeist
  class Railtie < Rails::Railtie
    initializer "rollgeist.executor" do |application|
      ExecutionState.install!(application.executor)
    end
  end
end
