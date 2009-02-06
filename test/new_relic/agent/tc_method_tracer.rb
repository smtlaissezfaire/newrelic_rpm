require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'new_relic/agent/mock_scope_listener'

::RPM_TRACERS_ENABLED = true unless defined? ::RPM_TRACERS_ENABLED

class Module
  def method_traced?(method_name, metric_name)
    traced_method_prefix = _traced_method_name(method_name, metric_name)
    
    method_defined? traced_method_prefix
  end
end  

class Insider
  def initialize(stats_engine)
    @stats_engine = stats_engine
  end
  def catcher(level=0)
    thrower(level) if level>0
  end
  def thrower(level)
    if level == 0
      # don't use a real sampler because we can't instantiate one
      # sampler = NewRelic::Agent::TransactionSampler.new(NewRelic::Agent.instance)
      sampler = "<none>"
      begin
        @stats_engine.add_scope_stack_listener sampler
        fail "This should not have worked."
        rescue; end
    else
      thrower(level-1)
    end
  end
end

module NewRelic
  module Agent
    
    # for testing, enable the stats engine to clear itself
    class StatsEngine
      def reset
        scope_stack.clear
        @stats_hash.clear
      end
    end
    
    extend self
    def module_method_to_be_traced (x, testcase)
      testcase.assert x == "x"
      testcase.assert testcase.stats_engine.peek_scope.name == "x"
    end
  end
end

