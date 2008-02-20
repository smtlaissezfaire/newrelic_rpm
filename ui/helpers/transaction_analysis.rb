# Add these methods to TransactionSample that enable performance analysis in the user interface.
# TODO move this sample analysis to a common library when we reuse it for the hosted version
class NewRelic::TransactionSample
  def database_time
    time_percentage(/^Database\/.*/)
  end
  
  def render_time
    time_percentage(/^View\/.*/)
  end
  
  # summarizes performance data for all calls to segments
  # with the same metric_name
  class SegmentSummary
    attr_accessor :metric_name, :total_time, :exclusive_time, :call_count
    def initialize(metric_name, sample)
      @metric_name = metric_name
      @total_time, @exclusive_time, @call_count = 0,0,0
      @sample = sample
    end
    
    def <<(segment)
      if metric_name != segment.metric_name
        raise ArgumentError.new("Metric Name Mismatch: #{segment.metric_name} != #{metric_name}") 
      end
      
      @total_time += segment.duration
      @exclusive_time += segment.exclusive_duration
      @call_count += 1
    end
    
    def average_time
      @total_time / @call_count
    end
    
    def average_exclusive_time
      @exclusive_time / @call_count
    end
    
    def exclusive_time_percentage
      @exclusive_time / @sample.duration
    end
    
    def total_time_percentage
      @total_time / @sample.duration
    end
    
    def developer_name
      return @metric_name if @metric_name == 'Remainder'
      # This drags all of the metric parser into the agent which I would prefer
      # not to do.  We could do a webservice that centralizes this but that might
      # be expensive and not well received.
      # MetricParser.parse(@metric_name).developer_name
      @metric_name
    end
  end
  
  # return the data that breaks down the performance of the transaction
  # as an array of SegmentSummary objects.  If a limit is specified, then
  # limit the data set to the top n
  def breakdown_data(limit = nil)
    metric_hash = {}
    each_segment do |segment|
      unless segment == root_segment
        metric_name = segment.metric_name
        metric_hash[metric_name] ||= SegmentSummary.new(metric_name, self)
        metric_hash[metric_name] << segment
      end
    end
    
    data = metric_hash.values
    
    data.sort! do |x,y|
      y.exclusive_time <=> x.exclusive_time
    end
    
    if limit && data.length > limit
      data = data[0..limit - 1]
    end

    # add one last segment for the remaining time if any
    remainder = duration
    data.each do |segment|
      remainder -= segment.exclusive_time
    end
    
    if remainder.to_ms > 0.1
      remainder_summary = SegmentSummary.new('Remainder', self)
      remainder_summary.total_time = remainder_summary.exclusive_time = remainder
      remainder_summary.call_count = 1
      data << remainder_summary
    end
      
    data
  end
  
  # return an array of sql statements executed by this transaction
  # each element in the array contains [sql, parent_segment_metric_name, duration]
  def sql_segments
    segments = []
    each_segment do |segment|
      if segment[:sql]
        segments << segment
      end
    end
    segments
  end
  
  private 
    def time_percentage(regex)
      total = 0
      each_segment do |segment|
        if regex =~ segment.metric_name
          # TODO what if a find calls something else rather than going straight to the db?
          total += segment.duration
        end
      end

      return (total / duration).to_percentage
    end
end