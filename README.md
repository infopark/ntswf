NTSWF
=====

Not That Simple Workflow - A layer around AWS SWF

Common denominator of our [infopark](http://infopark.com/) internal services using
AWS Simple Workflow.

[![Gem Version](https://badge.fury.io/rb/ntswf.png)](http://badge.fury.io/rb/ntswf)
[![Code Climate](https://codeclimate.com/github/infopark/ntswf.png)](https://codeclimate.com/github/infopark/ntswf)
[![Dependency Status](https://gemnasium.com/infopark/ntswf.png)](https://gemnasium.com/infopark/ntswf)

Usage
-----
### Gemfile

    gem 'ntswf', '~> 1.0'

### Client
```
class WorkflowClient
  include Ntswf::Client

  def enqueue!
    start_execution(
      execution_id: 'my_singleton_task',
      name: 'my_worker_name',
      params: {my: :param},
      unit: 'my_worker',
    )
  end
end

config = {domain: 'my_domain', unit: 'my_app'} # ...
WorkflowClient.new(config).enqueue!
```
See {Ntswf::Base#initialize} for configuration options.

### Decision worker
```
class Decider
  include Ntswf::DecisionWorker
end

config = {domain: 'my_domain', unit: 'my_app'} # ...
loop { Decider.new(config).process_decision_task }
```

### Activity worker
```
class Worker
  include Ntswf::ActivityWorker

  def process_activity_task
    super do |task|
      options = parse_input(task.input)
      # ...
      task.complete!(result: 'OK')
    end
  end
end

config = {domain: 'my_domain', unit: 'my_worker'} # ...
loop { Worker.new(config).process_activity_task }
```

### Setup helpers
See {Ntswf::Utils}

License
-------
[LPGLv3](http://www.gnu.org/licenses/lgpl-3.0.html)