class NewRelic::Agent::MethodTracerTests < Test::Unit::TestCase
  attr_reader :stats_engine
  
  def setup
    NewRelic::Agent::Agent.instance.shutdown
    NewRelic::Agent::Agent.instance.start 'rake', 'test'
    @stats_engine = NewRelic::Agent::Agent.instance.stats_engine
    @stats_engine.reset
    @scope_listener = NewRelic::Agent::MockScopeListener.new
    
    @stats_engine.add_scope_stack_listener(@scope_listener)
  end
  
  def teardown
    self.class.remove_method_tracer :method_to_be_traced, @metric_name if @metric_name
    @metric_name = nil
    NewRelic::Agent::Agent.instance.shutdown
  end
  
  def test_basic
    metric = "hello"
    t1 = Time.now
    self.class.trace_method_execution_with_scope metric, true, true do
      sleep 1
      assert metric == @stats_engine.peek_scope.name
    end
    elapsed = Time.now - t1
    
    stats = @stats_engine.get_stats(metric)
    check_time stats.total_call_time, elapsed
    assert stats.call_count == 1
  end
  
  def test_basic__original_api
    metric = "hello"
    t1 = Time.now
    self.class.trace_method_execution metric, true, true, true do
      sleep 1
      assert metric == @stats_engine.peek_scope.name
    end
    elapsed = Time.now - t1
    
    stats = @stats_engine.get_stats(metric)
    check_time stats.total_call_time, elapsed
    assert stats.call_count == 1
  end
  
  METRIC = "metric"
  def test_add_method_tracer
    @metric_name = METRIC
    assert ::RPM_TRACERS_ENABLED
    self.class.add_method_tracer :method_to_be_traced, METRIC
    
    t1 = Time.now
    method_to_be_traced 1,2,3,true,METRIC
    elapsed = Time.now - t1
    
    stats = @stats_engine.get_stats(METRIC)
    check_time stats.total_call_time, elapsed
    assert stats.call_count == 1
  end
  
  
  def test_method_traced?
    assert !self.class.method_traced?(:method_to_be_traced, METRIC)
    self.class.add_method_tracer :method_to_be_traced, METRIC
    assert self.class.method_traced?(:method_to_be_traced, METRIC)
  end
  
  def test_tt_only
    
    assert_nil @scope_listener.scope["c2"]
    self.class.add_method_tracer :method_c1, "c1", true
    
    self.class.add_method_tracer :method_c2, "c2", :metric => false
    self.class.add_method_tracer :method_c3, "c3", false
    
    method_c1
    
    assert_not_nil @stats_engine.lookup_stat("c1")
    assert_nil @stats_engine.lookup_stat("c2")
    assert_not_nil @stats_engine.lookup_stat("c3")
    
    assert_not_nil @scope_listener.scope["c2"]
  end
  
  def test_nested_scope_tracer
    Insider.add_method_tracer :catcher, "catcher", :push_scope => true
    Insider.add_method_tracer :thrower, "thrower", :push_scope => true
    sampler = NewRelic::Agent::Agent.instance.transaction_sampler
    mock = Insider.new(@stats_engine)
    mock.catcher(0)
    mock.catcher(5)
    stats = @stats_engine.get_stats("catcher")
    assert_equal 2, stats.call_count
    stats = @stats_engine.get_stats("thrower")
    assert_equal 6, stats.call_count
    sample = sampler.harvest_slowest_sample
    assert_not_nil sample
  end
  
  def test_add_same_tracer_twice
    @metric_name = METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC
    self.class.add_method_tracer :method_to_be_traced, METRIC
    
    t1 = Time.now
    method_to_be_traced 1,2,3,true,METRIC
    elapsed = Time.now - t1
    
    stats = @stats_engine.get_stats(METRIC)
    check_time stats.total_call_time, elapsed
    assert stats.call_count == 1
  end
  
  def test_add_tracer_with_dynamic_metric
    metric_code = '#{args[0]}.#{args[1]}'
    @metric_name = metric_code
    expected_metric = "1.2"
    self.class.add_method_tracer :method_to_be_traced, metric_code
    
    t1 = Time.now
    method_to_be_traced 1,2,3,true,expected_metric
    elapsed = Time.now - t1
    
    stats = @stats_engine.get_stats(expected_metric)
    check_time stats.total_call_time, elapsed
    assert stats.call_count == 1
  end
  
  def test_trace_method_with_block
    self.class.add_method_tracer :method_with_block, METRIC
    
    t1 = Time.now
    method_with_block(1,2,3,true,METRIC) do |scope|
      assert scope == METRIC
    end
    elapsed = Time.now - t1
    
    stats = @stats_engine.get_stats(METRIC)
    check_time stats.total_call_time, elapsed
    assert stats.call_count == 1
  end
  
  def test_trace_module_method
    NewRelic::Agent.add_method_tracer :module_method_to_be_traced, '#{args[0]}'
    NewRelic::Agent.module_method_to_be_traced "x", self
    NewRelic::Agent.remove_method_tracer :module_method_to_be_traced, '#{args[0]}'
  end
  
  def test_remove
    self.class.add_method_tracer :method_to_be_traced, METRIC
    self.class.remove_method_tracer :method_to_be_traced, METRIC
    
    t1 = Time.now
    method_to_be_traced 1,2,3,false,METRIC
    elapsed = Time.now - t1
    
    stats = @stats_engine.get_stats(METRIC)
    assert stats.call_count == 0
  end
  
  def self.static_method(x, testcase, is_traced)
    testcase.assert x == "x"
    testcase.assert((testcase.stats_engine.peek_scope.name == "x") == is_traced)
  end
  
  def trace_trace_static_method
    self.add_method_tracer :static_method, '#{args[0]}'
    self.class.static_method "x", self, true
    self.remove_method_tracer :static_method, '#{args[0]}'
    self.class.static_method "x", self, false
  end
  
  def test_exception
    begin
      metric = "hey there"
      self.class.trace_method_execution_with_scope metric, true, true do
        assert @stats_engine.peek_scope.name == metric
        throw Exception.new            
      end
      
      assert false # should never get here
    rescue Exception
      # make sure the scope gets popped
      assert @stats_engine.peek_scope == nil
    end
    
    stats = @stats_engine.get_stats metric
    assert stats.call_count == 1
  end
  
  def test_add_multiple_tracers
    self.class.add_method_tracer :method_to_be_traced, 'X', :push_scope => false
    method_to_be_traced 1,2,3,true,nil
    self.class.add_method_tracer :method_to_be_traced, 'Y'
    method_to_be_traced 1,2,3,true,'Y'
    self.class.remove_method_tracer :method_to_be_traced, 'Y'
    method_to_be_traced 1,2,3,true,nil
    self.class.remove_method_tracer :method_to_be_traced, 'X'
    method_to_be_traced 1,2,3,false,'X'
  end
  
  def trace_no_push_scope
    self.class.add_method_tracer :method_to_be_traced, 'X', :push_scope => false
    method_to_be_traced 1,2,3,true,nil
    self.class.remove_method_tracer :method_to_be_traced, 'X'
    method_to_be_traced 1,2,3,false,'X'
  end
  
  def check_time (t1, t2)
    assert((t2-t1).abs < 0.01)
  end
  
  # =======================================================
  # test methods to be traced
  def method_to_be_traced(x, y, z, is_traced, expected_metric)
    sleep 0.1
    assert x == 1
    assert y == 2
    assert z == 3
    scope_name = @stats_engine.peek_scope ? @stats_engine.peek_scope.name : nil
    if is_traced
      assert_equal expected_metric, scope_name
    else
      assert_not_equal expected_metric, scope_name
    end
  end
  
  def method_with_block(x, y, z, is_traced, expected_metric, &block)
    sleep 0.1
    assert x == 1
    assert y == 2
    assert z == 3
    block.call(@stats_engine.peek_scope.name)
    
    scope_name = @stats_engine.peek_scope ? @stats_engine.peek_scope.name : nil
    assert((expected_metric == scope_name) == is_traced)
  end
  
  def method_c1
    method_c2
  end
  
  def method_c2
    method_c3
  end
  
  def method_c3
  end
  
end
