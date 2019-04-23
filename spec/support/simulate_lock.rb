# frozen_string_literal: true

require "concurrent/array"

module SimulateLock
  extend self
  @items = Concurrent::Array.new

  def lock_jid(key, jid)
    raise ArgumentError, ":key needs to be a Key" unless key.is_a?(SidekiqUniqueJobs::Key)
    SidekiqUniqueJobs.redis do |conn|
      conn.multi do
        conn.sadd(SidekiqUniqueJobs::UNIQUE_SET, key.digest)
        conn.set(key.exists, jid)
        conn.set(key.version, "1")
        conn.hset(key.grabbed, jid, Time.now.to_f)
        conn.rpush(key.available, jid)
      end
    end
  end

  def lock_until_executed(digest, jid, ttl = nil)
    item = get_item(digest: digest, jid: jid, lock_type: :until_executed, ttl: ttl)
    lock(item)
  end

  def lock_until_expired(digest, jid, ttl)
    item = get_item(digest: digest, jid: jid, lock_type: :until_expired, ttl: ttl)
    lock(item)
  end

  def lock_until_and_while_executing(digest, jid, ttl = nil)
    item = get_item(digest: digest, jid: jid, lock_type: :until_expired, ttl: ttl)
    lock(item)
  end

  def lock_while_executing(digest, jid, ttl = nil)
    digest = digest.dup + ":RUN"
    item = get_item(digest: digest, jid: jid, lock_type: :while_executing, ttl: ttl)
    lock(item)
  end

  def runtime_lock(digest, jid, ttl = nil)
    item = get_item(digest: digest, jid: jid, lock_type: :while_executing, ttl: ttl)
    lock(item)
    item = get_item(digest: "#{digest}:RUN", jid: "randomjid", lock_type: :while_executing, ttl: ttl)
    lock(item)
  end

  def lock(item)
    Locksmith.new(item).lock
  end

  def unlock(item)
    Locksmith.new(item).unlock
  end

  def get_item(digest: "randomdigest", jid: "randomjid", lock_type: :until_executed, ttl: nil)
    item = {
      UNIQUE_DIGEST_KEY => digest,
      JID_KEY => jid,
      LOCK_EXPIRATION_KEY => ttl,
      LOCK_KEY => lock_type,
    }
    @items << item
    item
  end
end

RSpec.configure do |config|
  config.include SimulateLock
end
