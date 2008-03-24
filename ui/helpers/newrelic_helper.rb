require 'pathname'

module NewrelicHelper
  
  # return the sample but post processed to strip out segments that normally don't show
  # up in production (after the first execution, at least) such as application code loading
  def stripped_sample(sample = @sample)
    if session[:newrelic_strip_code_loading] || true
      sample.omit_segments_with('(Rails/Application Code Loading)|(Database/.*/.+ Columns)')
    else
      sample
    end
  end
  
  def sql_caller(trace)
    trace.each do |trace_line|
      file = trace_line.split(':').first
      unless exclude_file_from_stack_trace?(file)
        return trace_line
      end
    end
    trace.last
  end
  
  def trace_without_agent(trace)
    trace.reject do |trace_line|
      file = trace_line.split(':').first
      exclude_file_from_stack_trace?(file)
    end
  end
  
  
  def url_for_source(trace_line)
    s = trace_line.split(':')
    
    begin
      file = Pathname.new(s[0]).realpath
    rescue Errno::ENOENT
      # we hit this exception when Pathame.realpath fails for some reason; attempt a link to
      # the file without a real path.  It may also fail, only when the user clicks on this specific
      # entry in the stack trace
      file = s[0]
    end
      
    line = s[1]
    
    if using_textmate?
      "txmt://open?url=file://#{file}&line=#{line}"
    else
      url_for :action => 'show_source', :file => file, :line => line, :anchor => 'selected_line'
    end
  end
  
  def link_to_source(trace)
    image_url = "http://rpm.newrelic.com/images/"
    # TODO need an image for regular text file
    image_url << (using_textmate? ? "textmate.png" : "file_icon.png")
    
    link_to image_tag(image_url), url_for_source(sql_caller(trace))
  end
  
  def line_wrap_sql(sql)
    sql.gsub(/\,/,', ').squeeze(' ')
  end

  # the rows logger plugin disables the sql tracing functionality of the NewRelic agent -
  # notify the user about this
  def rows_logger_present?
    File.exist?(File.join(File.dirname(__FILE__), "../../../rows_logger/init.rb"))
  end
  
private
  def using_textmate?
    # TODO make this a preference
    false
  end
  
  private 
  def exclude_file_from_stack_trace?(file)
      file =~ /\/newrelic\/agent\// ||
      file =~ /\/activerecord\// ||
      file =~ /\/activesupport\// ||
      file =~ /\/actionpack\//
  end
end
