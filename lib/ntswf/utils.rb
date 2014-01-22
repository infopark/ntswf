require_relative 'base'

module Ntswf
  module Utils
    include Ntswf::Base

    def create_domain(description)
      swf.domains.create(@config.domain, 3, description: description)
    end

    def register_workflow_type
      domain.workflow_types.register(workflow_name, workflow_version)
    end

    def register_activity_type
      domain.activity_types.register(activity_name, workflow_version)
    end
  end
end