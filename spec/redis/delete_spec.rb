# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "delete.lua", redis: :redis do
  subject(:delete) { call_script(:delete, key.to_a, argv) }

  let(:argv) do
    [
      job_id,
      lock_ttl,
      lock_type,
      lock_limit,
    ]
  end
  let(:job_id)     { "jobid" }
  let(:lock_type)  { :until_executed }
  let(:digest)     { "uniquejobs:digest" }
  let(:key)        { SidekiqUniqueJobs::Key.new(digest) }
  let(:lock_ttl)   { nil }
  let(:locked_jid) { job_id }
  let(:lock_limit) { 1 }

  context "when queued" do
    before do
      call_script(:queue, key.to_a, argv)
    end

    it "deletes keys from Redis" do
      expect { delete }.to change { zcard(key.changelog) }.by(1)

      expect(key.digest).not_to exist
      expect(key.queued).not_to exist
      expect(key.primed).not_to exist
      expect(key.locked).not_to exist
    end
  end

  context "when primed" do
    before do
      call_script(:queue, key.to_a, argv)
      rpoplpush(key.queued, key.primed)
    end

    it "deletes keys from Redis" do
      expect { delete }.to change { zcard(key.changelog) }.by(1)

      expect(key.digest).not_to exist
      expect(key.queued).not_to exist
      expect(key.primed).not_to exist
      expect(key.locked).not_to exist
    end
  end

  context "when locked" do
    before do
      call_script(:queue, key.to_a, argv)
      primed_jid = brpoplpush(key.queued, key.primed)
      call_script(:lock, key.to_a, argv)
    end

    it "deletes keys from Redis" do
      expect { delete }.to change { zcard(key.changelog) }.by(1)

      expect(key.digest).not_to exist
      expect(key.queued).not_to exist
      expect(key.primed).not_to exist
      expect(key.locked).not_to exist
    end
  end
end
# rubocop:enable RSpec/DescribeClass
