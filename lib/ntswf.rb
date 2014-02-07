module Ntswf
  # @!method self.create(*modules, config)
  # Shortcut for creating an {Instance}
  # @example
  #     Ntswf.create(:client, :activity_worker, unit: "my_worker")
  # @param modules (see Instance#initialize)
  # @param config (see Instance#initialize)
  # @option config (see Base#configure)
  def self.create(*args)
    Ntswf::Instance.new(*args)
  end

  DEFAULT_MODULES = %w(
    ActivityWorker
    Client
    DecisionWorker
    Utils
  )

  AUTOLOAD = DEFAULT_MODULES + %w(
    Instance
  )

  AUTOLOAD.each { |c| autoload c.to_sym, "ntswf/#{c.gsub(/.(?=[A-Z])/, '\0_').downcase}.rb" }
end