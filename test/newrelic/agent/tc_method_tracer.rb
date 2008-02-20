require File.join(File.dirname(__FILE__),'mock_agent')
require 'newrelic/agent/method_tracer'
require 'test/unit'

::RPM_TRACERS_ENABLED = true unless defined? ::RPM_TRACERS_ENABLED

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
    
    class MethodTracerTests < Test::Unit::TestCase
      attr_reader :stats_engine
      
      def setup
        @stats_engine = Agent.instance.stats_engine
        @stats_engine.reset
      end
      
      def teardown
        self.class.remove_method_tracer :method_to_be_traced, @metric_name if @metric_name
        @metric_name = nil
      end
      
      def test_basic
        metric = "hello"
        t1 = Time.now
        self.class.trace_method_execution metric do
          sleep 0.1
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
        self.class.add_method_tracer :method_to_be_traced, METRIC
        
        t1 = Time.now
        method_to_be_traced 1,2,3,true,METRIC
        elapsed = Time.now - t1
        
        stats = @stats_engine.get_stats(METRIC)
        check_time stats.total_call_time, elapsed
        assert stats.call_count == 1
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
      
      def MethodTracerTests.static_method(x, testcase, is_traced)
        testcase.assert x == "x"
        testcase.assert((testcase.stats_engine.peek_scope.name == "x") == is_traced)
      end

      def trace_trace_static_method
        self.add_method_tracer :static_method, '#{args[0]}'
        self.class.static_method "x", self, true
        self.remove_method_tracer :static_method, '#{args[0]}'
        self.class.static_method "x", self, false
      end
        
      def test_execption
        begin
          metric = "hey there"
          self.class.trace_method_execution metric do
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
        self.class.add_method_tracer :method_to_be_traced, 'X', false
        method_to_be_traced 1,2,3,true,nil
        self.class.add_method_tracer :method_to_be_traced, 'Y'
        method_to_be_traced 1,2,3,true,'Y'
        self.class.remove_method_tracer :method_to_be_traced, 'Y'
        method_to_be_traced 1,2,3,true,nil
        self.class.remove_method_tracer :method_to_be_traced, 'X'
        method_to_be_traced 1,2,3,false,'X'
      end
      
      def trace_no_push_scope
        self.class.add_method_tracer :method_to_be_traced, 'X', false
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
        assert((expected_metric == scope_name) == is_traced)
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
    end
  end
end

