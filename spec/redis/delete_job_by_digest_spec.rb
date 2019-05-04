# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "delete_job_by_digest.lua", redis: :redis do
  subject(:delete_by_digest) { call_script(:delete_by_digest, [digest], [current_time]) }

  let(:job_id)     { "jobid" }
  let(:digest)     { "uniquejobs:digest" }
  let(:key)        { SidekiqUniqueJobs::Key.new(digest) }
  let(:run_key)    { SidekiqUniqueJobs::Key.new("#{digest}:RUN") }
  let(:lock_ttl)   { nil }
  let(:locked_jid) { job_id }
  let(:current_time) { SidekiqUniqueJobs::Timing.current_time }

  before do
    simulate_lock(key, job_id)
    simulate_lock(run_key, job_id)
  end

  it_behaves_like "redis has keys created by lock.lua"

  it "removes all keys for the given digest" do
    delete_by_digest
    expect(unique_keys).to match_array([])
  end
end
# rubocop:enable RSpec/DescribeClass
