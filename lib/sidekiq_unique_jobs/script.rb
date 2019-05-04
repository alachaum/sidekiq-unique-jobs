# frozen_string_literal: true

require "pathname"
require "digest/sha1"
require "concurrent/map"

module SidekiqUniqueJobs
  # Interface to dealing with .lua files
  #
  # @author Mikael Henriksson <mikael@zoolutions.se>
  module Script
    #
    # Module Caller provides the convenience method #call_script
    #
    # @author Mikael Henriksson <mikael@zoolutions.se>
    #
    module Caller
      module_function

      #
      # Convenience method to reduce typing,
      #   calls redis lua scripts.
      #
      #
      # @param [Symbol] file_name the name of the `script.lua` without extension
      # @param [Array<String>] keys the keys to pass to the script
      # @param [Array<String>] argv any extra arguments to pass
      #
      # @return [true,false,String,Integer,Float,nil] returns the return value of the lua script
      #
      def call_script(file_name, keys = [], argv = [])
        redis_pool = nil unless defined?(redis_pool)
        Script.call(file_name, redis_pool, keys: keys, argv: argv)
      end
    end

    LUA_PATHNAME ||= Pathname.new(__FILE__).dirname.join("../../redis").freeze
    SCRIPT_SHAS ||= Concurrent::Map.new

    extend SidekiqUniqueJobs::Connection
    extend SidekiqUniqueJobs::Logging
    extend SidekiqUniqueJobs::Timing

    module_function

    #
    # Call a lua script with the provided file_name
    #
    # @note this method is recursive if we need to load a lua script
    #   that wasn't previously loaded.
    #
    # @param [Symbol] file_name the name of the lua script
    # @param [Sidekiq::RedisConnection, ConnectionPool] redis_pool the redis connection
    # @param [Hash] options arguments to pass to the script file
    # @option options [Array] :keys the array of keys to pass to the script
    # @option options [Array] :argv the array of arguments to pass to the script
    #
    # @return value from script
    #
    def call(file_name, redis_pool, options = {})
      result, elapsed = timed do
        execute_script(file_name, redis_pool, options)
      end

      log_debug("Executed #{file_name}.lua in #{elapsed}ms")
      result
    rescue ::Redis::CommandError => ex
      handle_error(ex, file_name) do
        call(file_name, redis_pool, options)
      end
    end

    #
    # Execute the script file
    #
    # @param [Symbol] file_name the name of the lua script
    # @param [Sidekiq::RedisConnection, ConnectionPool] redis_pool the redis connection
    # @param [Hash] options arguments to pass to the script file
    # @option options [Array] :keys the array of keys to pass to the script
    # @option options [Array] :argv the array of arguments to pass to the script
    #
    # @return value from script (evalsha)
    #
    def execute_script(file_name, redis_pool, options = {})
      redis(redis_pool) do |conn|
        sha = script_sha(conn, file_name)
        conn.evalsha(sha, options[:keys], options[:argv])
      end
    end

    #
    # Return sha of already loaded lua script or load it and return the sha
    #
    # @param [Sidekiq::RedisConnection] conn the redis connection
    # @param [Symbol] file_name the name of the lua script
    # @return [String] sha of the script file
    #
    # @return [String] the sha of the script
    #
    def script_sha(conn, file_name)
      if (sha = SCRIPT_SHAS.get(file_name))
        return sha
      end

      sha = conn.script(:load, script_source(file_name))
      SCRIPT_SHAS.put(file_name, sha)
      sha
    end

    #
    # Handle errors to allow retrying errors that need retrying
    #
    # @param [Redis::CommandError] ex exception to handle
    # @param [Symbol] file_name the name of the lua script
    #
    # @return [void]
    #
    # @yieldreturn [void] yields back to the caller when NOSCRIPT is raised
    def handle_error(ex, file_name)
      if ex.message == "NOSCRIPT No matching script. Please use EVAL."
        SCRIPT_SHAS.delete(file_name)
        return yield if block_given?
      end

      if ScriptError.intercepts?(ex)
        raise ScriptError.new(ex, script_path(file_name).to_s, script_source(file_name))
      else
        raise
      end
    end

    #
    # Reads the lua file from disk
    #
    # @param [Symbol] file_name the name of the lua script
    #
    # @return [String] the content of the lua file
    #
    def script_source(file_name)
      script_path(file_name).read
    end

    #
    # Construct a Pathname to a lua script
    #
    # @param [Symbol] file_name the name of the lua script
    #
    # @return [Pathname] the full path to the gems lua script
    #
    def script_path(file_name)
      LUA_PATHNAME.join("#{file_name}.lua")
    end
  end
end
