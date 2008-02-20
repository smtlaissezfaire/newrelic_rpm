require 'newrelic/transaction_sample'
require 'thread'

module NewRelic::Agent
  class TransactionSampler
    def initialize(agent = nil, max_samples = 500)
      @rules = []
      @samples = []
      @mutex = Mutex.new
      @max_samples = max_samples
      
      # when the agent is nil, we are in a unit test.
      # don't hook into the stats engine, which owns
      # the scope stack
      unless agent.nil?
        agent.stats_engine.add_scope_stack_listener self
      end
    end
    
    def add_rule(rule)
      @mutex.synchronize do 
        @rules << rule
      end
    end
    
    def notice_first_scope_push
      get_or_create_builder
    end
    
    def notice_push_scope(scope)
      with_builder do |builder|
        check_rules(scope)
        builder.trace_entry(scope)
        
        # in developer mode, capture the stack trace with the segment.
        # this is cpu and memory expensive and therefore should not be
        # turned on in production mode
        if ::RPM_DEVELOPER
          segment = builder.current_segment
          if segment
            trace = caller(8)
            
            trace = trace[0..40] if trace.length > 40
            segment[:backtrace] = trace
          end
        end
      end
    end
  
    def notice_pop_scope(scope)
      with_builder do |builder|
        builder.trace_exit(scope)
      end
    end
    
    def notice_scope_empty
      with_builder do |builder|
        builder.finish_trace
      
        @mutex.synchronize do
          @samples << builder.sample if should_collect_sample?
        
          # ensure we don't collect more than a specified number of samples in memory
          @samples.shift while @samples.length > @max_samples
        
          # remove any rules that have expired
          @rules.reject!{ |rule| rule.has_expired? }
        end
      
        reset_builder
      end
    end
    
    def notice_transaction(path, params)
      with_builder do |builder|
        builder.set_transaction_info(path, params)
      end
    end
    
    def notice_sql(sql)
      with_builder do |builder|
        segment = builder.current_segment
        if segment
          current_sql = segment[:sql]
          sql = current_sql + ";\n" + sql if current_sql
          segment[:sql] = sql
        end
      end
    end
    
    # get the set of collected samples, merging into previous samples,
    # and clear the collected sample list
    def harvest_samples(previous_samples=[])
      @mutex.synchronize do 
        s = previous_samples
      
        @samples.each do |sample|
          s << sample
        end
        @samples = [] unless is_developer_mode?
        s
      end
    end

    # get the list of samples without clearing the list.
    def get_samples
      @mutex.synchronize do
        return @samples.clone
      end
    end
    
    private 
      def check_rules(scope)
        return if should_collect_sample?
        set_should_collect_sample and return if is_developer_mode?
        
        @rules.each do |rule|
          if rule.check(scope)
            set_should_collect_sample
          end
        end
      end
    
      BUILDER_KEY = :transaction_sample_builder
      def get_or_create_builder
        return nil if @rules.empty? && !is_developer_mode?
        
        builder = get_builder
        if builder.nil?
          builder = TransactionSampleBuilder.new
          Thread::current[BUILDER_KEY] = builder
        end
        
        builder
      end
      
      # most entry points into the transaction sampler take the current transaction
      # sample builder and do something with it.  There may or may not be a current
      # transaction sample builder on this thread. If none is present, the provided
      # block is not called (saving sampling overhead); if one is, then the 
      # block is called with the transaction sample builder that is registered
      # with this thread.
      def with_builder
        builder = get_builder
        yield builder if builder
      end
      
      def get_builder
        Thread::current[BUILDER_KEY]
      end
      
      def reset_builder
        Thread::current[BUILDER_KEY] = nil
        set_should_collect_sample(false)
      end
      
      COLLECT_SAMPLE_KEY = :should_collect_sample
      def should_collect_sample?
        Thread::current[COLLECT_SAMPLE_KEY]
      end
      
      def set_should_collect_sample(value=true)
        Thread::current[COLLECT_SAMPLE_KEY] = value
      end
      
      def is_developer_mode?
        defined?(::RPM_DEVELOPER) && ::RPM_DEVELOPER
      end
  end

  # a builder is created with every sampled transaction, to dynamically
  # generate the sampled data
  class TransactionSampleBuilder
    attr_reader :current_segment
    
    def initialize
      @sample = NewRelic::TransactionSample.new
      @sample.begin_building
      @current_segment = @sample.root_segment
    end

    def trace_entry(metric_name)
      segment = @sample.create_segment(relative_timestamp, metric_name)
      @current_segment.add_called_segment(segment)
      @current_segment = segment
    end

    def trace_exit(metric_name)
      if metric_name != @current_segment.metric_name
        fail "unbalanced entry/exit: #{metric_name} != #{@current_segment.metric_name}"
      end
      
      @current_segment.end_trace relative_timestamp
      @current_segment = @current_segment.parent_segment
    end
    
    def finish_trace
      @sample.root_segment.end_trace relative_timestamp
      @sample.freeze
      @current_segment = nil
    end
    
    def freeze
      @sample.freeze unless sample.frozen?
    end
    
    def relative_timestamp
      Time.now - @sample.start_time
    end
    
    def set_transaction_info(path, params)
      @sample.params.merge(params)
      @sample.params[:path] = path  
    end
    
    def sample
      fail "Not finished building" unless @sample.frozen?
      @sample
    end
    
  end
end