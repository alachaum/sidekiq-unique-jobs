# frozen_string_literal: true

require "sidekiq"
require "forwardable"
require "concurrent/mutable_struct"

require "sidekiq_unique_jobs/version"
require "sidekiq_unique_jobs/constants"
require "sidekiq_unique_jobs/json"
require "sidekiq_unique_jobs/logging"
require "sidekiq_unique_jobs/timing"
require "sidekiq_unique_jobs/sidekiq_worker_methods"
require "sidekiq_unique_jobs/connection"
require "sidekiq_unique_jobs/exceptions"
require "sidekiq_unique_jobs/script"
require "sidekiq_unique_jobs/job"
require "sidekiq_unique_jobs/util"
require "sidekiq_unique_jobs/digests"
require "sidekiq_unique_jobs/cli"
require "sidekiq_unique_jobs/core_ext"
require "sidekiq_unique_jobs/timeout"
require "sidekiq_unique_jobs/unique_args"
require "sidekiq_unique_jobs/unlockable"
require "sidekiq_unique_jobs/key"
require "sidekiq_unique_jobs/locksmith"
require "sidekiq_unique_jobs/lock/base_lock"
require "sidekiq_unique_jobs/lock/until_executed"
require "sidekiq_unique_jobs/lock/until_executing"
require "sidekiq_unique_jobs/lock/until_expired"
require "sidekiq_unique_jobs/lock/while_executing"
require "sidekiq_unique_jobs/lock/while_executing_reject"
require "sidekiq_unique_jobs/lock/until_and_while_executing"
require "sidekiq_unique_jobs/options_with_fallback"
require "sidekiq_unique_jobs/middleware"
require "sidekiq_unique_jobs/sidekiq_unique_ext"
require "sidekiq_unique_jobs/on_conflict"
require "sidekiq_unique_jobs/client_middleware"
require "sidekiq_unique_jobs/server_middleware"

require "sidekiq_unique_jobs/config"
require "sidekiq_unique_jobs/sidekiq_unique_jobs"
# require "monitor"

# module MonitorMixin
#   def mon_synchronize
#     yield if block_given?
#   end
# end

# require "sidekiq_unique_jobs/async_sidekiq"
