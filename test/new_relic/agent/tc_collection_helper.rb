require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper')) 
require 'ostruct'
require 'new_relic/agent/model_fixture'

class NewRelic::Agent::CollectionHelperTests < Test::Unit::TestCase
  
  def setup
    super
    NewRelic::Agent::ModelFixture.setup
    NewRelic::Agent.instance.start :test, :test
  end
  def teardown
    NewRelic::Agent::ModelFixture.teardown
    NewRelic::Agent.instance.shutdown
    super
  end
  
  include NewRelic::Agent::CollectionHelper
  def test_string
    val = ('A'..'Z').to_a.join * 100
    assert_equal val.first(256) + "...", normalize_params(val)
  end
  def test_array
    new_array = normalize_params [ 1000 ] * 50
    assert_equal 20, new_array.size
    assert_equal '1000', new_array[0]
  end
  def test_boolean
    np = normalize_params(NewRelic::Config.instance.settings)
    assert_equal false, np['enabled']
  end
  class MyString < String; end
  def test_kind_of_string
    s = MyString.new "This is a string"
    assert_equal "This is a string", s.to_s
    assert_equal MyString, s.class
    assert_equal String, s.to_s.class
    params = normalize_params(:val => [s])
    assert_equal String, params[:val][0].class
    assert_equal String, flatten(s).class
    assert_equal String, truncate(s, 2).class
  end
  def test_number
    np = normalize_params({ 'one' => 1.0, 'two' => '2'})
  end
  def test_nil
    np = normalize_params({ nil => 1.0, 'two' => nil})
    assert_equal "1.0", np['']
    assert_equal nil, np['two']
  end
  def test_hash
    val = ('A'..'Z').to_a.join * 100
    assert_equal Hash["ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEF..." => (("0"*256) + "...")], normalize_params({ val => '0' * 512 })
  end
  class MyHash < Hash
    
  end
  # Test to ensure that hash subclasses are properly converted
  def test_hash_subclass
    h = MyHash.new
    h[:mine] = 'mine'
    custom_params = { :one => {:hash => { :a => :b}, :myhash => h }}
    nh = normalize_params(custom_params)
    myhash = custom_params[:one][:myhash]
    assert_equal MyHash, myhash.class 
    myhash = nh[:one][:myhash]
    assert_equal Hash, myhash.class 
  end
  
  class MyEnumerable
     include Enumerable
     
     def each
       yield "1"
     end
  end
  
  def test_enumerable
    e = MyEnumerable.new
    custom_params = { :one => {:hash => { :a => :b}, :myenum => e }}
    nh = normalize_params(custom_params)
    myenum = nh[:one][:myenum]
    assert_equal ["1"], myenum
  end
  
  
  def test_object
    assert_equal ["foo", '#<OpenStruct z="q">'], normalize_params(['foo', OpenStruct.new('z'=>'q')])
  end
  
  def test_strip_backtrace
    begin
      NewRelic::Agent::ModelFixture.find 0
      flunk "should throw"
    rescue => e
      #      puts e
      #      puts e.backtrace.join("\n")
      #      puts "\n\n"
      clean_trace = strip_nr_from_backtrace(e.backtrace)
      assert_equal 0, clean_trace.grep(/newrelic_rpm/).size, clean_trace.grep(/newrelic_rpm/)
      assert_equal 0, clean_trace.grep(/trace/).size, clean_trace.grep(/trace/)
      assert_equal 3, clean_trace.grep(/find/).size, "should see three frames with 'find' in them: \n#{clean_trace.join("\n")}"
    end
  end
end
