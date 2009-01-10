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

    PAGE_ORIENTATIONS = %w(PORTRAIT LANDSCAPE)
    
    BOOKMARK_ELEMENTS = %w(HEADINGS ANCHORS)

    @@java_path ||= "/usr/bin/java"
    @@jar_path  ||= "#{Rails.root}/extras/pd4ml/pd4ml.jar"
    @@font_path ||= "#{Rails.root}/extras/fonts"

    attr_reader :result
    attr_reader :errors

    def self.default_options
      @default_options ||= {
        :html_width                 => 800,
        :page_dimension             => 'A4',
        :page_orientation           => 'PORTRAIT',
        :inset_unit                 => 'mm',
        :inset_left                 => 20,
        :inset_top                  => 10,
        :inset_right                => 10,
        :inset_bottom               => 10,
        :bookmark_elements          => 'HEADINGS',
        :allow_annotate             => true, 
        :allow_copy                 => true, 
        :allow_modify               => true, 
        :allow_print                => true,
        :debug                      => false
      }
    end

    # Creates a blank PD4ML wrapper, using <tt>format</tt> to
    # indicate whether the output will be HTML, PDF or PS. The format
    # defaults to PDF, and can change using one of the module
    # contants.
    def initialize(options = {})
      @options = self.class.default_options.merge(options)
      @content = ""
      @command_options = ""
      @pdf_password = nil
      @tempfiles = []
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
    
    def self.font_path
      @@font_path
    end
    
    def self.font_path=(value)
      @@font_path = value
    end
    
    def pdf_password=(value)
      @pdf_password = value
    end

    # Sets an option for the wrapper. Only valid PD4ML options will
    # be accepted. The name of the option is a symbol, but the value
    # can be anything. Invalid options will throw an exception. To
    # unset an option, use <tt>nil</tt> as the value. Options with
    # negated counterparts, like <tt>:encryption</tt>, can be set
    # using :no or :none as the value.
    def set_option(option, value)
      if @default_options.keys.include?(option)
        if value_valid_for_option?(option, value)
          @options[option] = value
        end
      else
        raise PD4MLException.new("Invalid option #{option.to_s}")
      end
    end

    def add_content(html_content)
      @content << html_content
    end


    # Invokes PD4ML and generates the output. If an output directory
    # or file is provided, the method will return <tt>true</tt> or
    # <tt>false</tt> to indicate completion. If no output directory or
    # file is provided, it will return a string representing the
    # entire output. Generate will raise a PDF::PD4MLException if
    # the program path can't be found.
    def generate
      # Check if required files are present
      raise PD4MLException.new("Invalid jar path: #{@@jar_path}") unless File.exists? @@jar_path
      raise PD4MLException.new("Invalid java path: #{@@java_path}") unless File.exists? @@java_path
      raise PD4MLException.new("Invalid font path: #{@@font_path}") unless File.exists? @@font_path
      
      # Execute
      logger.info "[PD4ML] command: #{self.pd4ml_command}" if @options[:debug]
      result = IO.popen(self.pd4ml_command) { |s| s.read }

      # Check whether the program really was executed
      if $?.exitstatus == 127
        raise PD4MLException.new("Sorry. Could not run PD4ML. Giving up!")
      else
        return result
      end

    ensure
      @tempfiles.each { |t| t.close }
    end
    
    def save_to(file_path)
      File.open(file_path, 'w') {|f| f.write(self.generate) }
    end

    def input_file
      t = Tempfile.new("pd4ml.html", "#{Rails.root}/tmp")
      t.binmode
      t.write(@content)
      t.flush
      @tempfiles << t
      t.path
    end
    
    def pd4ml_command
      "#{@@java_path} -Xmx512m -Djava.awt.headless=true -cp #{@@jar_path}:.:#{File.dirname(__FILE__)} Pd4Ruby #{self.command_parameters} 2>&1"
    end

    def command_parameters
      command_options = ""
      
      command_options << "--file #{self.input_file} "
      command_options << "--width #{@options[:html_width]} "
      command_options << "--pagesize #{@options[:page_dimension]} "
      command_options << "--orientation #{@options[:page_orientation]} "
      command_options << "--permissions #{self.pdf_permissions} "
      command_options << "--password #{@pdf_password} " unless @pdf_password.blank?
      command_options << "--insets #{self.page_insets} "
      command_options << "--bookmarks #{@options[:bookmark_elements]} "
      command_options << "--ttf #{@@font_path}"
      command_options << "--debug " if @options[:debug]
      
      command_options  
    end
    
    # Builds permissions for the PDF encryption
    # The permission flags are 65472 (decimal) or
    # 1111111111000000 (binary).  Bits 0 and 1 are reserved (always 0), bit
    # 2 is the print permission (0 here, meaning that printing is not
    # allowed), and bits 3, 4, and 5, are the "modify", "copy text", and
    # "add/edit annotations" permissions (all disallowed in this example).
    # The higher bits are reserved.
    def pdf_permissions
      annotate  = @options[:allow_annotate] ? 0 : 1
      print     = @options[:allow_print]    ? 0 : 1
      copy      = @options[:allow_copy]     ? 0 : 1
      modify    = @options[:allow_modify]   ? 0 : 1
      permissions = "1111111111#{annotate}#{copy}#{modify}#{print}00".to_i(2)
      logger.info "[PD4ML] permissions: #{permissions.to_s(2)}" if @options[:debug]
      permissions
    end
    
    # Builds the page insets string to be passed to the JAR file
    def page_insets
      "#{@options[:inset_top]},#{@options[:inset_left]},#{@options[:inset_bottom]},#{@options[:inset_right]},#{@options[:inset_unit]}"
    end
    
    # Return true if the given value for the option is valid
    def value_valid_for_option?(option, value)
      case option
        
      when :html_width          then value.is_a? Fixnum
      when :page_dimension      then PAGE_DIMENSIONS.include? value
      when :page_orientation    then PAGE_ORIENTATIONS.include? value 
      when :inset_unit          then %(mm pt).include? value
      when :inset_left          then value.is_a? Fixnum
      when :inset_top           then value.is_a? Fixnum
      when :inset_right         then value.is_a? Fixnum
      when :inset_bottom        then value.is_a? Fixnum
      when :bookmark_elements   then BOOKMARK_ELEMENTS.include? value
      when :allow_annotate      then [true, false].include? value 
      when :allow_copy          then [true, false].include? value 
      when :allow_modify        then [true, false].include? value 
      when :allow_print         then [true, false].include? value 
      when :debug               then [true, false].include? value  
      end
    end

  end

end
