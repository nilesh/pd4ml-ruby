require "tempfile"

module PDF

  # Exception class representing an internal error in the HTMLDoc
  # class.
  class PD4MLException < StandardError; end

  # The wrapper class around HTMLDOC, providing methods for setting
  # the options for the application and retriving the generate output
  # either as a file, diretory or string.
  class PD4ML

    VERSION = "0.1.0"

    PAGE_DIMENSIONS = %w(A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 HALFLETTER ISOB0 
                         ISOB1 ISOB2 ISOB3 ISOB4 ISOB5 LEDGER LEGAL LETTER 
                         NOTE TABLOID)

    @@basic_options = [ :allow_annotate, :allow_assembly, 
                        :allow_content_extraction, :allow_copy, 
                        :allow_degraded_print, :allow_filling_forms, 
                        :allow_modify, :allow_print]

    # @@extra_options = [:duplex, :embedfonts, :encryption,
    #                    :links, :localfiles, :numbered, :pscommands, :strict, :title,
    #                    :toc, :xrxcomments]
    # @@special_options = [:compression, :jpeg]

    @@all_options = @@basic_options # + @@extra_options + @@special_options

    # The path to HTMLDOC in the system. E.g, <code>/usr/bin/html</code> or
    # <code>"C:\Program Files\HTMLDOC\HTMLDOC.exe"</code>.
    @@java_path = "java"
    @@jar_path = "#{Rails.root}/extras/pd4ml/pd4ml.jar"

    # The last result from the generation of the output file(s). It's
    # a hash comprising three pairs:
    # <tt>bytes</tt>:: The number of bytes generated in the last request or <tt>nil</tt>
    # <tt>pages</tt>:: The number of pages generated in the last request or <tt>nil</tt>
    # <tt>output</tt>:: The raw output of the command
    attr_reader :result

    # The last error messages generate by the command. It's a hash
    # where they key represents the error number, and the value
    # represents the error message. If the error number is zero,
    # HTMLDOC was called with invalid parameters. Errors can happen
    # even if generation succeeds, for example, if an image can't be
    # found in the course of the generation.
    attr_reader :errors

    def self.default_options
      @default_options ||= {
        :dimension                  => 'A4',
        :allow_annotate             => true, 
        :allow_assembly             => true, 
        :allow_content_extraction   => true, 
        :allow_copy                 => true, 
        :allow_degraded_print       => false, 
        :allow_filling_forms        => true, 
        :allow_modify               => true, 
        :allow_print                => true
      }
    end

    # Creates a blank PD4ML wrapper, using <tt>format</tt> to
    # indicate whether the output will be HTML, PDF or PS. The format
    # defaults to PDF, and can change using one of the module
    # contants.
    def initialize(options = {})
      @options = self.class.default_options.merge(options)
      @pages = []
      @tempfiles = []
      reset
    end

    # Creates a blank PD4ML wrapper and passes it to a block. When
    # the block finishes running, the <tt>generate</tt> method is
    # automatically called. The result of <tt>generate</tt> is then
    # passed back to the application.
    def self.create(&block)
      pdf = PD4ML.new
      if block_given?
        yield pdf
        pdf.generate
      end
    end

    # Gets the current path for the PD4ML jar file.
    def self.jar_path
      @@jar_path
    end

    # Sets the current path for the PD4ML jar file.
    def self.jar_path=(value)
      @@jar_path = value
    end
    
    # Gets the current path for the java executable.
    def self.java_path
      @@java_path
    end
    
    # Sets the current path for the java executable.
    def self.java_path=(value)
      @@java_path = value
    end

    # Sets an option for the wrapper. Only valid PD4ML options will
    # be accepted. The name of the option is a symbol, but the value
    # can be anything. Invalid options will throw an exception. To
    # unset an option, use <tt>nil</tt> as the value. Options with
    # negated counterparts, like <tt>:encryption</tt>, can be set
    # using :no or :none as the value.
    def set_option(option, value)
      if @@all_options.include?(option)
        if value
          @options[option] = value
        else
          @options.delete(option)
        end
      else
        raise PD4MLException.new("Invalid option #{option.to_s}")
      end
    end

    # Sets the header. It's the same as set_option :header, value.
    def header(value)
      set_option :header, value
    end

    # Sets the footer. It's the same as set_option :footer, value.
    def footer(value)
      set_option :footer, value
    end

    # Adds a page for generation. The page can be a URL beginning with
    # either <tt>http://</tt> or <tt>https://</tt>; a file, which will
    # be verified for existence; or any text.
    def add_page(page)
      if /^(http|https)/ =~ page
        type = :url
      elsif File.exists?(page)
        type = :file
      else
        type = :text
      end
      @pages << { :type => type, :value => page }
    end

    alias :<< :add_page

    # Adds a title page for generation.
    def add_title_page(body)
      t = Tempfile.new("htmldoc.temp")
      t.binmode
      t.write(body)
      t.flush
      @tempfiles << t
      set_option :titlefile, t.path
    end

    # Invokes HTMLDOC and generates the output. If an output directory
    # or file is provided, the method will return <tt>true</tt> or
    # <tt>false</tt> to indicate completion. If no output directory or
    # file is provided, it will return a string representing the
    # entire output. Generate will raise a PDF::HTMLDocException if
    # the program path can't be found.
    def generate
      tempfile = nil
      unless @options[:outdir] || @options[:outfile]
        tempfile = Tempfile.new("pd4ml.temp", "#{Rails.root}/tmp/")
        @options[:outfile] = tempfile.path
      end
      execute
      if @result[:pages]
        if tempfile
          File.open(tempfile.path, "rb") { |f| f.read }
        else
          true
        end
      else
        false
      end
    ensure
      if tempfile
        tempfile.close
        @options[:outfile] = nil
      end
      @tempfiles.each { |t| t.close }
    end

    private

    def execute
      # Reset internal variables
      reset
      
      # Check if required files are present
      raise PD4MLException.new("Invalid jar path: #{@@jar_path}") unless File.exist? @@jar_path
      raise PD4MLException.new("Invalid java path: #{@@java_path}") unless File.exist? @@java_path
      
      # Execute
      command = "#{@@java_path} -Xmx512m -Djava.awt.headless=true -cp #{@@jar_path}:.:#{File.dirname(__FILE__)} Pd4Ruby #{get_command_options} #{get_command_pages} 2>&1"
      @result[:command] = command
      result = IO.popen(command) { |s| s.read }
      # Check whether the program really was executed
      if $?.exitstatus == 127
        raise PD4MLException.new("Sorry. Could not run PD4ML. Giving up!")
      else
        @result[:output] = result
        result.split("\n").each do |line|
          case line
            when /^BYTES: (\d+)/
              @result[:bytes] = $1.to_i
            when /^PAGES: (\d+)/
              @result[:pages] = $1.to_i
            when /^ERROR: (.*)$/
              @errors[0] = $1.strip
            when /^ERR(\d+): (.*)$/
              @errors[$1.to_i] = $2.strip
          end
        end
      end
    end

    def reset
      @result = { :bytes => nil, :pages => nil, :output => nil }
      @errors = { }
    end

    def get_command_pages
      pages = @pages.collect do |page|
        case page[:type]
          when :file, :url
            page[:value]
          else
            t = Tempfile.new("htmldoc.temp")
            t.binmode
            t.write(page[:value])
            t.flush
            @tempfiles << t
            t.path
        end
      end
      pages.join(" ")
    end

    def get_command_options
      options = @options.dup.merge({ :format => @format })
      options = options.collect { |key, value| get_final_value(key, value) }
      options.sort.join(" ")
    end

    def get_final_value(option, value)
      option_name = "--" + option.to_s.gsub("_", "-")
      if value.kind_of?(TrueClass)
        option_name
      elsif value.kind_of?(Hash)
        items = value.collect { |name, contents| "#{name.to_s}=#{contents.to_s}" }
        option_name + " '" + items.sort.join(";") + "'"
      elsif @@basic_options.include?(option)
        option_name + " " + value.to_s
      elsif @@special_options.include?(option)
        option_name + "=" + value.to_s
      else
        if [false, :no, :none].include?(value)
          option_name.sub("--", "--no-")
        else
          option_name + " " + value.to_s
        end
      end
    end

  end

end
