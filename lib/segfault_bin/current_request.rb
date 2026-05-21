# frozen_string_literal: true

require "active_support"
require "active_support/code_generator"
require "active_support/current_attributes"

module SegfaultBin
  class CurrentRequest < ActiveSupport::CurrentAttributes
    attribute :env, :user, :n_plus_one_tracker, :slow_query_tracker, :transaction

    def self.set_user(user_data)
      return unless user_data.is_a?(Hash)
      self.user = user_data.slice(:id, :email, :username)
    end
  end
end
