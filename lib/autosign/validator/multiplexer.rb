# frozen_string_literal: true
require 'autosign/validator/validator_base'
require 'English'

module Autosign
  module Validator
    # The multiplexer validator sends the same request received by the autosign
    # executable to one or more external executables. The purpose is to allow
    # one or more existing autosign scripts to be used in conjunction with the
    # native validators implemented in this tool.
    #
    # @example validate autosign requests with any one of three external autosign scripts
    #   # In the /etc/autosign.conf file, include a section reading:
    #   [multiplexer]
    #     strategy = any
    #     external_policy_executable = /usr/local/bin/custom-autosigner1.sh
    #     external_policy_executable = /usr/local/bin/another-autosign-script.rb
    #     external_policy_executable = /usr/local/bin/yet-another-autosign-script.pl
    #   # all three scripts will be called with the same interface puppet
    #   # uses when an autosign policy executable is specified in the `autosign`
    #   # setting in the [master] section of the puppet.conf config file.
    #
    # @example validate autosign requests with both of two external autosign scripts
    #   # In the /etc/autosign.conf file, include a section reading:
    #   [multiplexer]
    #     strategy = all
    #     external_policy_executable = /usr/local/bin/custom-autosigner1.sh
    #     external_policy_executable = /usr/local/bin/another-autosign-script.rb
    #   # requests will only be validated by the multiplexer validator if they
    #   # are validated by both external policy executables.
    class Multiplexer < Autosign::Validator::ValidatorBase
      NAME = 'multiplexer'

      private

      # validate a CSR by passing it to each external executable
      # @param token [String] not used by this validator
      # @param certname [String] certname requested in the CSR
      # @param raw_csr [String] X509 certificate signing request as received by the policy executable
      # @return [True, False] returns true to indicate successful validation, and false to indicate failure to validate
      def perform_validation(_token, certname, raw_csr)
        results = []
        @log.debug 'validating using multiplexed external executables'
        policy_executables.each do |executable|
          @log.debug "attempting to validate using #{executable}"
          results << IO.popen(executable + ' ' + certname.to_s, 'r+') { |obj| obj.puts raw_csr; obj.close_write; obj.read; obj.close; $CHILD_STATUS.exitstatus }
          @log.debug "exit code from #{executable}: #{results.last}"
        end
        bool_results = results.map { |val| val == 0 }
        validate_using_strategy(bool_results)
      end

      # set the default validation strategy to "any", succeeding if any one
      # external autosign script succeeds.
      # @return [Hash] config hash to be merged in with config file settings and overrides.
      def default_settings
        {
          'strategy' => 'any'
        }
      end

      # given an array of booleans, check whether any or all of them are true
      # depending on the strategy set in settings.
      # @param array [Array] array of booleans
      # @return [True, False]
      def validate_using_strategy(array)
        case settings['strategy']
        when 'any'
          @log.debug "validating using 'any' strategy"
          array.any?
        when 'all'
          @log.debug "validating using 'all' strategy"
          array.all?
        else
          @log.error 'unable to validate; unknown strategy'
          false
        end
      end

      # return an array of external policy executables in settings,
      # or an empty array if none are specified.
      # @return [Array] of policy executables.
      def policy_executables
        Array(settings['external_policy_executable'])
      end

      # validate that settins are reasonable. Validation strategy must be
      # either any or all.
      # @param settings [Hash] config settings hash
      # @return [True, False] true if settings validate successfully, false otherwise
      def validate_settings(settings)
        @log.debug 'validating settings: ' + settings.to_s
        unless %w[any all].include? settings['strategy']
          @log.error "strategy setting must be set to 'any' or 'all'"
          return false
        end

        @log.debug 'done validating settings'
        true
      end
    end
  end
end
