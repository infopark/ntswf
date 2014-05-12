module Ntswf
  module Errors
    # @see Client#start_execution
    AlreadyStarted = AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault

    # @see Base#configure
    InvalidArgument = Class.new(RuntimeError)

    # @see Client#find
    NotFound = AWS::SimpleWorkflow::Errors::UnknownResourceFault
  end
end