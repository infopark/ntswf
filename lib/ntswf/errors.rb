module Ntswf
  module Errors
    # @see Client#find
    NotFound = AWS::SimpleWorkflow::Errors::UnknownResourceFault

    # @see Client#start_execution
    AlreadyStarted = AWS::SimpleWorkflow::Errors::WorkflowExecutionAlreadyStartedFault
  end
end