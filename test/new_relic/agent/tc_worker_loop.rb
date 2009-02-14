require 'test/unit'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 

NewRelic::Agent::WorkerLoop.class_eval do 
  public :run_next_task
end

class NewRelic::Agent::WorkerLoopTests < Test::Unit::TestCase
  def setup
    @log = ""
    @logger = Logger.new(StringIO.new(@log))
    @worker_loop = NewRelic::Agent::WorkerLoop.new(@logger)
    @test_start_time = Time.now
  end
  def test_add_task
    @x = false
    period = 1.0
    @worker_loop.add_task(period) do
      @x = true
    end
    
    assert !@x
    @worker_loop.run_next_task
    assert @x
    check_test_timestamp period
  end
  
  def test_add_tasks_with_different_periods
    @last_executed = nil
    
    period1 = 0.2
    period2 = 0.35
    
    @worker_loop.add_task(period1) do
      @last_executed = 1
    end
    
    @worker_loop.add_task(period2) do
      @last_executed = 2
    end
    
    @worker_loop.run_next_task
    assert_equal @last_executed, 1      # 0.2 s
    check_test_timestamp(0.2)
    
    @worker_loop.run_next_task
    assert_equal @last_executed, 2      # 0.35 s
    check_test_timestamp(0.35)
    
    @worker_loop.run_next_task
    assert_equal @last_executed, 1      # 0.4 s
    check_test_timestamp(0.4)
    
    @worker_loop.run_next_task
    assert_equal @last_executed, 1      # 0.6 s
    check_test_timestamp(0.6)
    
    @worker_loop.run_next_task
    assert_equal @last_executed, 2      # 0.7 s
    check_test_timestamp(0.7)
  end
  
  def test_task_error__standard
    @worker_loop.add_task(0.2) do
      raise "Standard Error Test"
    end
    # Should not throw
    @logger.expects(:error).once
    @logger.expects(:debug).never
    @worker_loop.run_next_task
    
  end
  def test_task_error__runtime
    @worker_loop.add_task(0.2) do
      raise RuntimeError, "Runtime Error Test"
    end
    # Should not throw, but log at error level
    # because it detects no agent listener inthe
    # stack
    @logger.expects(:error).once
    @logger.expects(:debug).never
    @worker_loop.run_next_task
  end

  def test_task_error__server
    @worker_loop.add_task(0.2) do
      raise NewRelic::Agent::ServerError, "Runtime Error Test"
    end
    # Should not throw
    @logger.expects(:error).never
    @logger.expects(:debug).once
    @worker_loop.run_next_task
  end
  
  private
  def check_test_timestamp(expected)
    ts = Time.now - @test_start_time
    delta = (expected - ts).abs
    assert(delta < 0.05, "#{delta} exceeds 50 milliseconds")
  end
end
