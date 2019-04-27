# frozen_string_literal: true

module SidekiqUniqueJobs
  # Lock manager class that handles all the various locks
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  class Locksmith
    include SidekiqUniqueJobs::Connection
    include SidekiqUniqueJobs::Logging
    include SidekiqUniqueJobs::Timing

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
      # @concurrency = 1 # removed in a0cff5bc42edbe7190d6ede7e7f845074d2d7af6
      @jid           = item[JID_KEY]
      @key           = Key.new(item[UNIQUE_DIGEST_KEY])
      @ttl           = item[LOCK_EXPIRATION_KEY].to_i * 1000
      @lock_type     = item[LOCK_KEY]
      @lock_type   &&= @lock_type.to_sym
      @redis_pool    = redis_pool
      @retry_count   = item["lock_retry_count"] || DEFAULT_RETRY_COUNT
      @retry_delay   = item["lock_retry_delay"] || DEFAULT_RETRY_DELAY
      @retry_jitter  = item["lock_retry_jitter"] || DEFAULT_RETRY_JITTER
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
      Scripts.call(
        :delete,
        redis_pool,
        keys: key.to_a,
      )
    end

    #
    # Create a lock for the item
    #
    # @param [Integer] timeout the number of seconds to wait for a lock.
    #
    # @return [String] the Sidekiq job_id (jid)
    #
    def lock
      locked_jid = try_lock
      return locked_jid unless block_given?

      begin
        return yield locked_jid if locked_jid
      ensure
        unlock
      end
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
      Scripts.call(
        :unlock,
        redis_pool,
        keys: key.to_a,
        argv: [jid, ttl, lock_type],
      )
    end

    # Checks if this instance is considered locked
    #
    # @return [true, false] true when the grabbed token contains the job_id
    #
    def locked?
      Scripts.call(
        :locked,
        redis_pool,
        keys: [key.digest, key.exists, key.grabbed],
        argv: [jid],
      ) >= 1
    end

    private

    attr_reader :key, :ttl, :jid, :redis_pool, :lock_type

    def try_lock
      tries = @extend ? 1 : (@retry_count + 1)

      tries.times do |attempt_number|
        # Wait a random delay before retrying.
        sleep((@retry_delay + rand(@retry_jitter)).to_f / 1000) if attempt_number.positive?

        locked = create_lock
        return locked if locked
      end

      false
    end

    def create_lock
      locked_jid, time_elapsed = timed do
        Scripts.call(:lock, redis_pool,
                     keys: key.to_a,
                     argv: [jid, ttl, lock_type])
      end

      validity = ttl.to_i - time_elapsed - drift

      if locked_jid == jid && (validity >= 0 || ttl.zero?)
        locked_jid
      else
        false
      end
    end

    def drift
      # Add 2 milliseconds to the drift to account for Redis expires
      # precision, which is 1 millisecond, plus 1 millisecond min drift
      # for small TTLs.
      (ttl * CLOCK_DRIFT_FACTOR).to_i + 2
    end
  end
end
