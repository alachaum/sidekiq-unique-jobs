# frozen_string_literal: true

module SidekiqUniqueJobs
  # Lock manager class that handles all the various locks
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  class Locksmith
    include SidekiqUniqueJobs::Connection
    include SidekiqUniqueJobs::Logging
    include SidekiqUniqueJobs::Timing
    include SidekiqUniqueJobs::Script::Caller

    DEFAULT_REDIS_TIMEOUT = 0.1
    DEFAULT_RETRY_COUNT   = 3
    DEFAULT_RETRY_DELAY   = 200
    DEFAULT_RETRY_JITTER  = 50
    CLOCK_DRIFT_FACTOR    = 0.01

    #
    # Initialize a new Locksmith instance
    #
    # @param [Hash] item a Sidekiq job hash
    # @option item [Integer] :lock_expiration the configured expiration
    # @option item [String] :jid the sidekiq job id
    # @option item [String] :unique_digest the unique digest (See: {UniqueArgs#unique_digest})
    # @param [Sidekiq::RedisConnection, ConnectionPool] redis_pool the redis connection
    #
    def initialize(item, redis_pool = nil)
      @key           = Key.new(item[UNIQUE_DIGEST_KEY])
      @jid           = item[JID_KEY]
      @ttl           = item[LOCK_EXPIRATION_KEY].to_i * 1000
      @timeout       = item[LOCK_TIMEOUT_KEY]
      @lock_type     = item[LOCK_KEY]
      @lock_type   &&= @lock_type.to_sym
      @redis_pool    = redis_pool
      @concurrency   = 1 # removed in a0cff5bc42edbe7190d6ede7e7f845074d2d7af6
      @retry_count   = item[LOCK_RETRY_COUNT_KEY] || DEFAULT_RETRY_COUNT
      @retry_delay   = item[LOCK_RETRY_DELAY_KEY] || DEFAULT_RETRY_DELAY
      @retry_jitter  = item[LOCK_RETRY_JITTER_KEY] || DEFAULT_RETRY_JITTER
      @extend        = item["lock_extend"]
      @extend_owned  = item["lock_extend_owned"]
    end

    #
    # Deletes the lock unless it has a ttl set
    #
    #
    def delete
      return if ttl.positive?

      delete!
    end

    #
    # Deletes the lock regardless of if it has a ttl set
    #
    def delete!
      call_script(:delete, key.to_a)
    end

    #
    # Create a lock for the item
    #
    # @return [String] the Sidekiq job_id that was locked/queued
    #
    def lock
      return unless (locked_jid = prepare)
      return unless locked_jid == job_id

      obtain do
        store_lock_token(token)
      end

      locked_jid
    end
    alias wait lock

    #
    # Removes the lock keys from Redis if locked by the provided jid/token
    #
    # @return [false] unless locked?
    # @return [String] Sidekiq job_id (jid) if successful
    #
    def unlock
      return false unless locked?

      unlock!
    end

    #
    # Removes the lock keys from Redis
    #
    # @return [false] unless locked?
    # @return [String] Sidekiq job_id (jid) if successful
    #
    def unlock!
      call_script(:unlock, key.to_a, [jid, ttl, lock_type])
    end

    # Checks if this instance is considered locked
    #
    # @return [true, false] true when the grabbed token contains the job_id
    #
    def locked?
      call_script(:locked, [key.digest], [jid]) >= 1
    end

    private

    attr_reader :key, :ttl, :jid, :redis_pool, :lock_type, :timeout, :concurrency

    def prepare
      locked_jid, time_elapsed = timed do
        call_script(:prepare, key.to_a, [jid, ttl, lock_type, current_time])
      end

      validity = ttl.to_i - time_elapsed - drift

      return unless locked_jid == jid
      return unless validity >= 0 || ttl.zero?

      locked_jid
    end

    def obtain
      return unless (token = pop_token)

      call_script(:obtain, key.to_a, [jid, ttl, current_time, concurrency, token])
      yield token
    end

    def pop_token
      token, elapsed = timed do
        redis do |conn|
          if timeout.nil? || timeout.positive?
            # passing timeout 0 to brpoplpush causes it to block indefinitely
            conn.brpoplpush(key.prepared, key.obtained, timeout || 0)
          else
            conn.rpoplpush(key.prepared, key.obtained)
          end
        end
      end

      # TODO: Collect metrics and stats
      log_debug("Waited #{elapsed}ms for #{token} to be released (digest: #{key.digest}, job_id: #{jid})")
      token
    end

    def try_lock
      tries = @extend ? 1 : (@retry_count + 1)

      tries.times do |attempt_number|
        # Wait a random delay before retrying.
        sleep(sleepy_time) if attempt_number.positive?
        locked = create_lock
        return locked if locked
      end

      false
    end

    def sleepy_time
      (@retry_delay + rand(@retry_jitter)).to_f / 1000
    end

    def drift
      # Add 2 milliseconds to the drift to account for Redis expires
      # precision, which is 1 millisecond, plus 1 millisecond min drift
      # for small TTLs.
      (ttl * CLOCK_DRIFT_FACTOR).to_i + 2
    end
  end
end
