NTSWF
=====

Not That Simple Workflow - A layer around AWS SWF

Common denominator of our [infopark](http://infopark.com/) internal services using
AWS Simple Workflow.

[![Gem Version](https://badge.fury.io/rb/ntswf.png)](http://badge.fury.io/rb/ntswf)
[![Code Climate](https://codeclimate.com/github/infopark/ntswf.png)](https://codeclimate.com/github/infopark/ntswf)
[![Dependency Status](https://gemnasium.com/infopark/ntswf.png)](https://gemnasium.com/infopark/ntswf)
[![Build Status](https://travis-ci.org/infopark/ntswf.png)](https://travis-ci.org/infopark/ntswf)

Usage
-----
### Gemfile

    gem 'ntswf', '~> 2.0'

### Client
```
config = {domain: 'my_domain', unit: 'my_app'} # ...
Ntswf.create(:client, config).start_execution(
  execution_id: 'my_singleton_task',
  name: 'my_worker_name',
  params: {my_param: :param},
  unit: 'my_worker',
)
```
See {Ntswf::Base#configure} for configuration options.

### Decision worker
```
config = {domain: 'my_domain', unit: 'my_app'} # ...
Ntswf.create(:decision_worker, config).process_decisions
```

### Activity worker
```
config = {domain: 'my_domain', unit: 'my_worker'} # ...
worker = Ntswf.create(:activity_worker, config)
worker.on_task ->(task) { Ntswf.result task.params['my_param'] }
worker.process_activities
```

### Setup helpers
See {Ntswf::Utils}

License
-------
[LPGL-3.0](http://www.gnu.org/licenses/lgpl-3.0.html)
