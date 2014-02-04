module Ntswf
  class Instance
    # @!method initialize(*modules, config)
    # @param modules (DEFAULT_MODULES)
    #   A list of module names to include
    # @param config (see Base#configure)
    # @option config (see Base#configure)
    def initialize(*args)
      symbols = args.grep Symbol
      configs = args - symbols
      instance_exec do
        module_names = symbols.map(&:to_s).map { |s| s.gsub(/(^|_)(.)/) { $2.upcase } }
        module_names = DEFAULT_MODULES if module_names.empty?
        module_names.each { |module_name| extend Ntswf::const_get module_name }
      end
      configure(configs.last || {})
    end
  end
end