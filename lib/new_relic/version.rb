#!/usr/bin/ruby
module NewRelic
  module VERSION #:nodoc:
  MAJOR = 2
  MINOR = 8
  TINY  = 999
  STRING = [MAJOR, MINOR, TINY].join('.')
  def self.changes
    puts "NewRelic RPM Plugin Version: #{NewRelic::VERSION::STRING}"
    puts CHANGELOG
  end

  CHANGELOG = <<EOF
2009-02-22 version 2.8.5
  * fix reference to CommandError which was breaking some cap scripts
  * fix incompatibility with Rails 2.0 in the server API
  * fix problem with litespeed with Lite accounts
  * fix problem when ActiveRecord is disabled
  * moved merb instrumentation to Merb::Controller instead of 
    AbstractController to address incompatibility with MailController
  * fix problem in devmode displaying sql with embedded urls
2009-02-17 version 2.8.4
  * fix bug detecting Phusion Passenger v 2.1.0
  * fix bug in capistrano recipe causing cap commands to fail with error
    about not finding Version class
2009-02-10 version 2.8.3
  * refactor unit tests so they will run in a generic rails environment
  * require classes in advance to avoid autoloading.  this is to address
    incompatibilities with desert as well as more flexibility in gem 
    initialization
  * fixed newrelic_helper.rb 1.9 incompatibility
2009-02-07 version 2.8.2
  * fix Ruby 1.9 syntax compatibility errors
  * update the class loading sanity check, will notify server of errors
  * fix agent output on script and rake task execution
2009-01-27 version 2.8.1
  * Convert the deployment information upload script to an executable
    and put in the bin directory.  When installed as a gem this command
    is symlinked to /usr/bin.  Usage: newrelic_cmd deployments --help
  * Fix issue invoking api when host is not set in newrelic.yml
  * Fix deployments api so it will work from a gem
  * Fix thin incompatibility in developer mode 
2008-12-18 version 2.8.0
  * add beta of api in new_relic_api.rb
  * instrumented dynamic finders in ActiveRecord
  * preliminary support for capturing deployment information via capistrano
  * change memory sampler for solaris to use /usr/bin/ps
  * allow ERB in newrelic.yml file
  * merged support for merb into this version 
  * fix incompatibility in the developer mode with the safe_erb plugin
  * fix module namespace issue causing an error accessing NewRelic::Instrumentation modules
  * fix issue where the agent sometimes failed to start up if there was a transient network problem
  * fix IgnoreSilentlyException message
2008-12-09 version 2.7.4
  * fix error when trying to serialize some kinds of Enumerable objects
  * added extra debug logging
  * added app_name to app mapping
2008-11-26 version 2.7.3
  * fix compatibility issue with 1.8.5 causing error with Dir.glob
2008-11-24 version 2.7.2
  * fix problem with passenger edge not being a detected environment
2008-11-22 verison 2.7.1
  * fix problem with skipped dispatcher instrumentation
2008-11-23 version 2.7.0
  * Repackage to support both plugin and Gem installation
  * Support passenger/litespeed/jruby application naming
  * Update method for calculating dispatcher queue time
  * Show stack traces in RPM Transaction Traces
  * Capture error source for TemplateErrors
  * Clean up error stack traces.
  * Support query plans from postgres
  * Performance tuning
  * bugfixes
2008-10-06 version 2.5.3
  * fix error in transaction tracing causing traces not to show up
2008-09-30 version 2.5.2
  * fixes for postgres explain plan support
2008-09-09 version 2.5.1
  * bugfixes
2008-08-29 version 2.5.0
  * add agent support for rpm 1.1 features
  * Fix regression error with thin support
2008-08-27 version 2.4.3
  * added 'newrelic_ignore' controller class method with :except and :only options for finer grained control
    over the blocking of instrumentation in controllers.
  * bugfixes
2008-07-31 version 2.4.2
  * error reporting in early access
2008-07-30 version 2.4.1
  * bugfix: initializing developer mode
2008-07-29 version 2.4.0
  * Beta support for LiteSpeed and Passenger
2008-07-28 version 2.3.7
  * bugfixes
2008-07-28 version 2.3.6
  * bugfixes
2008-07-17 version 2.3.5
  * bugfixes: pie chart data, rails 1.1 compability
2008-07-11 version 2.3.4
  * bugfix
2008-07-10 version 2.3.3
  * bugfix for non-mysql databases
2008-07-07 version 2.3.2
  * bugfixes
  * Add enhancement for Transaction Traces early access feature
2008-06-26 version 2.3.1
  * bugfixes
2008-06-26 version 2.3.0
  + Add support for Transaction Traces early access feature
2008-06-13 version 2.2.2
  * bugfixes
2008-06-10 version 2.2.1
  + Add rails 2.1 support for Developer Mode
  + Changes to memory sampler: Add support for JRuby and fix Solaris support.  
  * Stop catching exceptions and start catching StandardError; other exception cleanup
  * Add protective exception catching to the stats engine
  * Improved support for thin domain sockets
  * Support JRuby environments
2008-05-22 version 2.1.6
  * bugfixes
2008-05-22 version 2.1.5
  * bugfixes
2008-05-14 version 2.1.4
  * bugfixes
2008-05-13 version 2.1.3
  * bugfixes
2008-05-08 version 2.1.2
  * bugfixes
2008-05-07 version 2.1.1
  * bugfixes
2008-04-25 version 2.1.0
  * release for private beta
EOF
  end
end

if __FILE__ == $0
  NewRelic::VERSION.changes
end

