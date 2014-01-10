require_relative 'worker'

module Ntswf
  # Interface for a worker executing tasks
  module ActivityWorker
    include Ntswf::Worker

    def process_activity_task
      announce("polling for activity task #{activity_task_list}")
      domain.activity_tasks.poll_for_single_task(activity_task_list) do |task|
        announce("got activity task #{task.activity_type.inspect} #{task.input}")
        begin
          if task.activity_type == activity_type
            yield task
          else
            raise "unknown activity type: #{task.activity_type.inspect}"
          end
        rescue => e
          notify(e, activity_type: task.activity_type.inspect, input: task.input)
          details = {
            error: e.message[0, 1000],
            exception: e.class.to_s[0, 1000],
          }
          task.fail!(details: details.to_json, reason: 'Exception')
        end
      end
    end
  end
end