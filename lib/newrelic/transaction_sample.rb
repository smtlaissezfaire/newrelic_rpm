require 'newrelic/stats'

module NewRelic
  class TransactionSample
    class Segment
      attr_reader :entry_timestamp
      attr_reader :exit_timestamp
      attr_reader :parent_segment
      attr_reader :metric_name
      attr_reader :called_segments
      attr_reader :segment_id
      
      def initialize(timestamp, metric_name, segment_id)
        @entry_timestamp = timestamp
        @metric_name = metric_name
        @called_segments = []
        @segment_id = segment_id || object_id
      end
      
      def end_trace(timestamp)
        @exit_timestamp = timestamp
      end
      
      def add_called_segment(s)
        @called_segments << s
        s.parent_segment = self
      end
      
      def to_debug_str(depth)
        tab = "" 
        depth.times {tab << "  "}
        
        s = tab.clone
        s << ">> #{metric_name}: #{@entry_timestamp.to_ms}\n"
        unless params.empty?
          s << "#{tab}#{tab}{\n"
          params.each do |k,v|
            s << "#{tab}#{tab}#{k}: #{v}\n"
          end
          s << "#{tab}#{tab}}\n"
        end
        called_segments.each do |cs|
          s << cs.to_debug_str(depth + 1)
        end
        s << tab
        s << "<< #{metric_name}: #{@exit_timestamp ? @exit_timestamp.to_ms : 'n/a'}\n"
        s
      end
      
      def called_segments
        @called_segments.clone
      end
      
      def freeze
        params.freeze
        @called_segments.each do |s|
          s.freeze
        end
        super
      end
      
      # return the total duration of this segment
      def duration
        @exit_timestamp - @entry_timestamp
      end
      
      # return the duration of this segment without 
      # including the time in the called segments
      def exclusive_duration
        d = duration
        @called_segments.each do |segment|
          d -= segment.duration
        end
        d
      end
      
      def []=(key, value)
        # only create a parameters field if a parameter is set; this will save
        # bandwidth etc as most segments have no parameters
        params[key] = value
      end
        
      def [](key)
        params[key]
      end
      
      def params
        @params ||= {}
      end
      
      # call the provided block for this segment and each 
      # of the called segments
      def each_segment(&block)
        block.call self
        
        @called_segments.each do |segment|
          segment.each_segment(&block)
        end
      end
      
      # perform this in the runtime environment of a managed application, to explain the sql
      # statement(s) executed within a segment of a transaciton sample.
      # returns an array of explanations (which is an array of reqults from the explain query)
      # Note this happens only for statements whose execution time exceeds a threshold (e.g. 500ms)
      # and only within the slowest transaction in a report period, selected for shipment to RPM
      def explain_sql
        sql = params[:sql]
        return nil if sql.nil? 
        statements = sql.split(';')
        explanations = []
        statements.each do |statement|
          if statement.split($;, 2)[0].upcase == 'SELECT'
            explanation = []
            begin
              result = ActiveRecord::Base.connection.execute("EXPLAIN #{statement}")
              result.each {|row| explanation << row }
            rescue Exception
              # swallow failed attempts to run an explain.  One example of a failure is the
              # connection for the sql statement is to a different db than the default connection
              # specified in AR::Base
            end
            explanations << explanation
          end
        end

        explanations
      end
      
      protected
        def parent_segment=(s)
          @parent_segment = s
        end
    end

    attr_accessor :start_time
    attr_reader :root_segment
    attr_reader :params
    attr_reader :sample_id
    
    def initialize(sample_id = nil)
      @sample_id = sample_id || object_id
      @params = {}
    end
    
    def begin_building(start_time = Time.now)
      @start_time = start_time
      @root_segment = create_segment 0.0, "ROOT"
    end

    def create_segment (relative_timestamp, metric_name, segment_id = nil)
      raise TypeError.new("Frozen Transaction Sample") if frozen?
      NewRelic::TransactionSample::Segment.new(relative_timestamp, metric_name, segment_id)    
    end
    
    def freeze
      @root_segment.freeze
      params.freeze
      super
    end
    
    def duration
      root_segment.duration
    end
    
    def each_segment(&block)
      @root_segment.each_segment(&block)
    end
    
    def to_s
      s = "Transaction Sample collected at #{start_time}\n"
      s << "  {\n"
      s << "  Path: #{params[:path]} \n"
      
      params.each do |k,v|
        s << "  #{k}: #{v}\n" unless k == :path
      end
      s << "  }\n\n"
      s <<  @root_segment.to_debug_str(0)
    end
    
    # return a new transaction sample that treats segments
    # with the given regular expression in their name as if they
    # were never called at all.  This allows us to strip out segments
    # from traces captured in development environment that would not
    # normally show up in production (like Rails/Application Code Loading)
    def omit_segments_with(regex)
      regex = Regexp.new(regex)
      
      sample = TransactionSample.new(sample_id)
      sample.begin_building @start_time
      
      params.each {|k,v| sample.params[k] = v}
        
      delta = build_segment_with_omissions(sample, 0.0, @root_segment, sample.root_segment, regex)
      sample.root_segment.end_trace(@root_segment.exit_timestamp - delta) 
      sample.freeze
    end
    
    # return a new transaction sample that can be sent to the RPM service.
    # this involves potentially one or more of the following options 
    #   :explain_sql : run EXPLAIN on all queries whose response times equal the value for this key
    #       (for example :explain_sql => 2.0 would explain everything over 2 seconds.  0.0 would explain everything.)
    #   :keep_backtraces : keep backtraces, significantly increasing size of trace (off by default)
    #   :normalize_sql : clear sql fields of potentially sensitive values (higher overhead, better security)
    def prepare_to_send(options={})
      sample = TransactionSample.new(sample_id)
      sample.begin_building @start_time
      
      params.each {|k,v| sample.params[k] = v}
        
      build_segment_for_transfer(sample, @root_segment, sample.root_segment, options)
      sample.root_segment.end_trace(@root_segment.exit_timestamp) 
      sample.freeze
    end
    
  private
  
    def normalize_sql(sql)
      # TODO implement.s
      sql
    end
    
    def build_segment_with_omissions(new_sample, time_delta, source_segment, target_segment, regex)
      source_segment.called_segments.each do |source_called_segment|
        # if this segment's metric name matches the given regular expression, bail
        # here and increase the amount of time that we reduce the target sample with
        # by this omitted segment's duration.
        do_omit = regex =~ source_called_segment.metric_name
        
        if do_omit
          time_delta += source_called_segment.duration
        else
          target_called_segment = new_sample.create_segment(
                source_called_segment.entry_timestamp - time_delta, 
                source_called_segment.metric_name,
                source_called_segment.segment_id)
          
          target_segment.add_called_segment target_called_segment
          source_called_segment.params.each do |k,v|
            target_called_segment[k]=v
          end
          
          time_delta = build_segment_with_omissions(
                new_sample, time_delta, source_called_segment, target_called_segment, regex)
          target_called_segment.end_trace(source_called_segment.exit_timestamp - time_delta)
        end
      end
      
      return time_delta
    end

    # see prepare_to_send for what we do with options
    # TODO support each of the above options before shipping (keep_backtraces is optional)
    # TODO apply DRY to this and omit_segments_with
    def build_segment_for_transfer(new_sample, source_segment, target_segment, options)
      source_segment.called_segments.each do |source_called_segment|
        target_called_segment = new_sample.create_segment(
              source_called_segment.entry_timestamp,
              source_called_segment.metric_name,
              source_called_segment.segment_id)

        target_segment.add_called_segment target_called_segment
        source_called_segment.params.each do |k,v|
          if k == :backtrace
            target_called_segment[k]=v if options[:keep_backtraces]
          elsif k == :sql
            sql = v

            # run an EXPLAIN on this sql if specified.
            if options[:explain_sql] && source_called_segment.duration > options[:explain_sql].to_f
              target_called_segment[:explanation] = source_called_segment.explain_sql
            end
            
            sql = normalize(sql) if options[:normalize_sql]
            target_called_segment[k]=sql
          else
            target_called_segment[k]=v 
          end
        end

        build_segment_for_transfer(new_sample, source_called_segment, target_called_segment, options)
        target_called_segment.end_trace(source_called_segment.exit_timestamp)
      end
    end
  end
end
