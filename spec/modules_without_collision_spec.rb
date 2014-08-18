describe Ntswf::Instance, "full featured" do
  subject {Ntswf::Instance.new}

  def own_instance_methods(mod)
    method_retrievers = [:instance_methods, :private_instance_methods]
    methods = []
    method_retrievers.each do |method_retriever|
      methods.concat(mod.send(method_retriever))
    end
    mod.ancestors.each do |a|
      a == mod and next
      method_retrievers.each do |method_retriever|
        methods -= a.send(method_retriever)
      end
    end
    methods
  end

  it "is not composed of colliding methods" do
    # out of scope: non-instance methods considered
    # out of scope: methods calling super may not be colliding methods
    ntswf_modules = (class << subject; included_modules; end).select {|a| a.name[0, 7] == "Ntswf::"}
    ntswf_modules.each do |left|
      ntswf_modules.each do |right|
        left == right and next
        unless (left < right || right < left)
          expect(own_instance_methods(left) & own_instance_methods(right)).to eq([])
        end
      end
    end
  end
end
